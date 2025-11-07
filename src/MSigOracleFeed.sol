// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@morpho-blue-oracles/morpho-chainlink/interfaces/AggregatorV3Interface.sol";

/**
 * @title MSigOracleFeed
 * @notice A Chainlink-compatible oracle controlled by a single address (EOA or multisig)
 * @dev Implements AggregatorV3Interface with price deviation protection
 */
contract MSigOracleFeed is AggregatorV3Interface {

    /// @notice The address authorized to update the price
    address public immutable controller;

    /// @notice The number of decimals in the returned price
    uint8 public immutable decimals;

    /// @notice Human-readable description of the price feed
    string public description;

    /// @notice Maximum allowed deviation from current price (scaled by 1e18, e.g., 0.1e18 for 10%)
    uint256 public immutable maxSafeDeviation;

    /// @notice Current price value
    int256 private _price;

    /// @notice Current round ID
    uint80 private _roundId;

    /// @notice Timestamp of last update
    uint256 private _updatedAt;

    /// @notice Version of the price feed implementation
    uint256 public constant version = 1;

    // Events
    event PriceUpdated(uint80 indexed roundId, int256 price, address indexed updatedBy);
    event PriceForceUpdated(uint80 indexed roundId, int256 price, address indexed updatedBy);

    // Errors
    error Unauthorized();
    error InvalidPrice();
    error DeviationTooHigh(int256 oldPrice, int256 newPrice, uint256 deviation, uint256 maxDeviation);

    /**
     * @notice Constructs a new MSigOracleFeed
     * @param _controller The address authorized to update prices
     * @param _initialPrice The initial price value
     * @param _maxSafeDeviation Maximum allowed price deviation (scaled by 1e18)
     * @param _decimals The number of decimals for the oracle output
     * @param _description Human-readable description
     */
    constructor(
        address _controller,
        int256 _initialPrice,
        uint256 _maxSafeDeviation,
        uint8 _decimals,
        string memory _description
    ) {
        require(_controller != address(0), "Invalid controller");
        require(_initialPrice > 0, "Invalid initial price");

        controller = _controller;
        _price = _initialPrice;
        maxSafeDeviation = _maxSafeDeviation;
        decimals = _decimals;
        description = _description;

        _roundId = 1;
        _updatedAt = block.timestamp;

        emit PriceUpdated(1, _initialPrice, msg.sender);
    }

    /**
     * @notice Updates the price with deviation check
     * @dev Reverts if the new price deviates more than maxSafeDeviation from current price
     * @param newPrice The new price to set
     */
    function setPrice(int256 newPrice) external {
        if (msg.sender != controller) revert Unauthorized();
        if (newPrice <= 0) revert InvalidPrice();

        // Check deviation
        uint256 deviation = _calculateDeviation(_price, newPrice);
        if (deviation > maxSafeDeviation) {
            revert DeviationTooHigh(_price, newPrice, deviation, maxSafeDeviation);
        }

        _updatePrice(newPrice);
        emit PriceUpdated(_roundId, newPrice, msg.sender);
    }

    /**
     * @notice Updates the price without deviation check
     * @dev Should be used carefully, only when large price movements are legitimate
     * @param newPrice The new price to set
     */
    function setPriceForce(int256 newPrice) external {
        if (msg.sender != controller) revert Unauthorized();
        if (newPrice <= 0) revert InvalidPrice();

        _updatePrice(newPrice);
        emit PriceForceUpdated(_roundId, newPrice, msg.sender);
    }

    /**
     * @notice Internal function to update price and round data
     * @param newPrice The new price value
     */
    function _updatePrice(int256 newPrice) private {
        _price = newPrice;
        _roundId++;
        _updatedAt = block.timestamp;
    }

    /**
     * @notice Calculates the relative deviation between two prices
     * @dev Returns deviation scaled by 1e18 (e.g., 0.1e18 = 10%)
     * @param oldPrice The original price
     * @param newPrice The new price
     * @return The deviation scaled by 1e18
     */
    function _calculateDeviation(int256 oldPrice, int256 newPrice) private pure returns (uint256) {
        if (oldPrice == newPrice) return 0;

        // Calculate absolute difference
        uint256 diff;
        if (newPrice > oldPrice) {
            diff = uint256(newPrice - oldPrice);
        } else {
            diff = uint256(oldPrice - newPrice);
        }

        // Calculate relative deviation: (diff / oldPrice) * 1e18
        return (diff * 1e18) / uint256(oldPrice);
    }

    /**
     * @notice Get the latest round data (implements AggregatorV3Interface)
     * @return roundId The round ID
     * @return answer The current price
     * @return startedAt The timestamp when the round started
     * @return updatedAt The timestamp when the round was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }

    /**
     * @notice Get data from a specific round (implements AggregatorV3Interface)
     * @dev This contract does not maintain historical data, so it always returns the latest data
     * @param _requestedRoundId The round ID (ignored)
     * @return roundId The current round ID
     * @return answer The current price
     * @return startedAt The timestamp when the round started
     * @return updatedAt The timestamp when the round was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function getRoundData(uint80 _requestedRoundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        // For simplicity, always return latest data regardless of requested round
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }
}
