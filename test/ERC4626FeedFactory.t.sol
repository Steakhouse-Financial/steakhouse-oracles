// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC4626Feed} from "../src/ERC4626Feed.sol";
import {ERC4626FeedFactory} from "../src/ERC4626FeedFactory.sol";
import {MockERC4626} from "./mocks/MockERC4626.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract ERC4626FeedFactoryTest is Test {
    event ERC4626FeedDeployed(address indexed erc4626FeedAddress, address indexed vault, uint8 decimals);

    ERC4626FeedFactory public factory;
    MockERC20 public asset;
    MockERC4626 public vault;

    function setUp() public {
        factory = new ERC4626FeedFactory();
        asset = new MockERC20("Test Token", "TEST", 18);
        vault = new MockERC4626(asset, "Vault Test", "vTEST");
    }

    function testDeployERC4626Feed() public {
        ERC4626Feed feed = factory.deployERC4626Feed(vault, 8);

        assertEq(address(feed.vault()), address(vault));
        assertEq(address(feed.token()), address(asset));
        assertEq(feed.decimals(), 8);

        vault.setConvertToAssets(1e18, 2e18);
        assertEq(feed.getPrice(), 2e8);
    }

    function testDeployERC4626FeedWithAssetDecimals() public {
        ERC4626Feed feed = factory.deployERC4626Feed(vault, 0);

        assertEq(feed.decimals(), 18);
    }

    function testDeployERC4626FeedEmitsEvent() public {
        // The deployed address is not known up front, so only the vault topic and data are checked.
        vm.expectEmit(false, true, false, true, address(factory));
        emit ERC4626FeedDeployed(address(0), address(vault), 8);
        factory.deployERC4626Feed(vault, 8);
    }
}
