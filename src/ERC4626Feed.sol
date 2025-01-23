// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {AggregatorV3Interface} from "@morpho-blue-oracles/morpho-chainlink/interfaces/AggregatorV3Interface.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract ERC4626Feed is AggregatorV3Interface {
    using Math for uint256;

    uint256 public constant version = 1;
    IERC4626 public immutable vault;
    IERC20Metadata public immutable token;
    uint8 public immutable decimals;
    string public description;

    uint256 public immutable ONE_SHARE;
    uint256 public immutable ONE_ASSET;

    constructor(IERC4626 _vault, uint8 _decimals) {
        vault = _vault;
        token = IERC20Metadata(_vault.asset());
        if (_decimals == 0) {
            decimals = token.decimals();
        } else {
            decimals = _decimals;
        }
        description = string.concat(vault.symbol(), " / ", token.symbol());
        ONE_SHARE = 10 ** vault.decimals();
        ONE_ASSET = 10 ** token.decimals();
    }

    function getPrice() public view returns (uint256) {
        uint256 price = vault.convertToAssets(ONE_SHARE);
        return price.mulDiv(10**decimals, ONE_ASSET);
    }

    function _latestRoundData() internal view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        uint256 price = getPrice();
        uint256 timestamp = block.timestamp;
        return (1, int256(price), timestamp, timestamp, 1);
    }

    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        return _latestRoundData();
    }

    function getRoundData(uint80 _roundId) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
        return _latestRoundData();
    }
}
