// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {DummyFeed} from "./DummyFeed.sol";

/// @title DummyFeedFactory
/// @author Steakhouse Financial
/// @notice Factory for deploying DummyFeed instances.
contract DummyFeedFactory {

    event DummyFeedDeployed(
        address indexed dummyFeedAddress,
        uint8 decimals
    );

    /// @notice Deploys a new DummyFeed contract.
    /// @param _decimals The number of decimals for the oracle output.
    /// @return dummyFeed The newly deployed DummyFeed contract.
    function deployDummyFeed(
        uint8 _decimals
    ) external returns (DummyFeed dummyFeed) {
        dummyFeed = new DummyFeed(_decimals);

        emit DummyFeedDeployed(
            address(dummyFeed),
            _decimals
        );
    }
}