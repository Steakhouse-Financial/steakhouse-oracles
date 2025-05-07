// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {MetaOracleDeviationTimelock} from "./MetaOracleDeviationTimelock.sol";
import {IMetaOracleDeviationTimelock} from "./interfaces/IMetaOracleDeviationTimelock.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IOracle} from "./interfaces/IOracle.sol";

/// @title MetaOracleDeviationTimelockFactory
/// @author Steakhouse Financial
/// @notice Factory for deploying MetaOracleDeviationTimelock instances using EIP-1167 proxies.
contract MetaOracleDeviationTimelockFactory {
    address public immutable implementation;

    event MetaOracleDeployed(
        address indexed metaOracleAddress,
        address implementationAddress,
        address indexed primaryOracle,
        address indexed backupOracle,
        uint256 deviationThreshold,
        uint256 challengeTimelockDuration,
        uint256 healingTimelockDuration
    );

    constructor() {
        implementation = address(new MetaOracleDeviationTimelock());
    }

    /// @notice Deploys a new MetaOracleDeviationTimelock proxy contract and initializes it.
    /// @param _primaryOracle The primary price feed address.
    /// @param _backupOracle The backup price feed address.
    /// @param _deviationThreshold The max relative deviation (1e18 scale).
    /// @param _challengeTimelockDuration Duration (seconds) before challenge can be accepted.
    /// @param _healingTimelockDuration Duration (seconds) before healing can be accepted.
    /// @return proxyInstance The interface of the newly deployed MetaOracleDeviationTimelock proxy contract.
    function deployMetaOracle(
        IOracle _primaryOracle,
        IOracle _backupOracle,
        uint256 _deviationThreshold,
        uint256 _challengeTimelockDuration,
        uint256 _healingTimelockDuration
    ) external returns (IMetaOracleDeviationTimelock proxyInstance) {
        address proxy = Clones.clone(implementation);
        proxyInstance = IMetaOracleDeviationTimelock(proxy);

        // Initialize the proxy
        MetaOracleDeviationTimelock(proxy).initialize(
            _primaryOracle,
            _backupOracle,
            _deviationThreshold,
            _challengeTimelockDuration,
            _healingTimelockDuration
        );

        emit MetaOracleDeployed(
            address(proxyInstance),
            implementation,
            address(_primaryOracle),
            address(_backupOracle),
            _deviationThreshold,
            _challengeTimelockDuration,
            _healingTimelockDuration
        );
    }
} 