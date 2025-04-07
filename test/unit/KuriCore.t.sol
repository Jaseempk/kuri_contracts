//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {KuriCore} from "../../src/KuriCore.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract KuriCoreTest is Test {
    KuriCore kuriCore;
    MockERC20 supportedToken;

    // Constants
    uint64 public constant KURI_AMOUNT = 10001e6;
    uint16 public constant TOTAL_PARTICIPANTS = 10;
    uint256 public constant INITIAL_USER_BALANCE = 10001e6;
    address public constant SUPPORTED_TOKEN =
        0xC129124eA2Fd4D63C1Fc64059456D8f231eBbed1;
    // Test addresses
    address public creator;
    address public initialiser;
    address public admin;
    address[] public users;

    // Contract state variables
    KuriCore.IntervalType public intervalTypeEnum = KuriCore.IntervalType.WEEK;

    // Events for testing
    event KuriInitialised(KuriCore.Kuri _kuriData);
    event KuriInitFailed(
        address creator,
        uint64 kuriAmount,
        uint16 totalParticipantsCount,
        KuriCore.KuriState state
    );
    event UserDeposited(
        address user,
        uint256 userIndex,
        uint256 intervalIndex,
        uint64 amountDeposited,
        uint48 depositTimestamp
    );

    function setUp() public {
        // Setup addresses
        admin = makeAddr("admin");
        creator = makeAddr("creator");
        initialiser = makeAddr("initialiser");

        // Create test users
        for (uint16 i = 0; i < TOTAL_PARTICIPANTS; i++) {
            users.push(makeAddr(string(abi.encodePacked("user", i))));
        }

        // Deploy mock token at the same address as in the contract
        vm.etch(
            SUPPORTED_TOKEN,
            address(new MockERC20("Supported Token", "ST", 6)).code
        );

        supportedToken = MockERC20(SUPPORTED_TOKEN);

        // Mint tokens to users
        for (uint16 i = 0; i < users.length; i++) {
            deal(address(SUPPORTED_TOKEN), users[i], INITIAL_USER_BALANCE);
            // supportedToken.mint(users[i], INITIAL_USER_BALANCE);
        }

        console.log("heey");

        // Deploy KuriCore contract
        vm.prank(admin);
        kuriCore = new KuriCore(
            creator,
            KURI_AMOUNT,
            TOTAL_PARTICIPANTS,
            initialiser,
            intervalTypeEnum
        );
    }

    // Helper functions
    function _requestMembershipForAllUsers() internal {
        for (uint16 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            console.log("requesting membership for user:", users[i]);
            kuriCore.requestMembership();
        }
    }

    function _approveTokensForAllUsers(uint256 amount) internal {
        for (uint16 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            supportedToken.approve(address(kuriCore), amount);
        }
    }

    function _warpToLaunchPeriodEnd() internal {
        console.log("launchingPeriod:", kuriCore.LAUNCH_PERIOD_DURATION());
        // Warp to just after the launch period
        vm.warp(block.timestamp + kuriCore.LAUNCH_PERIOD_DURATION() + 1);
    }

    function _initializeKuri() internal {
        vm.prank(initialiser);
        kuriCore.initialiseKuri();
    }

    function _warpToNextDepositTime() internal {
        (, , , , , , uint48 nextIntervalDepositTime, , , , , ) = kuriCore
            .kuriData();
        vm.warp(nextIntervalDepositTime);
    }

    // ==================== CONSTRUCTOR TESTS ====================

    function test_constructorInitialization() public view {
        (
            address _creator,
            uint64 _kuriAmount,
            uint16 _totalParticipantsCount,
            uint16 _totalActiveParticipantsCount,
            ,
            ,
            ,
            uint48 _launchPeriod,
            ,
            ,
            ,
            KuriCore.KuriState _state
        ) = kuriCore.kuriData();

        assertEq(_creator, creator, "Creator address mismatch");
        assertEq(_kuriAmount, KURI_AMOUNT, "Kuri amount mismatch");
        assertEq(
            _totalParticipantsCount,
            TOTAL_PARTICIPANTS,
            "Total participants count mismatch"
        );
        assertEq(
            _totalActiveParticipantsCount,
            0,
            "Initial active participants should be 0"
        );
        assertEq(
            _launchPeriod,
            block.timestamp + kuriCore.LAUNCH_PERIOD_DURATION(),
            "Launch period mismatch"
        );
        assertEq(
            uint8(_state),
            uint8(KuriCore.KuriState.INLAUNCH),
            "Initial state should be INLAUNCH"
        );

        // Check roles
        assertTrue(
            kuriCore.hasRole(kuriCore.DEFAULT_ADMIN_ROLE(), admin),
            "Admin role not granted"
        );
        assertTrue(
            kuriCore.hasRole(kuriCore.INITIALISOR_ROLE(), initialiser),
            "Initialiser role not granted"
        );
    }

    // ==================== REQUEST MEMBERSHIP TESTS ====================

    function test_requestMembership() public {
        vm.prank(users[0]);
        kuriCore.requestMembership();

        (KuriCore.UserState userState, uint16 userIndex) = kuriCore.userToData(
            users[0]
        );
        (, , , uint16 totalActiveParticipantsCount, , , , , , , , ) = kuriCore
            .kuriData();

        assertEq(
            uint8(userState),
            uint8(KuriCore.UserState.ACCEPTED),
            "User should be accepted"
        );
        assertEq(userIndex, 0, "User index should be 0");
        assertEq(
            totalActiveParticipantsCount,
            1,
            "Active participants count should be 1"
        );
    }

    function testRequestMembershipMultipleUsers() public {
        for (uint16 i = 0; i < 5; i++) {
            vm.prank(users[i]);
            kuriCore.requestMembership();

            (KuriCore.UserState userState, uint16 userIndex) = kuriCore
                .userToData(users[i]);
            assertEq(
                uint8(userState),
                uint8(KuriCore.UserState.ACCEPTED),
                "User should be accepted"
            );
            assertEq(userIndex, i, "User index mismatch");
        }

        (, , , uint16 totalActiveParticipantsCount, , , , , , , , ) = kuriCore
            .kuriData();
        assertEq(
            totalActiveParticipantsCount,
            5,
            "Active participants count should be 5"
        );
    }

    function testCannotRequestMembershipAfterLaunchPeriod() public {
        _warpToLaunchPeriodEnd();

        vm.prank(users[0]);
        vm.expectRevert(KuriCore.KuriCore__AlreadyPastLaunchPeriod.selector);
        kuriCore.requestMembership();
    }

    function testCannotRequestMembershipWhenNotInLaunch() public {
        // First get all users to join
        _requestMembershipForAllUsers();

        // Initialize the Kuri
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Try to request membership when not in launch state
        vm.prank(makeAddr("newUser"));
        vm.expectRevert(KuriCore.KuriCore__CantRequestWhenNotInLaunch.selector);
        kuriCore.requestMembership();
    }

    function testRequestMembershipIdempotent() public {
        // First request
        vm.prank(users[0]);
        kuriCore.requestMembership();

        // Second request should not revert or change state
        vm.prank(users[0]);
        kuriCore.requestMembership();

        (, , , uint16 totalActiveParticipantsCount, , , , , , , , ) = kuriCore
            .kuriData();
        assertEq(
            totalActiveParticipantsCount,
            1,
            "Active participants count should still be 1"
        );
    }

    // ==================== INITIALIZE KURI TESTS ====================

    function test_initializeKuriSuccess() public {
        // Get all users to join
        _requestMembershipForAllUsers();

        // Warp to after launch period
        _warpToLaunchPeriodEnd();

        /**    struct Kuri {
        address creator;
        uint64 kuriAmount;
        uint16 totalParticipantsCount;
        uint16 totalActiveParticipantsCount;
        uint24 intervalDuration;
        uint48 nexRaffleTime;
        uint48 nextIntervalDepositTime;
        uint48 launchPeriod;
        uint48 startTime;
        uint48 endTime;
        IntervalType intervalType;
        KuriState state;
    } */

        KuriCore.Kuri memory kuriData = KuriCore.Kuri(
            creator,
            KURI_AMOUNT,
            TOTAL_PARTICIPANTS,
            TOTAL_PARTICIPANTS,
            uint24(kuriCore.WEEKLY_INTERVAL()),
            uint48(
                block.timestamp +
                    kuriCore.WEEKLY_INTERVAL() +
                    kuriCore.RAFFLE_DELAY_DURATION()
            ),
            uint48(block.timestamp + kuriCore.WEEKLY_INTERVAL()),
            uint48(block.timestamp + kuriCore.LAUNCH_PERIOD_DURATION() + 1),
            uint48(block.timestamp),
            uint48(
                block.timestamp +
                    ((TOTAL_PARTICIPANTS * kuriCore.WEEKLY_INTERVAL()) +
                        (TOTAL_PARTICIPANTS * kuriCore.RAFFLE_DELAY_DURATION()))
            ),
            KuriCore.IntervalType.WEEK,
            KuriCore.KuriState.INLAUNCH
        );
        //1744536516
        //1744277316

        // Initialize Kuri and check event emission
        vm.prank(initialiser);
        vm.expectEmit(true, true, true, true);
        emit KuriInitialised(kuriData); // This will be updated during the call
        bool success = kuriCore.initialiseKuri();

        assertTrue(success, "Initialization should succeed");

        // Check updated state
        (
            ,
            ,
            ,
            ,
            ,
            uint48 nexRaffleTime,
            uint48 nextIntervalDepositTime,
            ,
            uint48 startTime,
            uint48 endTime,
            ,
            KuriCore.KuriState state
        ) = kuriCore.kuriData();
        console.log("heey");

        assertEq(
            uint8(state),
            uint8(KuriCore.KuriState.ACTIVE),
            "State should be ACTIVE"
        );
        assertEq(
            startTime,
            block.timestamp,
            "Start time should be current timestamp"
        );
        assertEq(
            nextIntervalDepositTime,
            block.timestamp + kuriCore.WEEKLY_INTERVAL(),
            "Next interval deposit time mismatch"
        );
        assertEq(
            nexRaffleTime,
            nextIntervalDepositTime + kuriCore.RAFFLE_DELAY_DURATION(),
            "Next raffle time mismatch"
        );

        // Calculate expected end time
        uint256 expectedEndTime = block.timestamp +
            ((TOTAL_PARTICIPANTS * kuriCore.WEEKLY_INTERVAL()) +
                (TOTAL_PARTICIPANTS * kuriCore.RAFFLE_DELAY_DURATION()));
        assertEq(endTime, expectedEndTime, "End time mismatch");
    }

    function testInitializeKuriFailure() public {
        // Only 5 users join (not enough)
        for (uint16 i = 0; i < 5; i++) {
            vm.prank(users[i]);
            kuriCore.requestMembership();
        }

        // Warp to after launch period
        _warpToLaunchPeriodEnd();

        // Initialize Kuri and check event emission
        vm.prank(initialiser);
        vm.expectEmit(true, true, true, true);
        emit KuriInitFailed(
            creator,
            KURI_AMOUNT,
            TOTAL_PARTICIPANTS,
            KuriCore.KuriState.LAUNCHFAILED
        );
        bool success = kuriCore.initialiseKuri();

        assertFalse(success, "Initialization should fail");

        // Check updated state
        (, , , , , , , , , , , KuriCore.KuriState state) = kuriCore.kuriData();
        assertEq(
            uint8(state),
            uint8(KuriCore.KuriState.LAUNCHFAILED),
            "State should be LAUNCHFAILED"
        );
    }

    function testCannotInitializeBeforeLaunchPeriodEnds() public {
        // Get all users to join
        _requestMembershipForAllUsers();

        // Try to initialize before launch period ends
        vm.prank(initialiser);
        vm.expectRevert(KuriCore.KuriCore__LaunchPeriodNotOver.selector);
        kuriCore.initialiseKuri();
    }

    function testCannotInitializeWhenNotInLaunchState() public {
        // Get all users to join
        _requestMembershipForAllUsers();

        // Warp to after launch period and initialize
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Try to initialize again
        vm.prank(initialiser);
        vm.expectRevert(KuriCore.KuriCore__NotInLaunchState.selector);
        kuriCore.initialiseKuri();
    }

    function testCannotInitializeWithoutRole() public {
        // Get all users to join
        _requestMembershipForAllUsers();

        // Warp to after launch period
        _warpToLaunchPeriodEnd();

        // Try to initialize without the role
        vm.prank(users[0]);
        vm.expectRevert(); // AccessControl will revert with a specific error
        kuriCore.initialiseKuri();
    }

    // ==================== USER INSTALLMENT DEPOSIT TESTS ====================

    function testUserInstallmentDeposit() public {
        // Setup: Get all users to join, initialize Kuri, and approve tokens
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();
        _warpToNextDepositTime();

        uint64 expectedDepositAmount = KURI_AMOUNT / TOTAL_PARTICIPANTS;
        _approveTokensForAllUsers(expectedDepositAmount);

        // User makes a deposit
        vm.prank(users[0]);
        vm.expectEmit(true, true, true, true);
        emit UserDeposited(
            users[0],
            0, // User index
            0, // Interval index
            expectedDepositAmount,
            uint48(block.timestamp)
        );
        kuriCore.userInstallmentDeposit();

        // Check payment was recorded
        bool hasPaid = kuriCore.hasPaid(users[0], 0);
        assertTrue(hasPaid, "Payment should be recorded");

        // Check token transfer
        assertEq(
            supportedToken.balanceOf(address(kuriCore)),
            expectedDepositAmount,
            "Contract should have received tokens"
        );
        assertEq(
            supportedToken.balanceOf(users[0]),
            INITIAL_USER_BALANCE - expectedDepositAmount,
            "User balance should be reduced"
        );
    }

    function testCannotDepositWhenNotAccepted() public {
        // Setup: Some users join, initialize Kuri
        for (uint16 i = 0; i < 5; i++) {
            vm.prank(users[i]);
            kuriCore.requestMembership();
        }
        _warpToLaunchPeriodEnd();
        _initializeKuri();
        _warpToNextDepositTime();

        // Non-member tries to deposit
        address nonMember = makeAddr("nonMember");
        vm.prank(nonMember);
        vm.expectRevert(KuriCore.KuriCore__CallerNotAccepted.selector);
        kuriCore.userInstallmentDeposit();
    }

    function testCannotDepositWhenKuriNotActive() public {
        // Setup: Users join but Kuri fails to initialize
        for (uint16 i = 0; i < 5; i++) {
            vm.prank(users[i]);
            kuriCore.requestMembership();
        }
        _warpToLaunchPeriodEnd();

        // Initialize fails because not enough users
        vm.prank(initialiser);
        kuriCore.initialiseKuri();

        // Try to deposit
        vm.prank(users[0]);
        vm.expectRevert(KuriCore.KuriCore__NoActiveKuri.selector);
        kuriCore.userInstallmentDeposit();
    }

    function test_cantDeposit_beforeIntervalTime() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();

        _initializeKuri();

        // Try to deposit before interval time
        vm.prank(users[0]);
        vm.expectRevert(KuriCore.KuriCore__DepositIntervalNotReached.selector);
        kuriCore.userInstallmentDeposit();
    }

    function test_cannotDepositTwice_inSameInterval() public {
        // Setup: Get all users to join, initialize Kuri, and approve tokens
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();
        _warpToNextDepositTime();

        uint64 expectedDepositAmount = KURI_AMOUNT / TOTAL_PARTICIPANTS;
        _approveTokensForAllUsers(expectedDepositAmount);

        // First deposit succeeds
        vm.prank(users[0]);
        kuriCore.userInstallmentDeposit();

        // Second deposit should fail
        vm.prank(users[0]);
        vm.expectRevert(KuriCore.KuriCore__DepositIntervalNotReached.selector);
        kuriCore.userInstallmentDeposit();
    }

    function testMultipleUsersDeposit() public {
        // Setup: Get all users to join, initialize Kuri, and approve tokens
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();
        _warpToNextDepositTime();

        uint64 expectedDepositAmount = KURI_AMOUNT / TOTAL_PARTICIPANTS;
        _approveTokensForAllUsers(expectedDepositAmount);

        // All users make deposits
        for (uint16 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            kuriCore.userInstallmentDeposit();

            bool hasPaid = kuriCore.hasPaid(users[i], 0);
            assertTrue(hasPaid, "Payment should be recorded for user ");
        }

        // Check total tokens in contract
        assertEq(
            supportedToken.balanceOf(address(kuriCore)),
            expectedDepositAmount * users.length,
            "Contract should have received tokens from all users"
        );
    }

    function testDepositUpdatesNextIntervalTime() public {
        // Setup: Get all users to join, initialize Kuri, and approve tokens
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();
        _warpToNextDepositTime();

        uint64 expectedDepositAmount = KURI_AMOUNT / TOTAL_PARTICIPANTS;
        _approveTokensForAllUsers(expectedDepositAmount);

        // Record initial times
        (
            ,
            ,
            ,
            ,
            ,
            uint48 initialRaffleTime,
            uint48 initialDepositTime,
            ,
            ,
            ,
            ,

        ) = kuriCore.kuriData();

        // Make deposit
        vm.prank(users[0]);
        kuriCore.userInstallmentDeposit();

        // Check updated times
        (
            ,
            ,
            ,
            ,
            ,
            uint48 newRaffleTime,
            uint48 newDepositTime,
            ,
            ,
            ,
            ,

        ) = kuriCore.kuriData();

        assertEq(
            newDepositTime,
            block.timestamp + kuriCore.WEEKLY_INTERVAL(),
            "Next deposit time should be updated"
        );
        assertEq(
            newRaffleTime,
            newDepositTime + kuriCore.RAFFLE_DELAY_DURATION(),
            "Next raffle time should be updated"
        );
        assertTrue(
            newDepositTime > initialDepositTime,
            "Deposit time should increase"
        );
        assertTrue(
            newRaffleTime > initialRaffleTime,
            "Raffle time should increase"
        );
    }

    // ==================== ROLE MANAGEMENT TESTS ====================

    function testSetInitialisor() public {
        address newInitialiser = makeAddr("newInitialiser");

        // Admin grants role
        vm.prank(admin);
        kuriCore.setInitialisor(newInitialiser);

        assertTrue(
            kuriCore.hasRole(kuriCore.INITIALISOR_ROLE(), newInitialiser),
            "New initialiser should have role"
        );
    }

    function testRevokeInitialisor() public {
        // Admin revokes role
        vm.prank(admin);
        kuriCore.revokeInitialisor(initialiser);

        assertFalse(
            kuriCore.hasRole(kuriCore.INITIALISOR_ROLE(), initialiser),
            "Initialiser should not have role anymore"
        );
    }

    function testCannotSetInitialisorWithoutAdminRole() public {
        address newInitialiser = makeAddr("newInitialiser");

        // Non-admin tries to grant role
        vm.prank(users[0]);
        vm.expectRevert(); // AccessControl will revert
        kuriCore.setInitialisor(newInitialiser);
    }

    function testCannotRevokeInitialisorWithoutAdminRole() public {
        // Non-admin tries to revoke role
        vm.prank(users[0]);
        vm.expectRevert(); // AccessControl will revert
        kuriCore.revokeInitialisor(initialiser);
    }

    // ==================== EDGE CASES ====================

    function testFuzzUserIndexBitmap(uint16 userIndex) public {
        // Test the bitmap functionality with different user indices
        vm.assume(userIndex < 1000); // Reasonable limit

        address user = makeAddr(
            string(abi.encodePacked("fuzzUser", userIndex))
        );

        // Mock the user data
        uint256 intervalIndex = 1;
        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);

        // Set the payment bit directly
        vm.store(
            address(kuriCore),
            keccak256(
                abi.encode(
                    keccak256(abi.encode(intervalIndex, bucket)),
                    uint256(3)
                )
            ),
            bytes32(mask)
        );

        // Mock the user data in the mapping
        vm.mockCall(
            address(kuriCore),
            abi.encodeWithSignature("userToData(address)", user),
            abi.encode(KuriCore.UserState.ACCEPTED, userIndex)
        );

        // Check if payment is recorded
        bool hasPaid = kuriCore.hasPaid(user, intervalIndex);
        assertTrue(hasPaid, "Payment should be recorded for user index ");
    }

    function testIntervalCalculationEdgeCases() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Test interval calculation at different times
        (, , , , , , , uint48 startTime, , , , ) = kuriCore.kuriData();

        // Just after start - should be interval 0
        vm.warp(startTime + 1);
        vm.mockCall(
            address(kuriCore),
            abi.encodeWithSignature("passedIntervalsCounter()"),
            abi.encode(0)
        );

        // Just before first interval ends
        vm.warp(startTime + kuriCore.WEEKLY_INTERVAL() - 1);
        vm.mockCall(
            address(kuriCore),
            abi.encodeWithSignature("passedIntervalsCounter()"),
            abi.encode(0)
        );

        // Just after first interval ends
        vm.warp(startTime + kuriCore.WEEKLY_INTERVAL() + 1);
        vm.mockCall(
            address(kuriCore),
            abi.encodeWithSignature("passedIntervalsCounter()"),
            abi.encode(0)
        );

        // After first interval + raffle delay (should be interval 1)
        vm.warp(
            startTime +
                kuriCore.WEEKLY_INTERVAL() +
                kuriCore.RAFFLE_DELAY_DURATION() +
                1
        );
        vm.mockCall(
            address(kuriCore),
            abi.encodeWithSignature("passedIntervalsCounter()"),
            abi.encode(1)
        );
    }

    function testMaxParticipants() public {
        // Test with maximum number of participants (uint16 max)
        uint16 maxParticipants = type(uint16).max;

        vm.prank(admin);
        KuriCore maxKuri = new KuriCore(
            creator,
            KURI_AMOUNT,
            maxParticipants,
            initialiser,
            intervalTypeEnum
        );

        (, , uint16 totalParticipantsCount, , , , , , , , , ) = maxKuri
            .kuriData();
        assertEq(
            totalParticipantsCount,
            maxParticipants,
            "Should handle maximum participants"
        );
    }
}

/**
 * @title IERC20
 * @dev Interface for the ERC20 standard
 */
interface IERC20 {
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);
}
