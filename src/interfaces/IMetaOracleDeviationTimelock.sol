// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IOracle} from "./IOracle.sol";

/// @title IMetaOracleDeviationTimelock
/// @notice Interface for the MetaOracleDeviationTimelock contract, extending IOracle.
interface IMetaOracleDeviationTimelock is IOracle {
    // --- Events (Mirroring implementation) ---
    event ChallengeStarted(uint256 expiresAt);
    event ChallengeRevoked();
    event ChallengeAccepted(address indexed newOracle);
    event HealingStarted(uint256 expiresAt);
    event HealingRevoked();
    event HealingAccepted(address indexed newOracle);

    // --- Configuration --- Accessors for state variables set during initialization
    function primaryOracle() external view returns (IOracle);
    function backupOracle() external view returns (IOracle);
    function primaryPrice() external view returns (uint256);
    function backupPrice() external view returns (uint256);
    function deviationThreshold() external view returns (uint256);
    function challengeTimelockDuration() external view returns (uint256);
    function healingTimelockDuration() external view returns (uint256);

    // --- State --- Accessors for dynamic state variables
    function currentOracle() external view returns (IOracle);
    function challengeExpiresAt() external view returns (uint256);
    function healingExpiresAt() external view returns (uint256);

    // --- Views ---
    function isPrimary() external view returns (bool);
    function isBackup() external view returns (bool);
    function isChallenged() external view returns (bool);
    function isHealing() external view returns (bool);
    function getDeviation() external view returns (uint256);
    function isDeviant() external view returns (bool);
    function hasChallengeExpired() external view returns (bool);
    function hasHealingExpired() external view returns (bool);
    function canAcceptChallenge() external view returns (bool);
    function canAcceptHealing() external view returns (bool);

    // --- State Changing Functions ---
    function challenge() external;
    function revokeChallenge() external;
    function acceptChallenge() external;
    function heal() external;
    function revokeHealing() external;
    function acceptHealing() external;
} 