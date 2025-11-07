// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {MSigOracleFeed} from "./MSigOracleFeed.sol";

/// @title MSigOracleFeedFactory
/// @author Steakhouse Financial
/// @notice Factory for deploying MSigOracleFeed instances.
contract MSigOracleFeedFactory {

    event MSigOracleFeedDeployed(
        address indexed feedAddress,
        address indexed controller,
        int256 initialPrice,
        uint256 maxSafeDeviation,
        uint8 decimals,
        string description
    );

    /// @notice Deploys a new MSigOracleFeed contract.
    /// @param _controller The address authorized to update prices.
    /// @param _initialPrice The initial price value.
    /// @param _maxSafeDeviation Maximum allowed price deviation (scaled by 1e18).
    /// @param _decimals The number of decimals for the oracle output.
    /// @param _description Human-readable description of the feed.
    /// @return feed The newly deployed MSigOracleFeed contract.
    function deployMSigOracleFeed(
        address _controller,
        int256 _initialPrice,
        uint256 _maxSafeDeviation,
        uint8 _decimals,
        string memory _description
    ) external returns (MSigOracleFeed feed) {
        feed = new MSigOracleFeed(
            _controller,
            _initialPrice,
            _maxSafeDeviation,
            _decimals,
            _description
        );

        emit MSigOracleFeedDeployed(
            address(feed),
            _controller,
            _initialPrice,
            _maxSafeDeviation,
            _decimals,
            _description
        );
    }
}
