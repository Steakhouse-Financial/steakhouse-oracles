// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IMetaOracleDeviationTimelock} from "./interfaces/IMetaOracleDeviationTimelock.sol";
import {IOracle} from "./interfaces/IOracle.sol";

/// @title MetaOracleDeviationTimelock
/// @author Steakhouse Financial
/// @notice A meta-oracle that selects between a primary and backup oracle based on price deviation and timelocks.
/// @dev Switches to backup if primary deviates significantly, switches back when prices reconverge.
/// MUST be initialized by calling the `initialize` function.
contract MetaOracleDeviationTimelock is IMetaOracleDeviationTimelock, Initializable {
    // --- Configuration (set during initialization) ---
    IOracle public primaryOracle;
    IOracle public backupOracle;
    uint256 public deviationThreshold; // Scaled by 1e18 (e.g., 0.01e18 for 1%)
    uint256 public challengeTimelockDuration; // Duration in seconds
    uint256 public healingTimelockDuration; // Duration in seconds

    // --- State ---
    IOracle public currentOracle; // Currently selected oracle
    uint256 public challengeExpiresAt; // Timestamp when challenge period ends (0 if not challenged)
    uint256 public healingExpiresAt; // Timestamp when healing period ends (0 if not healing)

    /// @param _primaryOracle The primary price feed.
    /// @param _backupOracle The backup price feed.
    /// @param _deviationThreshold The maximum allowed relative deviation (scaled by 1e18) before a challenge can be initiated.
    /// @param _challengeTimelockDuration The duration (seconds) a challenge must persist before switching to backup.
    /// @param _healingTimelockDuration The duration (seconds) prices must remain converged before switching back to primary.
    function initialize(
        IOracle _primaryOracle,
        IOracle _backupOracle,
        uint256 _deviationThreshold,
        uint256 _challengeTimelockDuration,
        uint256 _healingTimelockDuration
    ) external initializer {
        require(address(_primaryOracle) != address(0), "Invalid primary oracle");
        require(address(_backupOracle) != address(0), "Invalid backup oracle");
        require(address(_primaryOracle) != address(_backupOracle), "Oracles must be different");
        require(_deviationThreshold > 0, "Deviation threshold must be positive");

        primaryOracle = _primaryOracle;
        backupOracle = _backupOracle;
        deviationThreshold = _deviationThreshold;
        challengeTimelockDuration = _challengeTimelockDuration;
        healingTimelockDuration = _healingTimelockDuration;

        // Check initial deviation
        uint256 initialPrimaryPrice = _primaryOracle.price();
        uint256 initialBackupPrice = _backupOracle.price();
        uint256 initialDeviation;
        if (initialBackupPrice == 0) {
            initialDeviation = initialPrimaryPrice == 0 ? 0 : type(uint256).max;
        } else {
            uint256 diff;
            if (initialPrimaryPrice >= initialBackupPrice) {
                diff = initialPrimaryPrice - initialBackupPrice;
            } else {
                diff = initialBackupPrice - initialPrimaryPrice;
            }
            initialDeviation = (diff * 10**18) / initialBackupPrice;
        }
        require(initialDeviation <= _deviationThreshold, "MODT: Initial deviation too high");

        currentOracle = _primaryOracle; // Start with the primary oracle
    }

    /// @inheritdoc IOracle
    function price() public view returns (uint256) {
        try currentOracle.price() returns (uint256 currentPrice) {
            return currentPrice;
        } catch {
            if (isPrimary()) {
                return backupOracle.price();
            } else {
                return primaryOracle.price();
            }
        }
    }

    /// @inheritdoc IMetaOracleDeviationTimelock
    function primaryPrice() public view returns (uint256) {
        return primaryOracle.price();
    }

    /// @inheritdoc IMetaOracleDeviationTimelock
    function backupPrice() public view returns (uint256) {
        return backupOracle.price();
    }

    /// @notice Checks if the primary oracle is currently selected.
    function isPrimary() public view returns (bool) {
        return currentOracle == primaryOracle;
    }

    /// @notice Checks if the backup oracle is currently selected.
    function isBackup() public view returns (bool) {
        return currentOracle == backupOracle;
    }

    /// @notice Checks if a challenge is currently active.
    function isChallenged() public view returns (bool) {
        return challengeExpiresAt > 0;
    }

    /// @notice Checks if a healing period is currently active.
    function isHealing() public view returns (bool) {
        return healingExpiresAt > 0;
    }

    /// @notice Calculates the absolute relative deviation between primary and backup oracles.
    /// @dev Deviation is calculated as `abs(primaryPrice - backupPrice) * 1e18 / backupPrice`.
    /// Returns 0 if backupPrice is 0 and primaryPrice is 0.
    /// Returns type(uint256).max if backupPrice is 0 and primaryPrice is non-zero.
    function getDeviation() public view returns (uint256) {
        uint256 currentPrimaryPrice = primaryOracle.price();
        uint256 currentBackupPrice = backupOracle.price();

        if (currentBackupPrice == 0) {
            return currentPrimaryPrice == 0 ? 0 : type(uint256).max;
        }

        uint256 diff;
        if (currentPrimaryPrice >= currentBackupPrice) {
            diff = currentPrimaryPrice - currentBackupPrice;
        } else {
            diff = currentBackupPrice - currentPrimaryPrice;
        }

        // Use uint256 for intermediate multiplication to avoid overflow before division
        return (diff * 10**18) / currentBackupPrice;
    }

    /// @notice Checks if the deviation exceeds the configured threshold.
    function isDeviant() public view returns (bool) {
        return getDeviation() > deviationThreshold;
    }

    /// @notice Initiates a challenge if the primary oracle is active and deviation threshold is exceeded.
    /// @dev Starts a timelock period (`challengeTimelockDuration`).
    function challenge() external {
        require(isPrimary(), "MODT: Must be primary oracle");
        require(!isChallenged(), "MODT: Already challenged");
        require(isDeviant(), "MODT: Deviation threshold not met");

        challengeExpiresAt = block.timestamp + challengeTimelockDuration;
        emit ChallengeStarted(challengeExpiresAt);
    }

    /// @notice Revokes an active challenge if the deviation is no longer present.
    function revokeChallenge() external {
        require(isPrimary(), "MODT: Must be primary oracle"); // Should still be primary
        require(isChallenged(), "MODT: Not challenged");
        require(!isDeviant(), "MODT: Deviation threshold still met");

        challengeExpiresAt = 0;
        emit ChallengeRevoked();
    }

    /// @notice Checks if the challenge has expired.
    function hasChallengeExpired() public view returns (bool) {
        return isChallenged() && block.timestamp >= challengeExpiresAt;
    }

    /// @notice Checks if the challenge can be accepted.
    function canAcceptChallenge() public view returns (bool) {
        return isPrimary() && isChallenged() && block.timestamp >= challengeExpiresAt && isDeviant();
    }

    /// @notice Accepts the challenge after the timelock expires, switching to the backup oracle.
    /// @dev Requires the deviation to still be present.
    function acceptChallenge() external {
        require(isPrimary(), "MODT: Must be primary oracle");
        require(isChallenged(), "MODT: Not challenged");
        require(block.timestamp >= challengeExpiresAt, "MODT: Challenge timelock not passed");
        require(isDeviant(), "MODT: Deviation resolved"); // Deviation must persist

        currentOracle = backupOracle;
        challengeExpiresAt = 0;
        emit ChallengeAccepted(address(currentOracle));
    }

    /// @notice Initiates the healing process if the backup oracle is active and prices have reconverged.
    /// @dev Starts a timelock period (`healingTimelockDuration`).
    function heal() external {
        require(isBackup(), "MODT: Must be backup oracle");
        require(!isHealing(), "MODT: Already healing");
        require(!isDeviant(), "MODT: Deviation threshold still met");

        healingExpiresAt = block.timestamp + healingTimelockDuration;
        emit HealingStarted(healingExpiresAt);
    }

    /// @notice Revokes an active healing process if the deviation threshold is exceeded again.
    function revokeHealing() external {
        require(isBackup(), "MODT: Must be backup oracle"); // Should still be backup
        require(isHealing(), "MODT: Not healing");
        require(isDeviant(), "MODT: Deviation threshold not met");

        healingExpiresAt = 0;
        emit HealingRevoked();
    }

    /// @notice Checks if the healing has expired.
    function hasHealingExpired() public view returns (bool) {
        return isHealing() && block.timestamp >= healingExpiresAt;
    }

    /// @notice Checks if the healing can be accepted.
    function canAcceptHealing() public view returns (bool) {
        return isBackup() && isHealing() && block.timestamp >= healingExpiresAt && !isDeviant();
    }

    /// @notice Accepts the healing after the timelock expires, switching back to the primary oracle.
    /// @dev Requires the prices to still be converged (not deviant).
    function acceptHealing() external {
        require(isBackup(), "MODT: Must be backup oracle");
        require(isHealing(), "MODT: Not healing");
        require(block.timestamp >= healingExpiresAt, "MODT: Healing timelock not passed");
        require(!isDeviant(), "MODT: Deviation occurred"); // Prices must remain converged

        currentOracle = primaryOracle;
        healingExpiresAt = 0;
        emit HealingAccepted(address(currentOracle));
    }
}