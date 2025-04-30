// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {MetaOracleDeviationTimelock, IOracle} from "./MetaOracleDeviationTimelock.sol";

/// @title MetaOracleDeviationTimelockFactory
/// @author Steakhouse Financial
/// @notice Factory for deploying MetaOracleDeviationTimelock instances.
contract MetaOracleDeviationTimelockFactory {
    event MetaOracleDeployed(
        address indexed metaOracleAddress,
        address indexed primaryOracle,
        address indexed backupOracle,
        uint256 deviationThreshold,
        uint256 challengeTimelockDuration,
        uint256 healingTimelockDuration
    );

    /// @notice Deploys a new MetaOracleDeviationTimelock contract.
    /// @param _primaryOracle The primary price feed address.
    /// @param _backupOracle The backup price feed address.
    /// @param _deviationThreshold The max relative deviation (1e18 scale).
    /// @param _challengeTimelockDuration Duration (seconds) before challenge can be accepted.
    /// @param _healingTimelockDuration Duration (seconds) before healing can be accepted.
    /// @return metaOracleInstance The address of the newly deployed MetaOracleDeviationTimelock.
    function deployMetaOracle(
        IOracle _primaryOracle,
        IOracle _backupOracle,
        uint256 _deviationThreshold,
        uint256 _challengeTimelockDuration,
        uint256 _healingTimelockDuration
    ) external returns (MetaOracleDeviationTimelock metaOracleInstance) {
        metaOracleInstance = new MetaOracleDeviationTimelock(
            _primaryOracle,
            _backupOracle,
            _deviationThreshold,
            _challengeTimelockDuration,
            _healingTimelockDuration
        );

        emit MetaOracleDeployed(
            address(metaOracleInstance),
            address(_primaryOracle),
            address(_backupOracle),
            _deviationThreshold,
            _challengeTimelockDuration,
            _healingTimelockDuration
        );
    }
} 