// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/// @title IOracle
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Interface that oracles used by Morpho must implement.
/// @dev It is the user's responsibility to select markets with safe oracles.
interface IOracle {
    /// @notice Returns the price of 1 asset of collateral token quoted in 1 asset of loan token, scaled by 1e36.
    /// @dev It corresponds to the price of 10**(collateral token decimals) assets of collateral token quoted in
    /// 10**(loan token decimals) assets of loan token with `36 + loan token decimals - collateral token decimals`
    /// decimals of precision.
    function price() external view returns (uint256);
}

/// @title MetaOracleDeviationTimelock
/// @author Steakhouse Financial
/// @notice A meta-oracle that selects between a primary and backup oracle based on price deviation and timelocks.
/// @dev Switches to backup if primary deviates significantly, switches back when prices reconverge.
contract MetaOracleDeviationTimelock is IOracle {
    IOracle public immutable primaryOracle;
    IOracle public immutable backupOracle;
    uint256 public immutable deviationThreshold; // Scaled by 1e18 (e.g., 0.01e18 for 1%)
    uint256 public immutable challengeTimelockDuration; // Duration in seconds
    uint256 public immutable healingTimelockDuration; // Duration in seconds

    IOracle public currentOracle; // Currently selected oracle
    uint256 public challengeExpiresAt; // Timestamp when challenge period ends (0 if not challenged)
    uint256 public healingExpiresAt; // Timestamp when healing period ends (0 if not healing)

    /// @param _primaryOracle The primary price feed.
    /// @param _backupOracle The backup price feed.
    /// @param _deviationThreshold The maximum allowed relative deviation (scaled by 1e18) before a challenge can be initiated.
    /// @param _challengeTimelockDuration The duration (seconds) a challenge must persist before switching to backup.
    /// @param _healingTimelockDuration The duration (seconds) prices must remain converged before switching back to primary.
    constructor(
        IOracle _primaryOracle,
        IOracle _backupOracle,
        uint256 _deviationThreshold,
        uint256 _challengeTimelockDuration,
        uint256 _healingTimelockDuration
    ) {
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

    event ChallengeStarted(uint256 expiresAt);
    event ChallengeRevoked();
    event ChallengeAccepted(address indexed newOracle);
    event HealingStarted(uint256 expiresAt);
    event HealingRevoked();
    event HealingAccepted(address indexed newOracle);

    /// @inheritdoc IOracle
    function price() public view returns (uint256) {
        return currentOracle.price();
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
        uint256 primaryPrice = primaryOracle.price();
        uint256 backupPrice = backupOracle.price();

        if (backupPrice == 0) {
            return primaryPrice == 0 ? 0 : type(uint256).max;
        }

        uint256 diff;
        if (primaryPrice >= backupPrice) {
            diff = primaryPrice - backupPrice;
        } else {
            diff = backupPrice - primaryPrice;
        }

        // Use uint256 for intermediate multiplication to avoid overflow before division
        return (diff * 10**18) / backupPrice;
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
        require(!isHealing(), "MODT: Cannot challenge while healing"); // Prevent challenging during healing phase
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
        require(!isChallenged(), "MODT: Cannot heal while challenged"); // Prevent healing during challenge phase
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