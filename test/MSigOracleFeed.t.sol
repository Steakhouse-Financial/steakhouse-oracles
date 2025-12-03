// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MSigOracleFeed} from "../src/MSigOracleFeed.sol";
import {MSigOracleFeedFactory} from "../src/MSigOracleFeedFactory.sol";

contract MSigOracleFeedTest is Test {
    MSigOracleFeed public feed;
    MSigOracleFeedFactory public factory;

    address public controller = address(0x1234);
    address public unauthorized = address(0x5678);

    int256 constant INITIAL_PRICE = 1000e8; // $1000 with 8 decimals
    uint256 constant MAX_DEVIATION = 0.1e18; // 10%
    uint8 constant DECIMALS = 8;
    string constant DESCRIPTION = "ETH/USD Test Feed";

    event PriceUpdated(uint80 indexed roundId, int256 price, address indexed updatedBy);
    event PriceForceUpdated(uint80 indexed roundId, int256 price, address indexed updatedBy);

    function setUp() public {
        feed = new MSigOracleFeed(
            controller,
            INITIAL_PRICE,
            MAX_DEVIATION,
            DECIMALS,
            DESCRIPTION
        );
        factory = new MSigOracleFeedFactory();
    }

    // Constructor Tests
    function testConstructor() public view {
        assertEq(feed.controller(), controller);
        assertEq(feed.decimals(), DECIMALS);
        assertEq(feed.description(), DESCRIPTION);
        assertEq(feed.maxSafeDeviation(), MAX_DEVIATION);
        assertEq(feed.version(), 1);
    }

    function testConstructorRevertsOnZeroController() public {
        vm.expectRevert("Invalid controller");
        new MSigOracleFeed(
            address(0),
            INITIAL_PRICE,
            MAX_DEVIATION,
            DECIMALS,
            DESCRIPTION
        );
    }

    function testConstructorRevertsOnZeroPrice() public {
        vm.expectRevert("Invalid initial price");
        new MSigOracleFeed(
            controller,
            0,
            MAX_DEVIATION,
            DECIMALS,
            DESCRIPTION
        );
    }

    function testConstructorRevertsOnNegativePrice() public {
        vm.expectRevert("Invalid initial price");
        new MSigOracleFeed(
            controller,
            -1000e8,
            MAX_DEVIATION,
            DECIMALS,
            DESCRIPTION
        );
    }

    // Chainlink Interface Tests
    function testLatestRoundData() public view {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(roundId, 1);
        assertEq(answer, INITIAL_PRICE);
        assertGt(updatedAt, 0);
        assertEq(startedAt, updatedAt);
        assertEq(answeredInRound, 1);
    }

    function testGetRoundData() public view {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.getRoundData(99); // Arbitrary round ID

        // Should return latest data regardless of requested round
        assertEq(roundId, 1);
        assertEq(answer, INITIAL_PRICE);
        assertGt(updatedAt, 0);
        assertEq(startedAt, updatedAt);
        assertEq(answeredInRound, 1);
    }

    // setPrice Tests
    function testSetPriceWithinDeviation() public {
        int256 newPrice = 1050e8; // 5% increase (within 10% limit)

        vm.prank(controller);
        vm.expectEmit(true, true, false, true);
        emit PriceUpdated(2, newPrice, controller);
        feed.setPrice(newPrice);

        (uint80 roundId, int256 answer,,,) = feed.latestRoundData();
        assertEq(roundId, 2);
        assertEq(answer, newPrice);
    }

    function testSetPriceAtExactDeviation() public {
        int256 newPrice = 1100e8; // Exactly 10% increase

        vm.prank(controller);
        feed.setPrice(newPrice);

        (, int256 answer,,,) = feed.latestRoundData();
        assertEq(answer, newPrice);
    }

    function testSetPriceDecrease() public {
        int256 newPrice = 950e8; // 5% decrease (within 10% limit)

        vm.prank(controller);
        feed.setPrice(newPrice);

        (, int256 answer,,,) = feed.latestRoundData();
        assertEq(answer, newPrice);
    }

    function testSetPriceRevertsOnExcessiveDeviation() public {
        int256 newPrice = 1150e8; // 15% increase (exceeds 10% limit)

        vm.prank(controller);
        vm.expectRevert(
            abi.encodeWithSelector(
                MSigOracleFeed.DeviationTooHigh.selector,
                INITIAL_PRICE,
                newPrice,
                0.15e18, // 15% deviation
                MAX_DEVIATION
            )
        );
        feed.setPrice(newPrice);
    }

    function testSetPriceRevertsOnExcessiveDecrease() public {
        int256 newPrice = 850e8; // 15% decrease (exceeds 10% limit)

        vm.prank(controller);
        vm.expectRevert(
            abi.encodeWithSelector(
                MSigOracleFeed.DeviationTooHigh.selector,
                INITIAL_PRICE,
                newPrice,
                0.15e18, // 15% deviation
                MAX_DEVIATION
            )
        );
        feed.setPrice(newPrice);
    }

    function testSetPriceRevertsOnUnauthorized() public {
        int256 newPrice = 1050e8;

        vm.prank(unauthorized);
        vm.expectRevert(MSigOracleFeed.Unauthorized.selector);
        feed.setPrice(newPrice);
    }

    function testSetPriceRevertsOnZeroPrice() public {
        vm.prank(controller);
        vm.expectRevert(MSigOracleFeed.InvalidPrice.selector);
        feed.setPrice(0);
    }

    function testSetPriceRevertsOnNegativePrice() public {
        vm.prank(controller);
        vm.expectRevert(MSigOracleFeed.InvalidPrice.selector);
        feed.setPrice(-1000e8);
    }

    function testSetPriceIncrementsRoundId() public {
        vm.startPrank(controller);

        feed.setPrice(1050e8);
        (uint80 roundId1,,,, ) = feed.latestRoundData();
        assertEq(roundId1, 2);

        feed.setPrice(1040e8);
        (uint80 roundId2,,,, ) = feed.latestRoundData();
        assertEq(roundId2, 3);

        vm.stopPrank();
    }

    function testSetPriceUpdatesTimestamp() public {
        uint256 timestamp1 = block.timestamp;

        vm.warp(timestamp1 + 100);

        vm.prank(controller);
        feed.setPrice(1050e8);

        (,, uint256 startedAt, uint256 updatedAt,) = feed.latestRoundData();
        assertEq(updatedAt, timestamp1 + 100);
        assertEq(startedAt, updatedAt);
    }

    // setPriceForce Tests
    function testSetPriceForceWithLargeDeviation() public {
        int256 newPrice = 2000e8; // 100% increase (far beyond 10% limit)

        vm.prank(controller);
        vm.expectEmit(true, true, false, true);
        emit PriceForceUpdated(2, newPrice, controller);
        feed.setPriceForce(newPrice);

        (, int256 answer,,,) = feed.latestRoundData();
        assertEq(answer, newPrice);
    }

    function testSetPriceForceWithDecrease() public {
        int256 newPrice = 100e8; // 90% decrease

        vm.prank(controller);
        feed.setPriceForce(newPrice);

        (, int256 answer,,,) = feed.latestRoundData();
        assertEq(answer, newPrice);
    }

    function testSetPriceForceRevertsOnUnauthorized() public {
        int256 newPrice = 2000e8;

        vm.prank(unauthorized);
        vm.expectRevert(MSigOracleFeed.Unauthorized.selector);
        feed.setPriceForce(newPrice);
    }

    function testSetPriceForceRevertsOnZeroPrice() public {
        vm.prank(controller);
        vm.expectRevert(MSigOracleFeed.InvalidPrice.selector);
        feed.setPriceForce(0);
    }

    function testSetPriceForceRevertsOnNegativePrice() public {
        vm.prank(controller);
        vm.expectRevert(MSigOracleFeed.InvalidPrice.selector);
        feed.setPriceForce(-1000e8);
    }

    // Multiple Updates Test
    function testMultipleUpdatesSequence() public {
        vm.startPrank(controller);

        // Update 1: +5%
        feed.setPrice(1050e8);
        (, int256 answer1,,,) = feed.latestRoundData();
        assertEq(answer1, 1050e8);

        // Update 2: +5% from new price
        feed.setPrice(1102e8); // 1050 * 1.05 = 1102.5
        (, int256 answer2,,,) = feed.latestRoundData();
        assertEq(answer2, 1102e8);

        // Update 3: Force large change
        feed.setPriceForce(500e8);
        (, int256 answer3,,,) = feed.latestRoundData();
        assertEq(answer3, 500e8);

        // Update 4: Normal update from new baseline
        feed.setPrice(550e8); // 10% increase from 500
        (, int256 answer4,,,) = feed.latestRoundData();
        assertEq(answer4, 550e8);

        vm.stopPrank();
    }

    // Fuzz Tests
    function testFuzzSetPriceWithinDeviation(int256 priceAdjustment) public {
        // Bound adjustment to be within -10% to +10%
        priceAdjustment = bound(priceAdjustment, -100e8, 100e8); // -10% to +10% of 1000
        int256 newPrice = INITIAL_PRICE + priceAdjustment;

        // Ensure price is positive
        vm.assume(newPrice > 0);

        // Calculate actual deviation
        uint256 deviation;
        if (newPrice > INITIAL_PRICE) {
            deviation = (uint256(newPrice - INITIAL_PRICE) * 1e18) / uint256(INITIAL_PRICE);
        } else {
            deviation = (uint256(INITIAL_PRICE - newPrice) * 1e18) / uint256(INITIAL_PRICE);
        }

        vm.prank(controller);
        if (deviation <= MAX_DEVIATION) {
            feed.setPrice(newPrice);
            (, int256 answer,,,) = feed.latestRoundData();
            assertEq(answer, newPrice);
        } else {
            vm.expectRevert();
            feed.setPrice(newPrice);
        }
    }

    function testFuzzSetPriceForce(int256 newPrice) public {
        // Only test positive prices
        newPrice = bound(newPrice, 1, type(int256).max);

        vm.prank(controller);
        feed.setPriceForce(newPrice);

        (, int256 answer,,,) = feed.latestRoundData();
        assertEq(answer, newPrice);
    }

    // Factory Tests
    function testFactoryDeployment() public {
        MSigOracleFeed newFeed = factory.deployMSigOracleFeed(
            controller,
            INITIAL_PRICE,
            MAX_DEVIATION,
            DECIMALS,
            DESCRIPTION
        );

        assertEq(address(newFeed.controller()), controller);
        assertEq(newFeed.decimals(), DECIMALS);
        assertEq(newFeed.maxSafeDeviation(), MAX_DEVIATION);
    }

    function testFactoryEmitsEvent() public {
        // Predict the deployed address using foundry's computeCreateAddress
        address expectedAddress = vm.computeCreateAddress(address(factory), 1);

        vm.expectEmit(true, true, false, true);
        emit MSigOracleFeedFactory.MSigOracleFeedDeployed(
            expectedAddress,
            controller,
            INITIAL_PRICE,
            MAX_DEVIATION,
            DECIMALS,
            DESCRIPTION
        );

        MSigOracleFeed newFeed = factory.deployMSigOracleFeed(
            controller,
            INITIAL_PRICE,
            MAX_DEVIATION,
            DECIMALS,
            DESCRIPTION
        );

        assertEq(address(newFeed), expectedAddress);
    }

    function testFactoryDeploysMultipleFeeds() public {
        MSigOracleFeed feed1 = factory.deployMSigOracleFeed(
            controller,
            INITIAL_PRICE,
            MAX_DEVIATION,
            DECIMALS,
            "Feed 1"
        );

        MSigOracleFeed feed2 = factory.deployMSigOracleFeed(
            controller,
            INITIAL_PRICE * 2,
            MAX_DEVIATION,
            DECIMALS,
            "Feed 2"
        );

        assertTrue(address(feed1) != address(feed2));
        assertEq(feed1.description(), "Feed 1");
        assertEq(feed2.description(), "Feed 2");
    }

    // Edge Cases
    function testZeroDeviationWhenPricesEqual() public {
        vm.prank(controller);
        feed.setPrice(INITIAL_PRICE); // Same price

        (, int256 answer,,,) = feed.latestRoundData();
        assertEq(answer, INITIAL_PRICE);
    }

    function testVerySmallDeviation() public {
        int256 newPrice = INITIAL_PRICE + 1; // Tiny increase

        vm.prank(controller);
        feed.setPrice(newPrice);

        (, int256 answer,,,) = feed.latestRoundData();
        assertEq(answer, newPrice);
    }

    function testMaxSafeDeviationZeroBlocksNormalUpdates() public {
        MSigOracleFeed strictFeed = new MSigOracleFeed(
            controller,
            INITIAL_PRICE,
            0, // 0% deviation allowed
            DECIMALS,
            "Strict Feed"
        );

        // Can only set the exact same price
        vm.startPrank(controller);
        strictFeed.setPrice(INITIAL_PRICE);

        // Any change should revert
        vm.expectRevert();
        strictFeed.setPrice(INITIAL_PRICE + 1);

        // But force should still work
        strictFeed.setPriceForce(INITIAL_PRICE + 1000e8);
        vm.stopPrank();
    }

    function testLargeMaxSafeDeviation() public {
        MSigOracleFeed permissiveFeed = new MSigOracleFeed(
            controller,
            INITIAL_PRICE,
            1e18, // 100% deviation allowed
            DECIMALS,
            "Permissive Feed"
        );

        vm.prank(controller);
        permissiveFeed.setPrice(INITIAL_PRICE * 2); // 100% increase - should work

        (, int256 answer,,,) = permissiveFeed.latestRoundData();
        assertEq(answer, INITIAL_PRICE * 2);
    }
}
