// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC4626Feed} from "./ERC4626Feed.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title ERC4626FeedFactory
/// @author Steakhouse Financial
/// @notice Factory for deploying ERC4626Feed instances.
contract ERC4626FeedFactory {

    event ERC4626FeedDeployed(
        address indexed erc4626FeedAddress,
        address indexed vault,
        uint8 decimals
    );

    /// @notice Deploys a new ERC4626Feed contract.
    /// @param _vault The ERC4626 vault for which to provide a price feed.
    /// @param _decimals The number of decimals for the oracle output (0 to use the token's decimals).
    /// @return erc4626Feed The newly deployed ERC4626Feed contract.
    function deployERC4626Feed(
        IERC4626 _vault,
        uint8 _decimals
    ) external returns (ERC4626Feed erc4626Feed) {
        erc4626Feed = new ERC4626Feed(_vault, _decimals);

        emit ERC4626FeedDeployed(
            address(erc4626Feed),
            address(_vault),
            _decimals
        );
    }
}