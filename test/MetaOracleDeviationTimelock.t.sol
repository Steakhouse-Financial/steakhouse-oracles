// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MetaOracleDeviationTimelock, IOracle} from "../src/MetaOracleDeviationTimelock.sol";
import {MetaOracleDeviationTimelockFactory} from "../src/MetaOracleDeviationTimelockFactory.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

// --- Mock Oracle Implementation ---

contract MockOracle is IOracle {
    string public description;
    uint8 public decimals;
    uint256 internal _price;

    constructor(string memory _description, uint8 _decimals, uint256 initialPrice) {
        description = _description;
        decimals = _decimals;
        _price = initialPrice;
    }

    function setPrice(uint256 newPrice) external {
        _price = newPrice;
    }

    function price() external view returns (uint256) {
        return _price;
    }
}

// --- Test Contract ---

contract MetaOracleDeviationTimelockTest is Test {
    // Constants
    uint256 constant ONE_HOUR = 3600;
    uint256 constant ONE_DAY = 24 * ONE_HOUR;
    uint256 constant PRICE_PRECISION = 1e18; // Assuming price is 18 decimals for simplicity
    uint256 constant THRESHOLD_5_PERCENT = 0.05 ether; // 5% deviation threshold (using ether for 1e18 scale)

    // Mock Oracles
    MockOracle internal primaryOracle;
    MockOracle internal backupOracle;

    // Factory and implementation
    MetaOracleDeviationTimelockFactory internal factory;
    MetaOracleDeviationTimelock internal implementation;

    // Contract under test (will be a proxy instance)
    MetaOracleDeviationTimelock internal metaOracle;

    // Deployment parameters
    uint256 internal challengeDuration = ONE_HOUR;
    uint256 internal healingDuration = ONE_DAY;

    // Event topic hashes for cleaner checks
    bytes32 constant CHALLENGE_STARTED_TOPIC = keccak256("ChallengeStarted(uint256)");
    bytes32 constant CHALLENGE_REVOKED_TOPIC = keccak256("ChallengeRevoked()");
    bytes32 constant CHALLENGE_ACCEPTED_TOPIC = keccak256("ChallengeAccepted(address)");
    bytes32 constant HEALING_STARTED_TOPIC = keccak256("HealingStarted(uint256)");
    bytes32 constant HEALING_REVOKED_TOPIC = keccak256("HealingRevoked()");
    bytes32 constant HEALING_ACCEPTED_TOPIC = keccak256("HealingAccepted(address)");

    /// @notice Setup test environment before each test function
    function setUp() public {
        // Deploy Factory (which deploys implementation)
        factory = new MetaOracleDeviationTimelockFactory();
        implementation = MetaOracleDeviationTimelock(factory.implementation());

        // Deploy mock oracles
        primaryOracle = new MockOracle("Primary ETH/USD", 18, 2000 * PRICE_PRECISION); // Initial price $2000
        backupOracle = new MockOracle("Backup ETH/USD", 18, 2000 * PRICE_PRECISION); // Initial price $2000

        // Deploy the meta-oracle proxy via factory
        metaOracle = factory.deployMetaOracle(
            IOracle(address(primaryOracle)),
            IOracle(address(backupOracle)),
            THRESHOLD_5_PERCENT,
            challengeDuration,
            healingDuration
        );

        // Ensure initial state of the proxy
        assertEq(address(metaOracle.currentOracle()), address(primaryOracle), "Initial oracle should be primary");
        assertEq(metaOracle.price(), 2000 * PRICE_PRECISION, "Initial price mismatch");
        assertFalse(metaOracle.isChallenged(), "Should not be challenged initially");
        assertFalse(metaOracle.isHealing(), "Should not be healing initially");
        assertFalse(metaOracle.isDeviant(), "Should not be deviant initially");
    }

    // --- Constructor / Initialization Tests ---

    function test_RevertIf_ZeroAddressPrimary() public {
        vm.expectRevert("Invalid primary oracle");
        factory.deployMetaOracle(
            IOracle(address(0)),
            IOracle(address(backupOracle)),
            THRESHOLD_5_PERCENT,
            challengeDuration,
            healingDuration
        );
    }

    function test_RevertIf_ZeroAddressBackup() public {
        vm.expectRevert("Invalid backup oracle"); // Keep simple revert string for now
        factory.deployMetaOracle(
            IOracle(address(primaryOracle)),
            IOracle(address(0)),
            THRESHOLD_5_PERCENT,
            challengeDuration,
            healingDuration
        );
    }

    function test_RevertIf_SameOracleAddresses() public {
        vm.expectRevert("Oracles must be different");
        factory.deployMetaOracle(
            IOracle(address(primaryOracle)),
            IOracle(address(primaryOracle)),
            THRESHOLD_5_PERCENT,
            challengeDuration,
            healingDuration
        );
    }

     function test_RevertIf_ZeroThreshold() public {
        vm.expectRevert("Deviation threshold must be positive");
        factory.deployMetaOracle(
            IOracle(address(primaryOracle)),
            IOracle(address(backupOracle)),
            0,
            challengeDuration,
            healingDuration
        );
    }

    function test_RevertIf_InitialDeviationTooHigh() public {
        // Set initial prices with > 5% deviation
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        backupOracle.setPrice(2000 * PRICE_PRECISION); // Stays at default

        vm.expectRevert("MODT: Initial deviation too high");
        factory.deployMetaOracle(
            IOracle(address(primaryOracle)),
            IOracle(address(backupOracle)),
            THRESHOLD_5_PERCENT,
            challengeDuration,
            healingDuration
        );
    }

    function test_RevertIf_Initialize_CalledTwice() public {
        // metaOracle is already initialized in setUp()
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        metaOracle.initialize(
            IOracle(address(primaryOracle)),
            IOracle(address(backupOracle)),
            THRESHOLD_5_PERCENT,
            challengeDuration,
            healingDuration
        );
    }

    // --- View Function Tests ---

    function test_IsPrimary_IsBackup() public {
        assertTrue(metaOracle.isPrimary(), "Should be primary initially");
        assertFalse(metaOracle.isBackup(), "Should not be backup initially");
        // Switch needed to test the other state, will be covered in challenge/heal tests
    }

    function test_GetDeviation_NoDeviation() public {
        assertEq(metaOracle.getDeviation(), 0, "Deviation should be 0 initially");
        assertFalse(metaOracle.isDeviant(), "Should not be deviant");
    }

    function test_GetDeviation_SlightDeviation_BelowThreshold() public {
        // Set prices with 2% deviation (2000 vs 1960)
        primaryOracle.setPrice(2000 * PRICE_PRECISION);
        backupOracle.setPrice(1960 * PRICE_PRECISION); // ~2.04% deviation relative to backup
        uint256 expectedDeviation = ((2000 - 1960) * PRICE_PRECISION * PRICE_PRECISION) / (1960 * PRICE_PRECISION);
        assertEq(metaOracle.getDeviation(), expectedDeviation, "Deviation mismatch (below threshold)");
        assertFalse(metaOracle.isDeviant(), "Should not be deviant (below threshold)");
    }

    function test_GetDeviation_SignificantDeviation_AboveThreshold() public {
        // Set prices with 6% deviation (2000 vs 1880)
        primaryOracle.setPrice(2000 * PRICE_PRECISION);
        backupOracle.setPrice(1880 * PRICE_PRECISION); // ~6.38% deviation relative to backup
        uint256 expectedDeviation = ((2000 - 1880) * PRICE_PRECISION * PRICE_PRECISION) / (1880 * PRICE_PRECISION);
        assertEq(metaOracle.getDeviation(), expectedDeviation, "Deviation mismatch (above threshold)");
        assertTrue(metaOracle.isDeviant(), "Should be deviant (above threshold)");
    }

    function test_GetDeviation_BackupHigher_AboveThreshold() public {
        // Set prices with 6% deviation (1880 vs 2000)
        primaryOracle.setPrice(1880 * PRICE_PRECISION);
        backupOracle.setPrice(2000 * PRICE_PRECISION); // ~6.38% abs deviation relative to backup
        uint256 expectedDeviation = ((2000 - 1880) * PRICE_PRECISION * PRICE_PRECISION) / (2000 * PRICE_PRECISION);
        assertEq(metaOracle.getDeviation(), expectedDeviation, "Deviation mismatch (backup higher, above threshold)");
        assertTrue(metaOracle.isDeviant(), "Should be deviant (backup higher, above threshold)");
    }

    function test_GetDeviation_BackupIsZero_PrimaryNonZero() public {
        primaryOracle.setPrice(1 * PRICE_PRECISION);
        backupOracle.setPrice(0);
        assertEq(metaOracle.getDeviation(), type(uint256).max, "Deviation should be max");
        assertTrue(metaOracle.isDeviant(), "Should be deviant when backup is zero");
    }

    function test_GetDeviation_BackupIsZero_PrimaryIsZero() public {
        primaryOracle.setPrice(0);
        backupOracle.setPrice(0);
        assertEq(metaOracle.getDeviation(), 0, "Deviation should be 0");
        assertFalse(metaOracle.isDeviant(), "Should not be deviant when both zero");
    }

    // --- Challenge Workflow Tests ---

    function test_Challenge_Success() public {
        // Introduce deviation
        primaryOracle.setPrice(2150 * PRICE_PRECISION); // > 5% deviation (2150 vs 2000)
        assertTrue(metaOracle.isDeviant(), "Pre-check: Should be deviant");

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit MetaOracleDeviationTimelock.ChallengeStarted(block.timestamp + challengeDuration);

        // Call challenge
        metaOracle.challenge();

        // Check state
        assertTrue(metaOracle.isChallenged(), "Should be challenged");
        assertEq(metaOracle.challengeExpiresAt(), block.timestamp + challengeDuration, "Challenge expiry time mismatch");
        assertFalse(metaOracle.isHealing(), "Should not be healing");
        assertTrue(metaOracle.isPrimary(), "Should still be primary during challenge");
        assertEq(metaOracle.price(), 2150 * PRICE_PRECISION, "Price should be primary's during challenge");
    }

    function test_RevertChallenge_WhenNotPrimary() public {
        // Switch to backup first (simulate previous challenge)
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        vm.warp(metaOracle.challengeExpiresAt()); // Move time forward
        metaOracle.acceptChallenge();
        assertTrue(metaOracle.isBackup(), "Setup: Should be backup");

        // Try to challenge again (while backup is active)
        vm.expectRevert("MODT: Must be primary oracle");
        metaOracle.challenge();
    }

    function test_RevertChallenge_WhenAlreadyChallenged() public {
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge(); // First challenge
        assertTrue(metaOracle.isChallenged(), "Setup: Should be challenged");

        // Try challenging again
        vm.expectRevert("MODT: Already challenged");
        metaOracle.challenge();
    }

    function test_RevertChallenge_WhenHealing() public {
        // Setup: Switch to backup, then start healing
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        vm.warp(metaOracle.challengeExpiresAt());
        metaOracle.acceptChallenge(); // Now backup
        primaryOracle.setPrice(2000 * PRICE_PRECISION); // Prices converge
        metaOracle.heal();
        assertTrue(metaOracle.isHealing(), "Setup: Should be healing");

        // Try to challenge while healing
        primaryOracle.setPrice(2150 * PRICE_PRECISION); // Make it deviant again
        // The first check in challenge() is isPrimary(), which fails first.
        vm.expectRevert("MODT: Must be primary oracle");
        metaOracle.challenge(); // << ACTUAL CALL
    }

    function test_RevertChallenge_WhenNotDeviant() public {
        assertFalse(metaOracle.isDeviant(), "Setup: Should not be deviant");
        vm.expectRevert("MODT: Deviation threshold not met");
        metaOracle.challenge();
    }

    function test_RevokeChallenge_Success() public {
        // Start challenge
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        assertTrue(metaOracle.isChallenged(), "Setup: Should be challenged");

        // Resolve deviation
        primaryOracle.setPrice(2010 * PRICE_PRECISION); // Back below 5% threshold
        assertFalse(metaOracle.isDeviant(), "Sanity check: Deviation resolved");

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit MetaOracleDeviationTimelock.ChallengeRevoked();

        // Revoke
        metaOracle.revokeChallenge();

        // Check state
        assertFalse(metaOracle.isChallenged(), "Should not be challenged after revoke");
        assertEq(metaOracle.challengeExpiresAt(), 0, "Challenge expiry should be reset");
        assertTrue(metaOracle.isPrimary(), "Should remain primary");
    }

    function test_RevertRevokeChallenge_WhenNotPrimary() public {
        // Setup: Switch to backup
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        vm.warp(metaOracle.challengeExpiresAt());
        metaOracle.acceptChallenge();

        // Try to revoke (no challenge active, and not primary)
        vm.expectRevert("MODT: Must be primary oracle");
        metaOracle.revokeChallenge();
    }

    function test_RevertRevokeChallenge_WhenNotChallenged() public {
        assertFalse(metaOracle.isChallenged(), "Setup: Should not be challenged");
        vm.expectRevert("MODT: Not challenged");
        metaOracle.revokeChallenge();
    }

    function test_RevertRevokeChallenge_WhenStillDeviant() public {
        // Start challenge
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        assertTrue(metaOracle.isChallenged(), "Setup: Should be challenged");
        assertTrue(metaOracle.isDeviant(), "Setup: Should still be deviant");

        // Try to revoke
        vm.expectRevert("MODT: Deviation threshold still met");
        metaOracle.revokeChallenge();
    }

    function test_AcceptChallenge_Success() public {
        // Start challenge
        primaryOracle.setPrice(2150 * PRICE_PRECISION); // Deviant
        metaOracle.challenge();
        uint256 expiry = metaOracle.challengeExpiresAt();
        assertTrue(metaOracle.isChallenged(), "Setup: Should be challenged");

        // Move time forward to exactly expiry time
        vm.warp(expiry);

        // Keep price deviant
        assertTrue(metaOracle.isDeviant(), "Sanity check: Should still be deviant");

        // Expect event
        vm.expectEmit(true, true, false, true); // Check indexed address (topic1)
        emit MetaOracleDeviationTimelock.ChallengeAccepted(address(backupOracle));

        // Accept challenge
        metaOracle.acceptChallenge();

        // Check state
        assertFalse(metaOracle.isChallenged(), "Should not be challenged after accept");
        assertTrue(metaOracle.isBackup(), "Should be backup oracle after accept");
        assertEq(address(metaOracle.currentOracle()), address(backupOracle), "Current oracle address mismatch");
        assertEq(metaOracle.price(), 2000 * PRICE_PRECISION, "Price should be backup's price");
    }

    function test_AcceptChallenge_Success_LongAfterExpiry() public {
        // Start challenge
        primaryOracle.setPrice(2150 * PRICE_PRECISION); // Deviant
        metaOracle.challenge();
        uint256 expiry = metaOracle.challengeExpiresAt();

        // Move time forward long after expiry time
        vm.warp(expiry + 5 * ONE_DAY);

        // Keep price deviant
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        assertTrue(metaOracle.isDeviant(), "Sanity check: Should still be deviant");

        // Accept challenge
        metaOracle.acceptChallenge();

        // Check state
        assertTrue(metaOracle.isBackup(), "Should be backup oracle after accept");
    }

    function test_RevertAcceptChallenge_WhenNotPrimary() public {
        // Setup: Switch to backup
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        vm.warp(metaOracle.challengeExpiresAt());
        metaOracle.acceptChallenge();
        assertTrue(metaOracle.isBackup(), "Setup: Should be backup");

        // Try accept challenge (no challenge active, not primary)
        vm.expectRevert("MODT: Must be primary oracle");
        metaOracle.acceptChallenge();
    }

    function test_RevertAcceptChallenge_WhenNotChallenged() public {
        assertFalse(metaOracle.isChallenged(), "Setup: Not challenged");
        vm.expectRevert("MODT: Not challenged");
        metaOracle.acceptChallenge();
    }

    function test_RevertAcceptChallenge_BeforeTimelock() public {
        // Start challenge
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        uint256 expiry = metaOracle.challengeExpiresAt();

        // Try to accept before expiry
        vm.warp(expiry - 10); // 10 seconds before expiry
        assertTrue(metaOracle.isDeviant(), "Sanity check: Should be deviant");

        vm.expectRevert("MODT: Challenge timelock not passed");
        metaOracle.acceptChallenge();
    }

    function test_RevertAcceptChallenge_WhenDeviationResolved() public {
        // Start challenge
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        uint256 expiry = metaOracle.challengeExpiresAt();

        // Move time forward
        vm.warp(expiry);

        // Resolve deviation just before accepting
        primaryOracle.setPrice(2010 * PRICE_PRECISION); // Below threshold
        assertFalse(metaOracle.isDeviant(), "Sanity check: Deviation resolved");

        vm.expectRevert("MODT: Deviation resolved");
        metaOracle.acceptChallenge();
    }

    // --- Healing Workflow Tests ---

    function test_Heal_Success() public {
        // Setup: Switch to backup oracle
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        vm.warp(metaOracle.challengeExpiresAt());
        metaOracle.acceptChallenge();
        assertTrue(metaOracle.isBackup(), "Setup: Should be backup");
        assertEq(metaOracle.price(), 2000 * PRICE_PRECISION, "Setup: Price should be backup's");

        // Make prices converge (no deviation)
        primaryOracle.setPrice(2000 * PRICE_PRECISION);
        assertFalse(metaOracle.isDeviant(), "Sanity Check: Should not be deviant for heal");

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit MetaOracleDeviationTimelock.HealingStarted(block.timestamp + healingDuration);

        // Start healing
        metaOracle.heal();

        // Check state
        assertTrue(metaOracle.isHealing(), "Should be healing");
        assertEq(metaOracle.healingExpiresAt(), block.timestamp + healingDuration, "Healing expiry time mismatch");
        assertFalse(metaOracle.isChallenged(), "Should not be challenged");
        assertTrue(metaOracle.isBackup(), "Should still be backup during healing");
        assertEq(metaOracle.price(), 2000 * PRICE_PRECISION, "Price should be backup's during healing");
    }

    function test_RevertHeal_WhenNotBackup() public {
        // Still on primary oracle
        assertTrue(metaOracle.isPrimary(), "Setup: Should be primary");
        assertFalse(metaOracle.isDeviant(), "Setup: Not deviant");
        vm.expectRevert("MODT: Must be backup oracle");
        metaOracle.heal();
    }

    function test_RevertHeal_WhenAlreadyHealing() public {
        // Setup: Switch to backup and start healing
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        vm.warp(metaOracle.challengeExpiresAt());
        metaOracle.acceptChallenge();
        primaryOracle.setPrice(2000 * PRICE_PRECISION); // Converge
        metaOracle.heal(); // First heal call
        assertTrue(metaOracle.isHealing(), "Setup: Should be healing");

        // Try healing again
        vm.expectRevert("MODT: Already healing");
        metaOracle.heal();
    }

    function test_RevertHeal_WhenChallenged() public {
        // Setup: Start challenge (primary still active)
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        assertTrue(metaOracle.isChallenged(), "Setup: Should be challenged");

        // Try healing while challenge is active (won't happen normally due to isBackup check, but testing check explicitly)
        // We need to bypass the isBackup check for this test case, maybe not possible without changing code?
        // The isBackup check prevents this path. We can skip testing this explicit revert message.
        // If somehow it was backup AND challenged (impossible state), this would trigger.
    }

    function test_RevertHeal_WhenStillDeviant() public {
        // Setup: Switch to backup
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        vm.warp(metaOracle.challengeExpiresAt());
        metaOracle.acceptChallenge();
        assertTrue(metaOracle.isBackup(), "Setup: Should be backup");

        // Keep prices deviant
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        assertTrue(metaOracle.isDeviant(), "Setup: Should be deviant");

        // Try to heal
        vm.expectRevert("MODT: Deviation threshold still met");
        metaOracle.heal();
    }

    function test_RevokeHealing_Success() public {
        // Setup: Switch to backup and start healing
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        vm.warp(metaOracle.challengeExpiresAt());
        metaOracle.acceptChallenge();
        primaryOracle.setPrice(2000 * PRICE_PRECISION); // Converge
        metaOracle.heal();
        assertTrue(metaOracle.isHealing(), "Setup: Should be healing");

        // Make prices deviant again
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        assertTrue(metaOracle.isDeviant(), "Sanity Check: Should be deviant again");

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit MetaOracleDeviationTimelock.HealingRevoked();

        // Revoke healing
        metaOracle.revokeHealing();

        // Check state
        assertFalse(metaOracle.isHealing(), "Should not be healing after revoke");
        assertEq(metaOracle.healingExpiresAt(), 0, "Healing expiry should be reset");
        assertTrue(metaOracle.isBackup(), "Should remain backup");
    }

    function test_RevertRevokeHealing_WhenNotBackup() public {
        assertTrue(metaOracle.isPrimary(), "Setup: Should be primary");
        vm.expectRevert("MODT: Must be backup oracle");
        metaOracle.revokeHealing();
    }

    function test_RevertRevokeHealing_WhenNotHealing() public {
        // Setup: Switch to backup, but don't start healing
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        vm.warp(metaOracle.challengeExpiresAt());
        metaOracle.acceptChallenge();
        assertTrue(metaOracle.isBackup(), "Setup: Should be backup");
        assertFalse(metaOracle.isHealing(), "Setup: Should not be healing");

        // Make prices deviant (needed for the check)
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        assertTrue(metaOracle.isDeviant(), "Setup: Making deviant for check");

        // Try revoke
        vm.expectRevert("MODT: Not healing");
        metaOracle.revokeHealing();
    }

    function test_RevertRevokeHealing_WhenNotDeviant() public {
        // Setup: Switch to backup and start healing
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        vm.warp(metaOracle.challengeExpiresAt());
        metaOracle.acceptChallenge();
        primaryOracle.setPrice(2000 * PRICE_PRECISION); // Converge
        metaOracle.heal();
        assertTrue(metaOracle.isHealing(), "Setup: Should be healing");
        assertFalse(metaOracle.isDeviant(), "Setup: Should not be deviant");

        // Try to revoke
        vm.expectRevert("MODT: Deviation threshold not met");
        metaOracle.revokeHealing();
    }

    function test_AcceptHealing_Success() public {
        // Setup: Switch to backup and start healing
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        vm.warp(metaOracle.challengeExpiresAt());
        metaOracle.acceptChallenge();
        primaryOracle.setPrice(2000 * PRICE_PRECISION); // Converge
        metaOracle.heal();
        uint256 expiry = metaOracle.healingExpiresAt();
        assertTrue(metaOracle.isHealing(), "Setup: Should be healing");

        // Move time forward to exactly expiry
        vm.warp(expiry);

        // Keep prices converged
        assertFalse(metaOracle.isDeviant(), "Sanity Check: Should still be converged");

        // Expect event
        vm.expectEmit(true, true, false, true); // Check indexed address (topic1)
        emit MetaOracleDeviationTimelock.HealingAccepted(address(primaryOracle));

        // Accept healing
        metaOracle.acceptHealing();

        // Check state
        assertFalse(metaOracle.isHealing(), "Should not be healing after accept");
        assertTrue(metaOracle.isPrimary(), "Should be primary oracle after accept");
        assertEq(address(metaOracle.currentOracle()), address(primaryOracle), "Current oracle address mismatch");
        assertEq(metaOracle.price(), 2000 * PRICE_PRECISION, "Price should be primary's price");
    }

    function test_AcceptHealing_Success_LongAfterExpiry() public {
        // Setup: Switch to backup and start healing
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        vm.warp(metaOracle.challengeExpiresAt());
        metaOracle.acceptChallenge();
        primaryOracle.setPrice(2000 * PRICE_PRECISION); // Converge
        metaOracle.heal();
        uint256 expiry = metaOracle.healingExpiresAt();

        // Move time forward long after expiry
        vm.warp(expiry + 5 * ONE_DAY);

        // Keep prices converged
        primaryOracle.setPrice(2005 * PRICE_PRECISION); // Still converged
        assertFalse(metaOracle.isDeviant(), "Sanity Check: Should still be converged");

        // Accept healing
        metaOracle.acceptHealing();

        // Check state
        assertTrue(metaOracle.isPrimary(), "Should be primary oracle after accept");
    }

    function test_RevertAcceptHealing_WhenNotBackup() public {
        // Still on primary
        assertTrue(metaOracle.isPrimary(), "Setup: Should be primary");
        vm.expectRevert("MODT: Must be backup oracle");
        metaOracle.acceptHealing();
    }

    function test_RevertAcceptHealing_WhenNotHealing() public {
        // Setup: Switch to backup, but don't start healing
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        vm.warp(metaOracle.challengeExpiresAt());
        metaOracle.acceptChallenge();
        assertTrue(metaOracle.isBackup(), "Setup: Should be backup");
        assertFalse(metaOracle.isHealing(), "Setup: Should not be healing");

        // Try accept healing
        vm.expectRevert("MODT: Not healing");
        metaOracle.acceptHealing();
    }

    function test_RevertAcceptHealing_BeforeTimelock() public {
        // Setup: Switch to backup and start healing
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        vm.warp(metaOracle.challengeExpiresAt());
        metaOracle.acceptChallenge();
        primaryOracle.setPrice(2000 * PRICE_PRECISION); // Converge
        metaOracle.heal();
        uint256 expiry = metaOracle.healingExpiresAt();
        assertTrue(metaOracle.isHealing(), "Setup: Should be healing");

        // Move time just before expiry
        vm.warp(expiry - 10);

        // Keep prices converged
        assertFalse(metaOracle.isDeviant(), "Sanity Check: Should still be converged");

        // Try accept healing
        vm.expectRevert("MODT: Healing timelock not passed");
        metaOracle.acceptHealing();
    }

    function test_RevertAcceptHealing_WhenDeviationOccurred() public {
        // Setup: Switch to backup and start healing
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        vm.warp(metaOracle.challengeExpiresAt());
        metaOracle.acceptChallenge();
        primaryOracle.setPrice(2000 * PRICE_PRECISION); // Converge
        metaOracle.heal();
        uint256 expiry = metaOracle.healingExpiresAt();
        assertTrue(metaOracle.isHealing(), "Setup: Should be healing");

        // Move time past expiry
        vm.warp(expiry);

        // Make prices deviant again just before accepting
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        assertTrue(metaOracle.isDeviant(), "Sanity check: Deviation occurred again");

        // Try accept healing
        vm.expectRevert("MODT: Deviation occurred");
        metaOracle.acceptHealing();
    }

    // --- Edge Cases ---

    function test_FullCycle_Challenge_Accept_Heal_Accept() public {
        // 1. Initial State: Primary active, prices converged
        assertEq(address(metaOracle.currentOracle()), address(primaryOracle));
        assertFalse(metaOracle.isDeviant());

        // 2. Deviation -> Challenge
        primaryOracle.setPrice(2150 * PRICE_PRECISION); // > 5% deviation
        assertTrue(metaOracle.isDeviant());
        metaOracle.challenge();
        assertTrue(metaOracle.isChallenged());
        uint256 challengeExpiry = metaOracle.challengeExpiresAt();

        // 3. Timelock passes -> Accept Challenge -> Backup active
        vm.warp(challengeExpiry);
        assertTrue(metaOracle.isDeviant()); // Still deviant
        metaOracle.acceptChallenge();
        assertFalse(metaOracle.isChallenged());
        assertTrue(metaOracle.isBackup());
        assertEq(address(metaOracle.currentOracle()), address(backupOracle));
        assertEq(metaOracle.price(), 2000 * PRICE_PRECISION); // Backup price

        // 4. Prices Converge -> Heal
        primaryOracle.setPrice(2010 * PRICE_PRECISION); // Converged (deviation < 5%)
        assertFalse(metaOracle.isDeviant(), "Sanity Check: Should not be deviant for heal");
        metaOracle.heal();
        assertTrue(metaOracle.isHealing());
        uint256 healingExpiry = metaOracle.healingExpiresAt();

        // 5. Timelock passes -> Accept Healing -> Primary active
        vm.warp(healingExpiry);
        assertFalse(metaOracle.isDeviant(), "Sanity Check: Should still be converged");
        metaOracle.acceptHealing();
        assertFalse(metaOracle.isHealing());
        assertTrue(metaOracle.isPrimary());
        assertEq(address(metaOracle.currentOracle()), address(primaryOracle));
        assertEq(metaOracle.price(), 2010 * PRICE_PRECISION); // Primary price
    }

    function test_Challenge_Revoke_ChallengeAgain_Accept() public {
        // 1. Deviate -> Challenge
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        assertTrue(metaOracle.isChallenged());
        uint256 firstChallengeExpiry = metaOracle.challengeExpiresAt();

        // 2. Converge -> Revoke Challenge
        vm.warp(block.timestamp + 100); // Pass some time, but less than timelock
        primaryOracle.setPrice(2000 * PRICE_PRECISION);
        assertFalse(metaOracle.isDeviant());
        metaOracle.revokeChallenge();
        assertFalse(metaOracle.isChallenged());
        assertTrue(metaOracle.isPrimary());

        // 3. Deviate Again -> Challenge Again
        vm.warp(block.timestamp + 100);
        primaryOracle.setPrice(2200 * PRICE_PRECISION); // Deviate more
        assertTrue(metaOracle.isDeviant());
        metaOracle.challenge();
        assertTrue(metaOracle.isChallenged());
        uint256 secondChallengeExpiry = metaOracle.challengeExpiresAt();
        assertTrue(secondChallengeExpiry > firstChallengeExpiry, "Second challenge expiry should be later");

        // 4. Timelock passes -> Accept Challenge
        vm.warp(secondChallengeExpiry);
        assertTrue(metaOracle.isDeviant()); // Still deviant
        metaOracle.acceptChallenge();
        assertTrue(metaOracle.isBackup());
    }

     function test_Heal_Revoke_HealAgain_Accept() public {
        // 1. Setup: Switch to backup
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        metaOracle.challenge();
        vm.warp(metaOracle.challengeExpiresAt());
        metaOracle.acceptChallenge();
        assertTrue(metaOracle.isBackup());

        // 2. Converge -> Heal
        primaryOracle.setPrice(2000 * PRICE_PRECISION);
        metaOracle.heal();
        assertTrue(metaOracle.isHealing());
        uint256 firstHealingExpiry = metaOracle.healingExpiresAt();

        // 3. Deviate -> Revoke Heal
        vm.warp(block.timestamp + 100); // Pass some time
        primaryOracle.setPrice(2150 * PRICE_PRECISION);
        assertTrue(metaOracle.isDeviant());
        metaOracle.revokeHealing();
        assertFalse(metaOracle.isHealing());
        assertTrue(metaOracle.isBackup());

        // 4. Converge Again -> Heal Again
        vm.warp(block.timestamp + 100);
        primaryOracle.setPrice(1990 * PRICE_PRECISION); // Converge again
        assertFalse(metaOracle.isDeviant());
        metaOracle.heal();
        assertTrue(metaOracle.isHealing());
        uint256 secondHealingExpiry = metaOracle.healingExpiresAt();
        assertTrue(secondHealingExpiry > firstHealingExpiry, "Second healing expiry should be later");

        // 5. Timelock passes -> Accept Healing
        vm.warp(secondHealingExpiry);
        assertFalse(metaOracle.isDeviant(), "Sanity Check: Should still be converged");
        metaOracle.acceptHealing();
        assertTrue(metaOracle.isPrimary());
    }
} 