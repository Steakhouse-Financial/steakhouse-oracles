// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@morpho-blue-oracles/morpho-chainlink/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title DummyFeed
 * @notice A Chainlink price feed compatible oracle that always returns 1 with specified decimals
 * @dev Implements AggregatorV3Interface to provide a constant value of 1, useful for 
 *      adjusting the number of decimals in a Morpho oracle's SCALE_FACTOR
 */
contract DummyFeed is AggregatorV3Interface {

    /// @notice Version of the price feed implementation
    uint256 public constant version = 1;
    
    /// @notice The number of decimals in the returned price
    uint8 public immutable decimals;
    
    /// @notice Human-readable description of the price feed
    string public description;

    /// @notice One unit with the specified number of decimals
    uint256 public immutable ONE;

    /**
     * @notice Constructs a new DummyFeed oracle
     * @param _decimals The number of decimals for the oracle output
     */
    constructor(uint8 _decimals) {
        decimals = _decimals;
        ONE = 10 ** decimals;
        // Set description
        description = string.concat("Dummy feed with ", Strings.toString(decimals), " decimals");
    }

    /**
     * @notice Get the current price, which is always 1 with the specified decimals
     * @dev Always returns 1 * 10^decimals
     * @return The constant value of ONE
     */
    function getPrice() public view returns (uint256) {
        return ONE;
    }

    /**
     * @notice Internal function to get the latest round data
     * @dev Used by both latestRoundData and getRoundData
     * @return roundId The round ID (always 1)
     * @return answer The constant value of 1 with the specified decimals
     * @return startedAt The timestamp when the round started (current block timestamp)
     * @return updatedAt The timestamp when the round was updated (current block timestamp)
     * @return answeredInRound The round ID in which the answer was computed (always 1)
     */
    function _latestRoundData() internal view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        uint256 price = getPrice();
        uint256 timestamp = block.timestamp;
        return (1, int256(price), timestamp, timestamp, 1);
    }

    /**
     * @notice Get the latest round data (implements AggregatorV3Interface)
     * @return roundId The round ID (always 1)
     * @return answer The constant value of 1 with the specified decimals
     * @return startedAt The timestamp when the round started (current block timestamp)
     * @return updatedAt The timestamp when the round was updated (current block timestamp)
     * @return answeredInRound The round ID in which the answer was computed (always 1)
     */
    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        return _latestRoundData();
    }

    /**
     * @notice Get data from a specific round (implements AggregatorV3Interface)
     * @dev This contract does not maintain historical data, so it always returns the latest data
     * @param _roundId The round ID (ignored)
     * @return roundId The round ID (always 1)
     * @return answer The constant value of 1 with the specified decimals
     * @return startedAt The timestamp when the round started (current block timestamp)
     * @return updatedAt The timestamp when the round was updated (current block timestamp)
     * @return answeredInRound The round ID in which the answer was computed (always 1)
     */
    function getRoundData(uint80 _roundId) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        return _latestRoundData();
    }
}
