// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DummyFeed} from "../src/DummyFeed.sol";
import {DummyFeedFactory} from "../src/DummyFeedFactory.sol";

contract DummyFeedTest is Test {
    function testConstructor() public {
        DummyFeed feed = new DummyFeed(8);

        assertEq(feed.decimals(), 8);
        assertEq(feed.ONE(), 1e8);
        assertEq(feed.version(), 1);
        assertEq(feed.description(), "Dummy feed with 8 decimals");
    }

    function testGetPriceIsOneForDifferentDecimals() public {
        uint8[4] memory decimalsList = [uint8(0), 6, 8, 18];

        for (uint256 i = 0; i < decimalsList.length; i++) {
            DummyFeed feed = new DummyFeed(decimalsList[i]);

            assertEq(feed.getPrice(), 10 ** decimalsList[i]);
        }
    }

    function testLatestRoundData() public {
        DummyFeed feed = new DummyFeed(18);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            feed.latestRoundData();

        assertEq(roundId, 1);
        assertEq(answer, int256(1e18));
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 1);
    }

    function testGetRoundDataIgnoresRoundId() public {
        DummyFeed feed = new DummyFeed(6);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            feed.getRoundData(42);

        assertEq(roundId, 1);
        assertEq(answer, int256(1e6));
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 1);
    }

    function testLatestRoundDataTracksBlockTimestamp() public {
        DummyFeed feed = new DummyFeed(8);

        vm.warp(block.timestamp + 1 days);

        (,, uint256 startedAt, uint256 updatedAt,) = feed.latestRoundData();

        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
    }

    function testConstructorRevertsWhenOneOverflows() public {
        // 10 ** 78 does not fit in a uint256
        vm.expectRevert();
        new DummyFeed(78);
    }
}

contract DummyFeedFactoryTest is Test {
    event DummyFeedDeployed(address indexed dummyFeedAddress, uint8 decimals);

    DummyFeedFactory public factory;

    function setUp() public {
        factory = new DummyFeedFactory();
    }

    function testDeployDummyFeed() public {
        DummyFeed feed = factory.deployDummyFeed(8);

        assertEq(feed.decimals(), 8);
        assertEq(feed.getPrice(), 1e8);
        assertEq(feed.description(), "Dummy feed with 8 decimals");
    }

    function testDeployDummyFeedEmitsEvent() public {
        // The deployed address is not known up front, so only the data (decimals) is checked.
        vm.expectEmit(false, false, false, true, address(factory));
        emit DummyFeedDeployed(address(0), 18);
        factory.deployDummyFeed(18);
    }

    function testDeployDummyFeedReturnsDistinctInstances() public {
        DummyFeed feedA = factory.deployDummyFeed(6);
        DummyFeed feedB = factory.deployDummyFeed(6);

        assertTrue(address(feedA) != address(feedB));
    }
}
