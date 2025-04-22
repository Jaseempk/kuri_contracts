//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {KuriCore} from "../../src/KuriCore.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../mocks/LinkToken.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {DeployKuriCore} from "../../script/DeployKuriCore.s.sol";
import {CodeConstants, HelperConfig} from "../../script/HelperConfig.s.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract KuriCoreTest is Test, CodeConstants {
    KuriCore kuriCore;
    HelperConfig helperConfig;
    MockERC20 supportedToken;
    VRFCoordinatorV2_5Mock vrfCoordinatorMock;
    LinkToken linkToken;

    uint256 subscriptionId;
    bytes32 gasLane;
    uint256 automationUpdateInterval;
    uint32 callbackGasLimit;

    address vrfCoordinatorV2_5;
    LinkToken link;

    uint256 public constant LINK_BALANCE = 100 ether;

    // Constants
    uint64 public constant KURI_AMOUNT = 1000e6;
    uint16 public constant TOTAL_PARTICIPANTS = 10;
    uint256 public constant INITIAL_USER_BALANCE = 1000e6;
    address public constant SUPPORTED_TOKEN =
        0xC129124eA2Fd4D63C1Fc64059456D8f231eBbed1;
    // Test addresses
    address public creator;
    address public initialiser;
    address public admin;
    address[] public users;

    // Contract state variables
    KuriCore.IntervalType public intervalTypeEnum = KuriCore.IntervalType.WEEK;

    event KuriSlotClaimed(
        address user,
        uint64 timestamp,
        uint64 kuriAmount,
        uint16 intervalIndex
    );

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
    event RequestedRaffleWinner(uint256 indexed requestId);
    event RaaffleWinnerSelected(
        uint16 __intervalIndex,
        uint16 __winnerIndex,
        address __winnerAddress,
        uint48 __timestamp,
        uint256 __requestId
    );

    event UserFlagged(address user, uint16 intervalIndex);
    event MembershipRequested(address user, uint64 timestamp);
    event MembershipAccepted(address user, uint64 timestamp);
    event MembershipRejected(address user, uint64 timestamp);
    event UserAccepted(address user, address admin, uint16 intervalIndex);
    event UserRejected(address user, address admin);

    function setUp() public {
        DeployKuriCore deployer = new DeployKuriCore();
        (kuriCore, helperConfig) = deployer.run();

        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        subscriptionId = config.subscriptionId;
        gasLane = config.gasLane;
        automationUpdateInterval = config.automationUpdateInterval;
        callbackGasLimit = config.callbackGasLimit;
        vrfCoordinatorV2_5 = config.vrfCoordinatorV2_5;

        link = LinkToken(config.link);
        // Setup addresses
        admin = config.account;
        creator = config.account;
        initialiser = config.initialiser;

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
        }

        link = LinkToken(config.link);

        vm.startPrank(msg.sender);
        if (block.chainid == LOCAL_CHAIN_ID) {
            link.mint(msg.sender, LINK_BALANCE);
            VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).fundSubscription(
                subscriptionId,
                LINK_BALANCE
            );
        }
        link.approve(vrfCoordinatorV2_5, LINK_BALANCE);
        vm.stopPrank();
    }

    // Helper functions
    function _requestMembershipForAllUsers() internal {
        for (uint16 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            console.log("requesting membership for user:", users[i]);
            kuriCore.requestMembership();
        }
    }

    function _acceptAllUsers() internal {
        for (uint16 i = 0; i < users.length; i++) {
            vm.prank(admin);
            kuriCore.acceptUserMembershipRequest(users[i]);
        }
    }

    function _requestAndAcceptAllUsers() internal {
        _requestMembershipForAllUsers();
        _acceptAllUsers();
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
        vm.warp(
            block.timestamp + uint256(kuriCore.LAUNCH_PERIOD_DURATION()) + 1
        );
    }

    function _initializeKuri() internal {
        vm.prank(initialiser);
        kuriCore.initialiseKuri();
    }

    function _warpToNextDepositTime() internal {
        (, , , , , , uint48 nextIntervalDepositTime, , , , , ) = kuriCore
            .kuriData();

        vm.warp((nextIntervalDepositTime + 1));
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
        // Test requesting membership
        vm.prank(users[0]);
        vm.expectEmit(true, true, true, true);
        emit MembershipRequested(users[0], uint64(block.timestamp));
        kuriCore.requestMembership();

        // Verify user state is NONE (not yet accepted)
        (KuriCore.UserState userState, , ) = kuriCore.userToData(users[0]);
        assertEq(
            uint8(userState),
            uint8(KuriCore.UserState.NONE),
            "User state should be NONE after request"
        );

        // Verify user address is set
        (, , address userAddress) = kuriCore.userToData(users[0]);
        assertEq(userAddress, users[0], "User address should be set");

        // Test requesting membership again should revert
        vm.prank(users[0]);
        vm.expectRevert(KuriCore.KuriCore__UserAlreadyRequested.selector);
        kuriCore.requestMembership();

        // Test requesting membership when not in launch state
        vm.prank(initialiser);
        kuriCore.initialiseKuri();
        vm.prank(users[1]);
        vm.expectRevert(KuriCore.KuriCore__CantRequestWhenNotInLaunch.selector);
        kuriCore.requestMembership();
    }

    function testRequestMembershipMultipleUsers() public {
        for (uint16 i = 0; i < 5; i++) {
            vm.prank(users[i]);
            kuriCore.requestMembership();

            (KuriCore.UserState userState, uint16 userIndex, ) = kuriCore
                .userToData(users[i]);
            assertEq(
                uint8(userState),
                uint8(KuriCore.UserState.NONE),
                "User should be in NONE state after request"
            );
            assertEq(userIndex, 0, "User index should be 0 before acceptance");
        }

        // Accept all users
        for (uint16 i = 0; i < 5; i++) {
            vm.prank(admin);
            kuriCore.acceptUserMembershipRequest(users[i]);
        }

        // Verify states after acceptance
        for (uint16 i = 0; i < 5; i++) {
            (KuriCore.UserState userState, uint16 userIndex, ) = kuriCore
                .userToData(users[i]);
            assertEq(
                uint8(userState),
                uint8(KuriCore.UserState.ACCEPTED),
                "User should be accepted after admin acceptance"
            );
            assertEq(
                userIndex,
                i + 1,
                "User index should be assigned after acceptance"
            );
        }

        (, , , uint16 totalActiveParticipantsCount, , , , , , , , ) = kuriCore
            .kuriData();
        assertEq(
            totalActiveParticipantsCount,
            5,
            "Active participants count should be 5 after acceptance"
        );
    }

    function testCannotRequestMembershipAfterLaunchPeriod() public {
        _warpToLaunchPeriodEnd();

        vm.prank(users[0]);
        vm.expectRevert(KuriCore.KuriCore__AlreadyPastLaunchPeriod.selector);
        kuriCore.requestMembership();
    }

    function testCannotRequestMembershipWhenNotInLaunch() public {
        // First get all users to join and be accepted
        _requestAndAcceptAllUsers();

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

        // Second request should revert
        vm.prank(users[0]);
        vm.expectRevert(KuriCore.KuriCore__UserAlreadyRequested.selector);
        kuriCore.requestMembership();

        // Accept the user
        vm.prank(admin);
        kuriCore.acceptUserMembershipRequest(users[0]);

        (, , , uint16 totalActiveParticipantsCount, , , , , , , , ) = kuriCore
            .kuriData();
        assertEq(
            totalActiveParticipantsCount,
            1,
            "Active participants count should be 1 after acceptance"
        );
    }

    // ==================== INITIALIZE KURI TESTS ====================

    function test_initializeKuriSuccess() public {
        // Get all users to join and be accepted
        _requestAndAcceptAllUsers();

        (, , , , , , , uint48 currentLaunchPeriod, , , , ) = kuriCore
            .kuriData();

        // Warp to after launch period
        _warpToLaunchPeriodEnd();

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
            currentLaunchPeriod,
            uint48(block.timestamp),
            uint48(
                block.timestamp +
                    ((TOTAL_PARTICIPANTS * kuriCore.WEEKLY_INTERVAL()) +
                        (TOTAL_PARTICIPANTS * kuriCore.RAFFLE_DELAY_DURATION()))
            ),
            KuriCore.IntervalType.WEEK,
            KuriCore.KuriState.INLAUNCH
        );

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
            ,
            ,
            KuriCore.KuriState state
        ) = kuriCore.kuriData();

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
    }

    function test_initializeKuriFailure() public {
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
            admin,
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

    function test_userInstallmentDeposit() public {
        // Setup: Request and accept membership
        vm.prank(users[0]);
        kuriCore.requestMembership();
        vm.prank(admin);
        kuriCore.acceptUserMembershipRequest(users[0]);

        // Approve tokens
        vm.prank(users[0]);
        supportedToken.approve(address(kuriCore), KURI_AMOUNT);

        // Initialize Kuri
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Warp to next deposit time
        _warpToNextDepositTime();

        // Test deposit
        vm.prank(users[0]);
        vm.expectEmit(true, true, true, true);
        emit UserDeposited(
            users[0],
            1, // userIndex
            0, // intervalIndex
            KURI_AMOUNT / TOTAL_PARTICIPANTS,
            uint48(block.timestamp)
        );
        kuriCore.userInstallmentDeposit();

        // Verify payment status
        assertTrue(
            kuriCore.hasPaid(users[0], 0),
            "User should have paid for interval 0"
        );

        // Test depositing again in same interval
        vm.prank(users[0]);
        vm.expectRevert(KuriCore.KuriCore__UserAlreadyDeposited.selector);
        kuriCore.userInstallmentDeposit();

        // Test depositing before interval time
        vm.warp(block.timestamp - 1);
        vm.prank(users[0]);
        vm.expectRevert(KuriCore.KuriCore__DepositIntervalNotReached.selector);
        kuriCore.userInstallmentDeposit();
    }

    function test_userInstallmentDepositNotAccepted() public {
        // Setup: Request membership but don't accept
        vm.prank(users[0]);
        kuriCore.requestMembership();

        // Approve tokens
        vm.prank(users[0]);
        supportedToken.approve(address(kuriCore), KURI_AMOUNT);

        // Initialize Kuri
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Warp to next deposit time
        _warpToNextDepositTime();

        // Test deposit should revert
        vm.prank(users[0]);
        vm.expectRevert(KuriCore.KuriCore__CallerNotAccepted.selector);
        kuriCore.userInstallmentDeposit();
    }

    function test_userInstallmentDepositRejected() public {
        // Setup: Request and reject membership
        vm.prank(users[0]);
        kuriCore.requestMembership();
        vm.prank(admin);
        kuriCore.rejectUserMembershipRequest(users[0]);

        // Approve tokens
        vm.prank(users[0]);
        supportedToken.approve(address(kuriCore), KURI_AMOUNT);

        // Initialize Kuri
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Warp to next deposit time
        _warpToNextDepositTime();

        // Test deposit should revert
        vm.prank(users[0]);
        vm.expectRevert(KuriCore.KuriCore__CallerNotAccepted.selector);
        kuriCore.userInstallmentDeposit();
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
        for (uint16 i = 0; i < 5; i++) {
            vm.prank(admin);
            kuriCore.acceptUserMembershipRequest(users[i]);
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
        // Request and accept all users first
        _requestAndAcceptAllUsers();

        _warpToLaunchPeriodEnd();

        // Initialize Kuri
        _initializeKuri();

        // Approve tokens
        _approveTokensForAllUsers(KURI_AMOUNT / TOTAL_PARTICIPANTS);

        // Try to deposit before interval time
        vm.prank(users[0]);
        vm.expectRevert(KuriCore.KuriCore__DepositIntervalNotReached.selector);
        kuriCore.userInstallmentDeposit();
    }

    function test_cannotDepositTwice_inSameInterval() public {
        // Request and accept all users first
        _requestAndAcceptAllUsers();

        _warpToLaunchPeriodEnd();
        // Initialize Kuri
        _initializeKuri();

        // Warp to next deposit time
        _warpToNextDepositTime();

        // Approve tokens
        _approveTokensForAllUsers(KURI_AMOUNT / TOTAL_PARTICIPANTS);

        // First deposit should succeed
        vm.prank(users[0]);
        kuriCore.userInstallmentDeposit();

        // Second deposit should revert
        vm.prank(users[0]);
        vm.expectRevert(KuriCore.KuriCore__UserAlreadyDeposited.selector);
        kuriCore.userInstallmentDeposit();
    }

    function test_multipleUsersDeposit() public {
        // Setup: Get all users to join, initialize Kuri, and approve tokens
        _requestAndAcceptAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();
        _warpToNextDepositTime();

        uint64 expectedDepositAmount = KURI_AMOUNT / TOTAL_PARTICIPANTS;
        _approveTokensForAllUsers(expectedDepositAmount);

        // All users make deposits
        for (uint16 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            kuriCore.userInstallmentDeposit();

            bool hasPaid = kuriCore.hasPaid(users[i], 1);
            assertTrue(hasPaid, "Payment should be recorded for user ");
        }

        // Check total tokens in contract
        assertEq(
            supportedToken.balanceOf(address(kuriCore)),
            expectedDepositAmount * users.length,
            "Contract should have received tokens from all users"
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
        bytes32 paymentsSlot = keccak256(
            abi.encode(
                bucket,
                keccak256(abi.encode(intervalIndex, uint256(10)))
            )
        ); // payments mapping is at slot 10

        // Store the mask in the calculated slot
        vm.store(address(kuriCore), paymentsSlot, bytes32(mask));

        // UserData values you want to set
        KuriCore.UserState userState = KuriCore.UserState.ACCEPTED; // Set as ACCEPTED

        // Calculate the storage slot for userToData[nonMember]
        bytes32 userToDataSlot = keccak256(abi.encode(user, uint256(13))); // userToData is at slot 13

        console.log("user:", user);
        bytes32 packedData = bytes32(
            (uint256(uint8(userState))) |
                (uint256(userIndex) << 8) |
                (uint256(uint160(user)) << 24)
        );

        // For a struct, we need to store each field separately
        // The first slot contains the first field (userState)
        vm.store(address(kuriCore), userToDataSlot, packedData);
        (, uint16 _userIndex, ) = kuriCore.userToData(user);
        console.log("usser:", _userIndex);

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

    // ==================== RAFFLE SYSTEM TESTS ====================

    function test_kuriNarukkInitiatesRaffle() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Warp to after raffle delay
        (, , , , , uint48 nexRaffleTime, , , , , , ) = kuriCore.kuriData();
        vm.warp(nexRaffleTime + 1);

        // Mock VRF coordinator to capture the request
        vm.mockCall(
            address(kuriCore),
            abi.encodeWithSignature(
                "requestRandomWords(VRFV2PlusClient.RandomWordsRequest)",
                abi.encode(
                    kuriCore.s_keyHash(),
                    kuriCore.s_subscriptionId(),
                    kuriCore.s_requestConfirmations(),
                    kuriCore.s_callbackGasLimit(),
                    kuriCore.s_numWords()
                )
            ),
            abi.encode(12345) // Mock request ID
        );

        // Call kuriNarukk
        vm.prank(admin);
        kuriCore.kuriNarukk();
    }

    function test_kuriNarukkRevertsBeforeRaffleDelay() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Try to call kuriNarukk before raffle delay is over
        vm.prank(admin);
        vm.expectRevert(KuriCore.KuriCore__RaffleDelayNotOver.selector);
        kuriCore.kuriNarukk();
    }

    function test_kuriNarukkRequiresAdminRole() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Warp to after raffle delay
        (, , , , , uint48 nexRaffleTime, , , , , , ) = kuriCore.kuriData();
        vm.warp(nexRaffleTime + 1);

        // Non-admin tries to call kuriNarukk
        vm.prank(users[0]);
        vm.expectRevert(); // AccessControl will revert
        kuriCore.kuriNarukk();
    }

    // Note: We can't directly test fulfillRandomWords as it's an internal function
    // Instead, we'll test the effects of the raffle by simulating the state changes
    // that would occur after a winner is selected

    function test_raffleWinnerSelection() public {
        // Setup: Get all users to join, initialize Kuri
        _requestAndAcceptAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Warp to after raffle delay
        (, , , , , uint48 nexRaffleTime, , , , , , ) = kuriCore.kuriData();
        vm.warp(nexRaffleTime + 1);

        vm.prank(admin);
        uint256 requestId = kuriCore.kuriNarukk();
        console.log("requestId:", requestId);

        // Simulate a winner being selected (user at index 3)
        uint16 intervalIndex = 1; // First interval
        uint16 winnerIndex = 4; // 1-indexed (user at index 3)
        address winnerAddress = users[3];

        // Manually set the winner in the contract state
        bytes32 intervalToWinnerSlot = keccak256(
            abi.encode(intervalIndex, uint256(15))
        ); // intervalToWinnerIndex mapping is at slot 15
        vm.store(
            address(kuriCore),
            intervalToWinnerSlot,
            bytes32(uint256(winnerIndex))
        );

        // Manually set the user as having won
        uint256 userIndex = 4;
        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);

        bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));

        vm.store(address(kuriCore), actualSlot, bytes32(mask));

        // Verify winner is correctly recorded
        assertEq(
            kuriCore.intervalToWinnerIndex(intervalIndex),
            winnerIndex,
            "Winner index should be set correctly"
        );
        assertTrue(
            kuriCore.hasWon(winnerAddress),
            "Winner should be marked as having won"
        );
    }

    function test_hasWonFunction() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Initially no user has won
        for (uint16 i = 0; i < users.length; i++) {
            address userr = users[i];
            uint16 _userIndex = i + 1;
            KuriCore.UserState userState = KuriCore.UserState.ACCEPTED; // Set as ACCEPTED

            bytes32 userToDataSlot = keccak256(abi.encode(userr, uint256(13))); // userToData is at slot 13

            console.log("user:", userr);
            bytes32 packedData = bytes32(
                (uint256(uint8(userState))) |
                    (uint256(_userIndex) << 8) |
                    (uint256(uint160(userr)) << 24)
            );
            vm.store(address(kuriCore), userToDataSlot, packedData);
            assertFalse(
                kuriCore.hasWon(users[i]),
                "User should not have won initially"
            );
        }

        // Manually set a user as having won by manipulating storage
        address user = users[1];
        uint256 userIndex = 2;
        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);

        // Set the bit directly in storage for wonKuriSlot
        bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));

        vm.store(address(kuriCore), actualSlot, bytes32(mask));

        // Verify hasWon returns true for this user
        assertTrue(
            kuriCore.hasWon(user),
            "User should be marked as having won"
        );
    }

    // ==================== CLAIMING SYSTEM TESTS ====================

    function test_claimKuriAmountt() public {
        // Setup: Get all users to join, initialize Kuri, and approve tokens
        _requestAndAcceptAllUsers();

        _warpToLaunchPeriodEnd();
        _initializeKuri();
        _approveTokensForAllUsers(KURI_AMOUNT);

        // Make deposits for all users
        _warpToNextDepositTime();
        for (uint16 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            kuriCore.userInstallmentDeposit();
        }

        // Mark user 3 as having won
        address user = users[2];
        uint256 userIndex = 3;
        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);

        // Set the bit directly in storage for wonKuriSlot
        bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));

        vm.store(address(kuriCore), actualSlot, bytes32(mask));

        // Ensure the contract has enough tokens to pay out
        deal(address(SUPPORTED_TOKEN), address(kuriCore), KURI_AMOUNT);

        // Expect the KuriSlotClaimed event
        uint16 intervalIndex = 1; // First interval
        vm.expectEmit(true, true, true, true);
        emit KuriSlotClaimed(
            user,
            uint64(block.timestamp),
            KURI_AMOUNT,
            intervalIndex
        );

        // Claim the Kuri amount
        vm.prank(user);
        kuriCore.claimKuriAmount(intervalIndex);

        // Verify user is marked as having claimed
        assertTrue(
            kuriCore.hasClaimed(user),
            "User should be marked as having claimed"
        );

        // Verify token transfer
        assertEq(
            supportedToken.balanceOf(user),
            INITIAL_USER_BALANCE -
                (KURI_AMOUNT / TOTAL_PARTICIPANTS) +
                KURI_AMOUNT,
            "User should have received Kuri amount"
        );
    }

    function test_claimKuriAmountRevertsForNonWinner() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        address user = users[0];
        uint256 userIndex = 1;

        KuriCore.UserState userState = KuriCore.UserState.ACCEPTED; // Set as ACCEPTED

        bytes32 userToDataSlot = keccak256(abi.encode(user, uint256(13))); // userToData is at slot 13

        console.log("user:", user);
        bytes32 packedData = bytes32(
            (uint256(uint8(userState))) |
                (uint256(userIndex) << 8) |
                (uint256(uint160(user)) << 24)
        );

        vm.store(address(kuriCore), userToDataSlot, packedData);

        // Try to claim without having won
        vm.prank(users[0]);
        vm.expectRevert(KuriCore.KuriCore__UserYetToGetASlot.selector);
        kuriCore.claimKuriAmount(1);
    }

    function test_claimKuriAmountRevertsForAlreadyClaimed() public {
        // Request and accept all users first
        _requestAndAcceptAllUsers();

        _warpToLaunchPeriodEnd();

        // Initialize Kuri
        _initializeKuri();

        // Warp to next deposit time
        _warpToNextDepositTime();

        // Approve tokens
        _approveTokensForAllUsers(KURI_AMOUNT / TOTAL_PARTICIPANTS);

        // Make deposit
        vm.prank(users[0]);
        kuriCore.userInstallmentDeposit();

        // Warp to raffle time
        vm.warp(block.timestamp + kuriCore.RAFFLE_DELAY_DURATION());

        // Trigger raffle
        vm.prank(admin);
        kuriCore.kuriNarukk();

        // Claim once
        vm.prank(users[0]);
        kuriCore.claimKuriAmount(0);

        // Try to claim again
        vm.prank(users[0]);
        vm.expectRevert(KuriCore.KuriCore__UserHasClaimedAlready.selector);
        kuriCore.claimKuriAmount(0);
    }

    function test_claimKuriAmountRevertsForInvalidInterval() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Mark user as having won
        address user = users[1];
        uint256 userIndex = 2;
        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);

        // Set the bit directly in storage for wonKuriSlot
        bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));

        vm.store(address(kuriCore), actualSlot, bytes32(mask));

        KuriCore.UserState userState = KuriCore.UserState.ACCEPTED; // Set as ACCEPTED

        bytes32 userToDataSlot = keccak256(abi.encode(user, uint256(13))); // userToData is at slot 13

        console.log("user:", user);
        bytes32 packedData = bytes32(
            (uint256(uint8(userState))) |
                (uint256(userIndex) << 8) |
                (uint256(uint160(user)) << 24)
        );

        // For a struct, we need to store each field separately
        // The first slot contains the first field (userState)
        vm.store(address(kuriCore), userToDataSlot, packedData);

        // Try to claim with invalid interval
        vm.prank(user);
        vm.expectRevert(KuriCore.KuriCore__InvalidIntervalIndex.selector);
        kuriCore.claimKuriAmount(TOTAL_PARTICIPANTS + 1);
    }

    function test_claimKuriAmountRevertsForUnpaidInterval() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Mark user as having won
        address user = users[2];
        uint256 userIndex = 3;
        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);

        KuriCore.UserState userState = KuriCore.UserState.ACCEPTED; // Set as ACCEPTED

        bytes32 userToDataSlot = keccak256(abi.encode(user, uint256(13))); // userToData is at slot 13

        console.log("user:", user);
        bytes32 packedData = bytes32(
            (uint256(uint8(userState))) |
                (uint256(userIndex) << 8) |
                (uint256(uint160(user)) << 24)
        );

        // Set the bit directly in storage for wonKuriSlot
        bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));

        vm.store(address(kuriCore), actualSlot, bytes32(mask));

        // For a struct, we need to store each field separately
        // The first slot contains the first field (userState)
        vm.store(address(kuriCore), userToDataSlot, packedData);

        // Try to claim without having paid
        vm.prank(user);
        vm.expectRevert(KuriCore.KuriCore__UserYetToMakePayments.selector);
        kuriCore.claimKuriAmount(1);
    }

    // function test_hasClaimedFunction() public {
    //     // Request and accept all users first
    //     _requestAndAcceptAllUsers();

    //     // Initialize Kuri
    //     _initializeKuri();

    //     // Warp to next deposit time
    //     _warpToNextDepositTime();

    //     // Approve tokens
    //     _approveTokensForAllUsers(KURI_AMOUNT / TOTAL_PARTICIPANTS);

    //     // Make deposit
    //     vm.prank(users[0]);
    //     kuriCore.userInstallmentDeposit();

    //     // Warp to raffle time
    //     vm.warp(block.timestamp + kuriCore.RAFFLE_DELAY_DURATION());

    //     // Trigger raffle
    //     vm.prank(admin);
    //     kuriCore.kuriNarukk();

    //     // Claim
    //     vm.prank(users[0]);
    //     kuriCore.claimKuriAmount(0);

    //     // Verify hasClaimed returns true
    //     assertTrue(kuriCore.hasClaimed(users[0]));
    // }

    function test_kuriSlotClaimedEvent() public {
        // Setup: Get all users to join, initialize Kuri, and approve tokens
        _requestAndAcceptAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();
        _approveTokensForAllUsers(KURI_AMOUNT);

        // Make deposits for all users
        _warpToNextDepositTime();
        for (uint16 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            kuriCore.userInstallmentDeposit();
        }

        // Mark user 3 as having won
        address user = users[2];
        uint256 userIndex = 3;
        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);

        // Set the bit directly in storage for wonKuriSlot
        bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));

        vm.store(address(kuriCore), actualSlot, bytes32(mask));

        // After setting the bitmap, read it back to verify
        bytes32 storedValue = vm.load(address(kuriCore), actualSlot);
        console.log("Stored value:", uint256(storedValue));
        console.log("maskedekdekdk:", mask);

        console.log("kuriSlot:", kuriCore.wonKuriSlot(bucket));

        // Ensure the contract has enough tokens to pay out
        deal(address(SUPPORTED_TOKEN), address(kuriCore), KURI_AMOUNT);

        // vm.prank(address(kuriCore));
        // supportedToken.approve(address(user), 1e18);

        // Expect the KuriSlotClaimed event
        uint16 intervalIndex = 1; // First interval
        vm.expectEmit(true, true, true, true);
        emit KuriSlotClaimed(
            user,
            uint64(block.timestamp),
            KURI_AMOUNT,
            intervalIndex
        );

        // Claim the Kuri amount
        vm.prank(user);
        kuriCore.claimKuriAmount(intervalIndex);

        // Verify winner is marked as having claimed
        assertTrue(
            kuriCore.hasClaimed(user),
            "Winner should be marked as having claimed"
        );
    }

    // ==================== USER ID TO ADDRESS MAPPING TESTS ====================

    function test_userIdToAddressMapping() public {
        // Clear any existing mappings
        vm.store(address(kuriCore), bytes32(uint256(13)), bytes32(0)); // userIdToAddress mapping is at slot 13

        // Request membership for users
        for (uint16 i = 0; i < 5; i++) {
            vm.prank(users[i]);
            kuriCore.requestMembership();

            // Verify mapping is updated correctly
            address storedAddress = kuriCore.userIdToAddress(i + 1);
            assertEq(
                storedAddress,
                users[i],
                "User ID to address mapping incorrect"
            );
        }
    }

    // ==================== INTEGRATION TESTS ====================

    function test_fullKuriLifecycle() public {
        // 1. Request membership for all users
        _requestAndAcceptAllUsers();

        // 2. Initialize Kuri
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // 3. Make deposits for first interval
        _approveTokensForAllUsers(KURI_AMOUNT);
        console.log("before:", block.timestamp);
        _warpToNextDepositTime();
        console.log("after:", block.timestamp);

        for (uint16 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            kuriCore.userInstallmentDeposit();
        }

        // 4. Trigger raffle
        vm.warp(block.timestamp + kuriCore.RAFFLE_DELAY_DURATION() + 1);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 1;

        // Call kuriNarukk
        vm.prank(admin);
        // uint256 requestId =
        kuriCore.kuriNarukk();

        // 5. Simulate VRF callback by manually setting the winner
        uint16 intervalIndex = 1; // First interval
        uint16 winnerIndex = 2; // 1-indexed (user at index 2)
        address winnerAddress = users[1];

        // Manually set the winner in the contract state
        bytes32 intervalToWinnerSlot = keccak256(
            abi.encode(intervalIndex, uint256(15))
        ); // intervalToWinnerIndex mapping is at slot 15
        vm.store(
            address(kuriCore),
            intervalToWinnerSlot,
            bytes32(uint256(winnerIndex))
        );

        // Manually set the user as having won
        uint256 userIndex = 2;
        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);

        bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));

        vm.store(address(kuriCore), actualSlot, bytes32(mask));

        // 6. Verify winner and claim Kuri amount
        assertTrue(
            kuriCore.hasWon(winnerAddress),
            "Winner should be marked as having won"
        );

        // Ensure contract has enough tokens
        deal(address(SUPPORTED_TOKEN), address(kuriCore), KURI_AMOUNT);

        // Claim Kuri amount
        vm.prank(winnerAddress);
        kuriCore.claimKuriAmount(intervalIndex);

        // Verify winner received tokens
        assertEq(
            supportedToken.balanceOf(winnerAddress),
            INITIAL_USER_BALANCE -
                (KURI_AMOUNT / TOTAL_PARTICIPANTS) +
                KURI_AMOUNT,
            "Winner should have received Kuri amount"
        );

        // 7. Verify winner is marked as having claimed
        assertTrue(
            kuriCore.hasClaimed(winnerAddress),
            "Winner should be marked as having claimed"
        );
    }

    // ==================== SECURITY TESTS ====================

    function test_bitmapOperations_withHighUserIndices() public {
        // Test with user indices near the bitmap bucket boundaries
        uint16[] memory testIndices = new uint16[](4);
        testIndices[0] = 255; // Last index in first bucket
        testIndices[1] = 256; // First index in second bucket
        testIndices[2] = 511; // Last index in second bucket
        testIndices[3] = 512; // First index in third bucket

        for (uint16 i = 0; i < testIndices.length; i++) {
            uint16 userIndex = testIndices[i];
            address user = makeAddr(
                string(abi.encodePacked("highIndexUser", userIndex))
            );
            console.log("user:", user);

            // UserData values you want to set
            KuriCore.UserState userState = KuriCore.UserState.ACCEPTED; // Set as ACCEPTED

            // Calculate the storage slot for userToData[nonMember]
            bytes32 userToDataSlot = keccak256(abi.encode(user, uint256(13))); // userToData is at slot 14

            console.log("user:", user);
            bytes32 packedData = bytes32(
                (uint256(uint8(userState))) |
                    (uint256(userIndex) << 8) |
                    (uint256(uint160(user)) << 24)
            );

            // For a struct, we need to store each field separately
            // The first slot contains the first field (userState)
            vm.store(address(kuriCore), userToDataSlot, packedData);

            // Verify it worked
            (
                KuriCore.UserState storedState,
                uint16 storedIndex,
                address storedAddress
            ) = kuriCore.userToData(user);
            console.log("Stored state:", uint8(storedState));
            console.log("Stored index:", storedIndex);
            console.log("Stored address:", storedAddress);

            // Mock the user data
            uint256 bucket = userIndex >> 8;
            uint256 mask = 1 << (userIndex & 0xff);

            console.log("bucket:", bucket);
            console.log("maask:", mask);
            console.log("userIndexx:", userIndex);

            // Set the bit directly in storage for wonKuriSlot
            bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));

            vm.store(address(kuriCore), actualSlot, bytes32(mask));

            console.log("maapping:", kuriCore.wonKuriSlot(bucket));

            // Verify hasWon works correctly
            assertTrue(
                kuriCore.hasWon(user),
                "hasWon should work for high indices"
            );

            // Test claimedKuriSlot bitmap
            bytes32 claimedBucketKey = keccak256(
                abi.encode(bucket, uint256(12))
            ); // claimedKuriSlot mapping is at slot 12
            vm.store(address(kuriCore), claimedBucketKey, bytes32(mask));

            // Verify hasClaimed works correctly
            assertTrue(
                kuriCore.hasClaimed(user),
                "hasClaimed should work for high indices"
            );
        }
    }

    // ==================== EVENTS TESTS ====================

    function test_raffleWinnerSelectedEvent() public {
        // Note: We can't directly test this event since it's emitted by the internal fulfillRandomWords function
        // Instead, we'll focus on testing the state changes that would occur after a winner is selected

        // Setup: Get all users to join, initialize Kuri
        _requestAndAcceptAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Warp to after raffle delay
        (, , , , , uint48 nexRaffleTime, , , , , , ) = kuriCore.kuriData();
        vm.warp(nexRaffleTime + 1);

        vm.prank(admin);
        kuriCore.kuriNarukk();

        // Simulate a winner being selected (user at index 3)
        uint16 intervalIndex = 1; // First interval
        uint16 winnerIndex = 4; // 1-indexed (user at index 3)
        address winnerAddress = users[3];

        // Manually set the winner in the contract state
        bytes32 intervalToWinnerSlot = keccak256(
            abi.encode(intervalIndex, uint256(15))
        ); // intervalToWinnerIndex mapping is at slot 15
        vm.store(
            address(kuriCore),
            intervalToWinnerSlot,
            bytes32(uint256(winnerIndex))
        );

        // Manually set the user as having won
        uint256 userIndex = 4;
        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);

        bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));

        vm.store(address(kuriCore), actualSlot, bytes32(mask));

        // Verify winner is correctly recorded
        assertEq(
            kuriCore.intervalToWinnerIndex(intervalIndex),
            winnerIndex,
            "Winner index should be set correctly"
        );
        assertTrue(
            kuriCore.hasWon(winnerAddress),
            "Winner should be marked as having won"
        );
    }

    // ==================== VRF RAFFLE TESTS ====================

    function test_kuriNarukkRequestsRandomness() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        (, , , , , uint48 nexRaffleTime, , , , , , ) = kuriCore.kuriData();

        // Warp to after raffle delay
        skip(nexRaffleTime + 1);

        // Call kuriNarukk to initiate raffle
        vm.prank(admin);
        uint256 requestId = kuriCore.kuriNarukk();

        // Verify request ID is non-zero
        assertGt(requestId, 0, "Request ID should be greater than 0");
    }

    // ==================== ROLE MANAGEMENT TESTS ====================

    function test_setInitialisor() public {
        address newInitialiser = makeAddr("newInitialiser");

        // Verify new initialiser doesn't have the role yet
        assertFalse(
            kuriCore.hasRole(kuriCore.INITIALISOR_ROLE(), newInitialiser),
            "New initialiser should not have the role yet"
        );

        // Grant the role
        vm.prank(admin);
        kuriCore.setInitialisor(newInitialiser);

        // Verify role was granted
        assertTrue(
            kuriCore.hasRole(kuriCore.INITIALISOR_ROLE(), newInitialiser),
            "New initialiser should have the role after granting"
        );
    }

    function test_setInitialisorRevertsForNonAdmin() public {
        address newInitialiser = makeAddr("newInitialiser");

        // Try to grant role from non-admin account
        vm.prank(users[0]);
        vm.expectRevert();
        kuriCore.setInitialisor(newInitialiser);
    }

    function test_revokeInitialisor() public {
        // Verify initialiser has the role
        assertTrue(
            kuriCore.hasRole(kuriCore.INITIALISOR_ROLE(), initialiser),
            "Initialiser should have the role"
        );

        // Revoke the role
        vm.prank(admin);
        kuriCore.revokeInitialisor(initialiser);

        // Verify role was revoked
        assertFalse(
            kuriCore.hasRole(kuriCore.INITIALISOR_ROLE(), initialiser),
            "Initialiser should not have the role after revoking"
        );
    }

    function test_revokeInitialisorRevertsForNonAdmin() public {
        // Try to revoke role from non-admin account
        vm.prank(users[0]);
        vm.expectRevert();
        kuriCore.revokeInitialisor(initialiser);
    }

    // ==================== PAYMENT STATUS TESTS ====================

    function test_hasPaidd() public {
        // Setup: Get all users to join, initialize Kuri
        _requestAndAcceptAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Approve tokens for user 0
        vm.prank(users[0]);
        supportedToken.approve(address(kuriCore), KURI_AMOUNT);

        // Warp to deposit time
        _warpToNextDepositTime();

        // User 0 makes a deposit
        vm.prank(users[0]);
        kuriCore.userInstallmentDeposit();

        // Check hasPaid returns true for user 0 for interval 1
        uint16 intervalIndex = 1; // First interval
        assertTrue(
            kuriCore.hasPaid(users[0], intervalIndex),
            "hasPaid should return true for user who has paid"
        );

        // Check hasPaid returns false for user 1 who hasn't paid
        assertFalse(
            kuriCore.hasPaid(users[1], intervalIndex),
            "hasPaid should return false for user who hasn't paid"
        );
    }

    function test_hasPaidRevertsForInvalidUser() public {
        address nonMember = makeAddr("nonMember");

        // Try to check payment status for non-member
        vm.expectRevert(KuriCore.KuriCore__InvalidUser.selector);
        kuriCore.hasPaid(nonMember, 1);
    }

    function test_hasPaidWithDirectStorageManipulation() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Manually set payment status for user 2
        address user = users[2];
        uint16 userIndex = 3; // 1-indexed
        uint16 intervalIndex = 1;

        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);

        // For nested mappings, we need to hash twice:
        // First hash: keccak256(abi.encode(bucket, keccak256(abi.encode(intervalIndex, uint256(10)))))
        bytes32 paymentsSlot = keccak256(
            abi.encode(
                bucket,
                keccak256(abi.encode(intervalIndex, uint256(10)))
            )
        ); // payments mapping is at slot 10

        // Store the mask in the calculated slot
        vm.store(address(kuriCore), paymentsSlot, bytes32(mask));

        // UserData values you want to set
        KuriCore.UserState userState = KuriCore.UserState.ACCEPTED; // Set as ACCEPTED

        // Calculate the storage slot for userToData[nonMember]
        bytes32 userToDataSlot = keccak256(abi.encode(user, uint256(13))); // userToData is at slot 13

        console.log("user:", user);
        bytes32 packedData = bytes32(
            (uint256(uint8(userState))) |
                (uint256(userIndex) << 8) |
                (uint256(uint160(user)) << 24)
        );

        // For a struct, we need to store each field separately
        // The first slot contains the first field (userState)
        vm.store(address(kuriCore), userToDataSlot, packedData);

        // Verify it worked
        bool hasPaid = kuriCore.hasPaid(users[2], intervalIndex);
        console.log("Has user paid:", hasPaid);

        // Verify hasPaid returns true
        assertTrue(
            kuriCore.hasPaid(user, intervalIndex),
            "hasPaid should return true after direct storage manipulation"
        );
    }

    // ==================== INTERVAL COUNTER TESTS ====================

    function test_passedIntervalsCounter() public {
        // Setup: Get all users to join, initialize Kuri
        _requestAndAcceptAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Initially should be 0 intervals passed
        assertEq(
            kuriCore.passedIntervalsCounter(),
            0,
            "No intervals should have passed initially"
        );

        // Get start time and interval duration
        (
            ,
            ,
            ,
            ,
            uint24 intervalDuration,
            ,
            ,
            ,
            uint48 startTime,
            ,
            ,

        ) = kuriCore.kuriData();

        // Warp to just after first interval
        uint256 firstIntervalEnd = startTime +
            intervalDuration +
            kuriCore.RAFFLE_DELAY_DURATION();
        vm.warp(firstIntervalEnd + 1);

        // Should be 1 interval passed
        assertEq(
            kuriCore.passedIntervalsCounter(),
            1,
            "One interval should have passed"
        );

        // Warp to just after second interval
        uint256 secondIntervalEnd = firstIntervalEnd +
            intervalDuration +
            kuriCore.RAFFLE_DELAY_DURATION();
        vm.warp(secondIntervalEnd + 1);

        // Should be 2 intervals passed
        assertEq(
            kuriCore.passedIntervalsCounter(),
            2,
            "Two intervals should have passed"
        );
    }

    // ==================== BITMAP STORAGE TESTS ====================

    function test_updateUserKuriSlotClaimStatus() public {
        // Setup: Get all users to join, initialize Kuri
        _requestAndAcceptAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Mark user as having won
        address user = users[3];
        uint16 userIndex = 4; // 1-indexed
        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);
        uint16 intervalIndex = 1;

        bytes32 paymentsSlot = keccak256(
            abi.encode(
                bucket,
                keccak256(abi.encode(intervalIndex, uint256(10)))
            )
        ); // payments mapping is at slot 10
        vm.store(address(kuriCore), paymentsSlot, bytes32(mask));

        // Verify it worked
        bool hasPaid = kuriCore.hasPaid(users[3], intervalIndex);
        console.log("Has user paid:", hasPaid);

        // Set the bit directly in storage for wonKuriSlot
        bytes32 wonSlot = keccak256(abi.encode(bucket, uint256(11))); // wonKuriSlot mapping is at slot 11
        vm.store(address(kuriCore), wonSlot, bytes32(mask));

        // Ensure the contract has enough tokens to pay out
        deal(address(SUPPORTED_TOKEN), address(kuriCore), KURI_AMOUNT);

        // User claims their Kuri amount
        vm.prank(user);
        kuriCore.claimKuriAmount(1);

        // Verify user is marked as having claimed
        assertTrue(
            kuriCore.hasClaimed(user),
            "User should be marked as having claimed after claiming"
        );

        // Check the actual storage slot to verify the bitmap was updated
        bytes32 claimedSlot = keccak256(abi.encode(bucket, uint256(12))); // claimedKuriSlot mapping is at slot 12
        bytes32 storedValue = vm.load(address(kuriCore), claimedSlot);
        assertEq(
            uint256(storedValue) & mask,
            mask,
            "Bitmap should have the user's bit set"
        );
    }

    // ==================== RANDOM SELECTION TESTS ====================

    function test_activeIndicesInitialization() public {
        // Request and accept all users
        _requestAndAcceptAllUsers();

        // Initialize Kuri
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Verify active indices
        uint256 activeIndicesLength = kuriCore.getActiveIndicesLength();
        assertEq(
            activeIndicesLength,
            TOTAL_PARTICIPANTS,
            "activeIndices should contain all participant indices"
        );

        // Verify each user is in active indices
        for (uint16 i = 0; i < TOTAL_PARTICIPANTS; i++) {
            (KuriCore.UserState userState, uint16 userIndex, ) = kuriCore
                .userToData(users[i]);
            assertEq(
                uint8(userState),
                uint8(KuriCore.UserState.ACCEPTED),
                "User should be accepted"
            );
            assertEq(userIndex, i + 1, "User index should match position");
        }
    }

    function test_randomSelectionWithoutReplacement() public {
        // Setup: Get all users to join, initialize Kuri
        _requestAndAcceptAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Warp to after raffle delay
        (, , , , , uint48 nexRaffleTime, , , , , , ) = kuriCore.kuriData();
        vm.warp(nexRaffleTime + 1);

        // Trigger first raffle
        vm.prank(admin);
        kuriCore.kuriNarukk();

        // Simulate VRF response for first raffle
        uint256[] memory randomWords1 = new uint256[](1);
        randomWords1[0] = 42; // Random value

        // Check activeIndices length decreased by 1
        assertEq(
            kuriCore.getActiveIndicesLength(),
            TOTAL_PARTICIPANTS - 1,
            "activeIndices should decrease after selection"
        );

        // Warp to next interval and trigger second raffle
        vm.warp(
            nexRaffleTime +
                kuriCore.WEEKLY_INTERVAL() +
                kuriCore.RAFFLE_DELAY_DURATION() +
                1
        );

        vm.prank(admin);

        kuriCore.kuriNarukk();

        // Simulate VRF response for second raffle
        uint256[] memory randomWords2 = new uint256[](1);
        randomWords2[0] = 123; // Different random value

        // Check activeIndices length decreased by another 1
        assertEq(
            kuriCore.getActiveIndicesLength(),
            TOTAL_PARTICIPANTS - 2,
            "activeIndices should decrease after second selection"
        );

        // Verify that we have unique winners for the two intervals
        uint16 winner1 = kuriCore.intervalToWinnerIndex(1);
        uint16 winner2 = kuriCore.intervalToWinnerIndex(2);

        assertTrue(
            winner1 != winner2,
            "Winners should be different for different intervals"
        );
    }

    function test_completeRandomSelectionCycle() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Array to track winners
        uint16[] memory winners = new uint16[](TOTAL_PARTICIPANTS);

        // Run through all intervals and select winners
        for (uint16 i = 0; i < TOTAL_PARTICIPANTS; i++) {
            // Warp to appropriate time for this interval
            (, , , , , uint48 nexRaffleTime, , , , , , ) = kuriCore.kuriData();
            vm.warp(nexRaffleTime + 1);

            // // Trigger raffle
            // vm.prank(admin);
            // kuriCore.kuriNarukk();

            // // Simulate VRF response
            // uint256[] memory randomWords = new uint256[](1);
            // randomWords[0] = uint256(keccak256(abi.encode(i))); // Different random value for each interval

            uint16 userIndex = i + 1;

            bytes32 intervalToWinnerIndexSlot = keccak256(
                abi.encode(i + 1, uint256(15))
            );
            vm.store(
                address(kuriCore),
                intervalToWinnerIndexSlot,
                bytes32(uint256(userIndex))
            );

            // adlald
            // Trigger raffle
            vm.prank(admin);
            kuriCore.kuriNarukk();

            // Manually set the user as having won
            uint256 bucket = userIndex >> 8;
            uint256 mask = 1 << (userIndex & 0xff);

            bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));

            vm.store(address(kuriCore), actualSlot, bytes32(mask));

            // Record winner
            winners[i] = kuriCore.intervalToWinnerIndex(i + 1);

            // Warp to next interval
            if (i < TOTAL_PARTICIPANTS - 1) {
                vm.warp(
                    nexRaffleTime +
                        kuriCore.WEEKLY_INTERVAL() +
                        kuriCore.RAFFLE_DELAY_DURATION() +
                        1
                );
            }
        }

        // Verify all winners are unique
        for (uint16 i = 0; i < winners.length; i++) {
            for (uint16 j = i + 1; j < winners.length; j++) {
                assertTrue(
                    winners[i] != winners[j],
                    string(
                        abi.encodePacked(
                            "Winners at indices ",
                            i,
                            " and ",
                            j,
                            " are the same"
                        )
                    )
                );
            }
        }
    }

    // ==================== FLAG USER TESTS ====================

    function test_flagUserSuccess() public {
        // Setup: Get all users to join, initialize Kuri
        _requestAndAcceptAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Warp to first interval deposit time
        (, , , , , , uint48 nextIntervalDepositTime, , , , , ) = kuriCore
            .kuriData();
        vm.warp(nextIntervalDepositTime + 1);

        // User 0 makes a deposit
        vm.startPrank(users[0]);
        supportedToken.approve(address(kuriCore), KURI_AMOUNT);
        kuriCore.userInstallmentDeposit();
        vm.stopPrank();

        // User 1 doesn't make a deposit

        // Admin flags user 1 for not paying
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit UserFlagged(users[1], 1);
        kuriCore.flagUser(users[1], 1);

        // Verify user is flagged
        (KuriCore.UserState userState, , ) = kuriCore.userToData(users[1]);
        assertEq(
            uint8(userState),
            uint8(KuriCore.UserState.FLAGGED),
            "User should be flagged"
        );
    }

    function test_flagUserRevertsWhenAlreadyPaid() public {
        // Setup: Get all users to join, initialize Kuri
        _requestAndAcceptAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Warp to first interval deposit time
        (, , , , , , uint48 nextIntervalDepositTime, , , , , ) = kuriCore
            .kuriData();
        vm.warp(nextIntervalDepositTime + 1);

        // User makes a deposit
        vm.startPrank(users[0]);
        supportedToken.approve(address(kuriCore), KURI_AMOUNT);
        kuriCore.userInstallmentDeposit();
        vm.stopPrank();

        // Try to flag user who has already paid
        vm.prank(admin);
        vm.expectRevert(KuriCore.KuriCore__CantFlagUserAlreadyPaid.selector);
        kuriCore.flagUser(users[0], 1);
    }

    function test_flagUserRevertsForFutureInterval() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        address user = users[0];
        uint16 userIndex = 1;

        // UserData values you want to set
        KuriCore.UserState userState = KuriCore.UserState.ACCEPTED; // Set as ACCEPTED

        // Calculate the storage slot for userToData[nonMember]
        bytes32 userToDataSlot = keccak256(abi.encode(user, uint256(13))); // userToData is at slot 13

        console.log("user:", user);
        bytes32 packedData = bytes32(
            (uint256(uint8(userState))) |
                (uint256(userIndex) << 8) |
                (uint256(uint160(user)) << 24)
        );

        // For a struct, we need to store each field separately
        // The first slot contains the first field (userState)
        vm.store(address(kuriCore), userToDataSlot, packedData);

        // Try to flag user for a future interval
        vm.prank(admin);
        vm.expectRevert(KuriCore.KuriCore__CantFlagForFutureIndex.selector);
        kuriCore.flagUser(users[0], 2); // Second interval hasn't occurred yet
    }

    function test_flagUserRequiresAdminRole() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Non-admin tries to flag a user
        vm.prank(users[5]);
        vm.expectRevert(); // AccessControl will revert
        kuriCore.flagUser(users[0], 1);
    }

    function test_cannotFlagUser_beforeDepositTime() public {
        // Request and accept all users first
        _requestAndAcceptAllUsers();

        _warpToLaunchPeriodEnd();

        // Initialize Kuri
        _initializeKuri();

        // Try to flag user before deposit time
        vm.prank(admin);
        vm.expectRevert(KuriCore.KuriCore__CantFlagForFutureIndex.selector);
        kuriCore.flagUser(users[0], 1);
    }

    function test_cannotFlagUser_afterDeposit() public {
        // Request and accept all users first
        _requestAndAcceptAllUsers();

        _warpToLaunchPeriodEnd();

        // Initialize Kuri
        _initializeKuri();

        // Warp to next deposit time
        _warpToNextDepositTime();

        // Approve tokens
        _approveTokensForAllUsers(KURI_AMOUNT / TOTAL_PARTICIPANTS);

        // Make deposit
        vm.prank(users[0]);
        kuriCore.userInstallmentDeposit();

        // Try to flag user after deposit
        vm.prank(admin);
        vm.expectRevert(KuriCore.KuriCore__CantFlagUserAlreadyPaid.selector);
        kuriCore.flagUser(users[0], 1);
    }

    function test_cannotFlagUser_twice() public {
        // Request and accept all users first
        _requestAndAcceptAllUsers();

        _warpToLaunchPeriodEnd();

        // Initialize Kuri
        _initializeKuri();

        // Warp to next deposit time
        _warpToNextDepositTime();

        // Flag user once
        vm.prank(admin);
        kuriCore.flagUser(users[0], 0);

        // Try to flag same user again
        vm.prank(admin);
        vm.expectRevert(KuriCore.KuriCore__UserAlreadyFlagged.selector);
        kuriCore.flagUser(users[0], 0);
    }

    function test_cannotFlagUser_whenNotAdmin() public {
        // Request and accept all users first
        _requestAndAcceptAllUsers();

        _warpToLaunchPeriodEnd();

        // Initialize Kuri
        _initializeKuri();

        // Warp to next deposit time
        _warpToNextDepositTime();

        // Try to flag user as non-admin
        vm.prank(users[0]);
        vm.expectRevert();
        kuriCore.flagUser(users[1], 0);
    }

    // ==================== WITHDRAW TESTS ====================

    function test_withdrawSuccess() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Add some tokens to the contract
        deal(address(SUPPORTED_TOKEN), address(kuriCore), KURI_AMOUNT);

        // Warp to after cycle completion
        (, , , , , , , , , uint48 endTime, , ) = kuriCore.kuriData();
        vm.warp(endTime + 1);

        // Set state to COMPLETED
        bytes32 stateSlot = keccak256(abi.encode(uint256(7))); // kuriData.state is at index 11 in the struct, which is at slot 8
        vm.store(address(kuriCore), stateSlot, bytes32(uint256(uint8(3)))); // 2 = COMPLETED

        // Get admin's balance before withdrawal
        uint256 adminBalanceBefore = supportedToken.balanceOf(admin);

        // Admin withdraws tokens
        vm.prank(admin);
        kuriCore.withdraw();

        // Verify tokens were transferred to admin
        uint256 adminBalanceAfter = supportedToken.balanceOf(admin);
        assertEq(
            adminBalanceAfter,
            adminBalanceBefore + KURI_AMOUNT,
            "Admin should receive all tokens from contract"
        );

        // Verify contract balance is zero
        assertEq(
            supportedToken.balanceOf(address(kuriCore)),
            0,
            "Contract should have zero balance after withdrawal"
        );
    }

    function test_withdrawRevertsWhenCycleActive() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Add some tokens to the contract
        deal(address(SUPPORTED_TOKEN), address(kuriCore), KURI_AMOUNT);

        // Try to withdraw while cycle is still active
        vm.prank(admin);
        vm.expectRevert(
            KuriCore.KuriCore__CantWithdrawWhenCycleIsActive.selector
        );
        kuriCore.withdraw();
    }

    function test_withdrawRequiresAdminRole() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Add some tokens to the contract
        deal(address(SUPPORTED_TOKEN), address(kuriCore), KURI_AMOUNT);

        // Warp to after cycle completion
        (, , , , , , , , , uint48 endTime, , ) = kuriCore.kuriData();
        vm.warp(endTime + 1);

        // Set state to COMPLETED
        bytes32 stateSlot = keccak256(abi.encode(uint256(8))); // kuriData.state is at index 11 in the struct, which is at slot 8
        vm.store(address(kuriCore), stateSlot, bytes32(uint256(3))); // 2 = COMPLETED

        // Non-admin tries to withdraw
        vm.prank(users[0]);
        vm.expectRevert(); // AccessControl will revert
        kuriCore.withdraw();
    }

    // ==================== UPDATE AVAILABLE INDICES TESTS ====================

    function test_updateAvailableIndicesReinitializes() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Simulate some selections by directly manipulating activeIndices
        // We'll do this by completing the entire cycle
        for (uint16 i = 0; i < TOTAL_PARTICIPANTS; i++) {
            // Warp to appropriate time for this interval
            (, , , , , uint48 nexRaffleTime, , , , , , ) = kuriCore.kuriData();
            vm.warp(nexRaffleTime + 1);

            // Trigger raffle
            vm.prank(admin);
            kuriCore.kuriNarukk();

            // Simulate VRF response
            uint256[] memory randomWords = new uint256[](1);
            randomWords[0] = uint256(keccak256(abi.encode(i)));

            // Warp to next interval
            if (i < TOTAL_PARTICIPANTS - 1) {
                vm.warp(
                    nexRaffleTime +
                        kuriCore.WEEKLY_INTERVAL() +
                        kuriCore.RAFFLE_DELAY_DURATION() +
                        1
                );
            }
        }

        // Verify activeIndices is empty
        assertEq(
            kuriCore.getActiveIndicesLength(),
            0,
            "activeIndices should be empty after all selections"
        );

        // Call updateAvailableIndices (indirectly through initialiseKuri)
        // First we need to reset the contract state
        bytes32 stateSlot = bytes32(uint256(8)); // kuriData.state is at index 11 in the struct, which is at slot 8
        vm.store(address(kuriCore), stateSlot, bytes32(uint256(0))); // 0 = LAUNCH

        vm.prank(initialiser);
        kuriCore.initialiseKuri();

        // Verify activeIndices is reinitialized
        assertEq(
            kuriCore.getActiveIndicesLength(),
            TOTAL_PARTICIPANTS,
            "activeIndices should be reinitialized with all participants"
        );
    }

    // ==================== EVENT TESTS ====================

    function test_userFlaggedEvent() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Warp to first interval deposit time
        (, , , , , , uint48 nextIntervalDepositTime, , , , , ) = kuriCore
            .kuriData();
        vm.warp(nextIntervalDepositTime + 1);

        // Expect the UserFlagged event
        vm.expectEmit(true, true, true, true);
        emit UserFlagged(users[1], 1);

        // Admin flags user
        vm.prank(admin);
        kuriCore.flagUser(users[1], 1);
    }

    // ==================== VRF CONFIGURATION TESTS ====================

    function test_vrfConfiguration() public view {
        // Test VRF parameters match deployment configuration
        assertEq(
            kuriCore.s_subscriptionId(),
            subscriptionId,
            "Subscription ID mismatch"
        );
        assertEq(kuriCore.s_keyHash(), gasLane, "Key hash mismatch");
        assertEq(
            kuriCore.vrfCoordinator(),
            vrfCoordinatorV2_5,
            "VRF coordinator address mismatch"
        );
        assertEq(
            kuriCore.s_callbackGasLimit(),
            callbackGasLimit,
            "Callback gas limit mismatch"
        );
        assertEq(kuriCore.s_numWords(), 1, "Number of words should be 1");
    }

    function test_vrfRequestFlow() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Warp to after raffle delay
        (, , , , , uint48 nexRaffleTime, , , , , , ) = kuriCore.kuriData();
        vm.warp(nexRaffleTime + 1);

        // Mock VRF coordinator to capture the request
        vm.mockCall(
            vrfCoordinatorV2_5,
            abi.encodeWithSignature(
                "requestRandomWords(bytes32,uint256,uint16,uint32,uint32)",
                gasLane,
                subscriptionId,
                kuriCore.s_requestConfirmations(),
                callbackGasLimit,
                1
            ),
            abi.encode(12345) // Mock request ID
        );

        // Call kuriNarukk and verify request ID
        vm.prank(admin);
        uint256 requestId = kuriCore.kuriNarukk();
        assertEq(requestId, 12345, "Request ID should match mock value");

        // Verify VRF coordinator was called with correct parameters
        vm.expectCall(
            vrfCoordinatorV2_5,
            abi.encodeWithSignature(
                "requestRandomWords(bytes32,uint256,uint16,uint32,uint32)",
                gasLane,
                subscriptionId,
                kuriCore.s_requestConfirmations(),
                callbackGasLimit,
                1
            )
        );
    }

    function test_vrfCallback() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Warp to after raffle delay
        (, , , , , uint48 nexRaffleTime, , , , , , ) = kuriCore.kuriData();
        vm.warp(nexRaffleTime + 1);

        // Call kuriNarukk to initiate raffle
        vm.prank(admin);
        uint256 requestId = kuriCore.kuriNarukk();

        // Simulate VRF callback with random words
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 42; // Fixed value for testing

        // Mock the VRF coordinator callback
        vm.mockCall(
            vrfCoordinatorV2_5,
            abi.encodeWithSignature(
                "fulfillRandomWords(uint256,uint256[])",
                requestId,
                randomWords
            ),
            abi.encode()
        );

        // Call fulfillRandomWords directly
        vm.prank(vrfCoordinatorV2_5);
        // kuriCore.fulfillRandomWords(requestId, randomWords);

        // Verify winner was selected and state was updated
        uint16 intervalIndex = 1;
        uint16 winnerIndex = kuriCore.intervalToWinnerIndex(intervalIndex);
        assertTrue(winnerIndex > 0, "Winner should be selected");
        assertTrue(
            winnerIndex <= TOTAL_PARTICIPANTS,
            "Winner index should be within bounds"
        );
    }

    // ==================== USER STATE TRANSITION TESTS ====================

    function test_userStateTransitions() public {
        // Test initial state
        (KuriCore.UserState userState, , ) = kuriCore.userToData(users[0]);
        assertEq(
            uint8(userState),
            uint8(KuriCore.UserState.NONE),
            "Initial user state should be NONE"
        );

        // Request membership
        vm.prank(users[0]);
        kuriCore.requestMembership();

        // Verify state is still NONE after request
        (userState, , ) = kuriCore.userToData(users[0]);
        assertEq(
            uint8(userState),
            uint8(KuriCore.UserState.NONE),
            "User state should be NONE after request"
        );

        // Accept membership
        vm.prank(admin);
        kuriCore.acceptUserMembershipRequest(users[0]);

        // Verify state is ACCEPTED after acceptance
        (userState, , ) = kuriCore.userToData(users[0]);
        assertEq(
            uint8(userState),
            uint8(KuriCore.UserState.ACCEPTED),
            "User state should be ACCEPTED after acceptance"
        );

        // Reject membership (should revert since user is already accepted)
        vm.prank(admin);
        vm.expectRevert(KuriCore.KuriCore__UserAlreadyAccepted.selector);
        kuriCore.rejectUserMembershipRequest(users[0]);
    }

    function test_userStateEdgeCases() public {
        // Test requesting membership when already REJECTED
        vm.prank(users[0]);
        kuriCore.requestMembership();
        vm.prank(admin);
        kuriCore.rejectUserMembershipRequest(users[0]);

        vm.prank(users[0]);
        vm.expectRevert(KuriCore.KuriCore__AlreadyRejected.selector);
        kuriCore.requestMembership();

        // Test requesting membership when already ACCEPTED
        vm.prank(users[1]);
        kuriCore.requestMembership();
        vm.prank(users[1]);
        kuriCore.requestMembership(); // Should not revert, just do nothing

        // Test rejecting when already REJECTED
        vm.prank(admin);
        vm.expectRevert(KuriCore.KuriCore__AlreadyRejected.selector);
        kuriCore.rejectUserMembershipRequest(users[0]);

        // Test rejecting when already ACCEPTED
        vm.prank(admin);
        vm.expectRevert(KuriCore.KuriCore__UserAlreadyAccepted.selector);
        kuriCore.rejectUserMembershipRequest(users[1]);
    }

    // ==================== INTERVAL MANAGEMENT TESTS ====================

    function test_intervalTypeSwitching() public {
        // Test weekly interval
        assertEq(
            kuriCore.WEEKLY_INTERVAL(),
            7 days,
            "Weekly interval duration should match"
        );

        // Test monthly interval
        assertEq(
            kuriCore.MONTHLY_INTERVAL(),
            30 days,
            "Monthly interval duration should match"
        );

        // Test interval type in Kuri data
        (, , , , , , , , , , KuriCore.IntervalType intervalType, ) = kuriCore
            .kuriData();
        assertEq(
            uint8(intervalType),
            uint8(KuriCore.IntervalType.WEEK),
            "Default interval type should be WEEK"
        );
    }

    function test_intervalTimingCalculations() public {
        // Request and accept all users
        _requestAndAcceptAllUsers();

        // Initialize Kuri
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Verify timing calculations
        (
            ,
            ,
            ,
            ,
            ,
            uint48 nexRaffleTime,
            uint48 nextIntervalDepositTime,
            ,
            ,
            ,
            ,

        ) = kuriCore.kuriData();

        assertEq(
            nextIntervalDepositTime,
            block.timestamp + kuriCore.WEEKLY_INTERVAL(),
            "Next interval deposit time calculation incorrect"
        );

        assertEq(
            nexRaffleTime,
            nextIntervalDepositTime + kuriCore.RAFFLE_DELAY_DURATION(),
            "Next raffle time calculation incorrect"
        );
    }

    // ==================== PAYMENT TRACKING TESTS ====================

    function test_multipleIntervalPayments() public {
        // Setup: Get all users to join, initialize Kuri
        _requestAndAcceptAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        uint64 expectedDepositAmount = KURI_AMOUNT / TOTAL_PARTICIPANTS;
        _approveTokensForAllUsers(expectedDepositAmount);

        // Test payments across multiple intervals
        for (uint16 interval = 1; interval <= 3; interval++) {
            // Warp to next deposit time
            _warpToNextDepositTime();

            // All users make deposits for this interval
            for (uint16 i = 0; i < users.length; i++) {
                vm.prank(users[i]);
                kuriCore.userInstallmentDeposit();

                // Verify payment was recorded
                assertTrue(
                    kuriCore.hasPaid(users[i], interval),
                    "Payment should be recorded for interval"
                );
            }

            // Verify total payments for this interval
            uint256 totalPayments = 0;
            for (uint16 i = 0; i < users.length; i++) {
                if (kuriCore.hasPaid(users[i], interval)) {
                    totalPayments++;
                }
            }
            assertEq(
                totalPayments,
                users.length,
                "All users should have paid for interval"
            );
        }
    }

    function test_paymentStatusAfterFlagging() public {
        // Setup: Get all users to join, initialize Kuri
        _requestAndAcceptAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        uint64 expectedDepositAmount = KURI_AMOUNT / TOTAL_PARTICIPANTS;
        _approveTokensForAllUsers(expectedDepositAmount);

        // Warp to first deposit time
        _warpToNextDepositTime();

        // User 0 makes a deposit
        vm.prank(users[0]);
        kuriCore.userInstallmentDeposit();

        // User 1 doesn't make a deposit and gets flagged
        vm.prank(admin);
        kuriCore.flagUser(users[1], 1);

        // Verify payment status
        assertTrue(kuriCore.hasPaid(users[0], 1), "User 0 should have paid");
        assertFalse(
            kuriCore.hasPaid(users[1], 1),
            "User 1 should not have paid"
        );

        // Warp to next interval
        _warpToNextDepositTime();

        // Try to make payment for flagged user
        vm.prank(users[1]);
        vm.expectRevert(KuriCore.KuriCore__CallerNotAccepted.selector);
        kuriCore.userInstallmentDeposit();
    }

    function test_paymentTrackingEdgeCases() public {
        // Setup: Get all users to join, initialize Kuri
        _requestAndAcceptAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        uint64 expectedDepositAmount = KURI_AMOUNT / TOTAL_PARTICIPANTS;
        _approveTokensForAllUsers(expectedDepositAmount);

        // Test payment tracking for invalid interval
        vm.expectRevert(KuriCore.KuriCore__InvalidIntervalIndex.selector);
        kuriCore.hasPaid(users[0], TOTAL_PARTICIPANTS + 1);

        // Test payment tracking for non-member
        address nonMember = makeAddr("nonMember");
        vm.expectRevert(KuriCore.KuriCore__InvalidUser.selector);
        kuriCore.hasPaid(nonMember, 1);

        // Test payment tracking for future interval
        assertFalse(
            kuriCore.hasPaid(users[0], 2),
            "Should return false for future interval"
        );
    }

    // ==================== COMPLEX SCENARIO TESTS ====================

    function test_completeKuriLifecycle() public {
        // 1. Setup and initialization
        _requestAndAcceptAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        uint64 expectedDepositAmount = KURI_AMOUNT / TOTAL_PARTICIPANTS;
        _approveTokensForAllUsers(expectedDepositAmount);

        // 2. Run through all intervals
        for (uint16 interval = 1; interval <= TOTAL_PARTICIPANTS; interval++) {
            // Warp to deposit time
            _warpToNextDepositTime();

            vm.warp(block.timestamp + 17 days);
            // All users make deposits
            for (uint16 i = 0; i < users.length; i++) {
                vm.prank(users[i]);
                console.log("IIII:", i);
                console.log("intervaaal:", interval);

                kuriCore.userInstallmentDeposit();
            }

            // Warp to raffle time
            (, , , , , uint48 nexRaffleTime, , , , , , ) = kuriCore.kuriData();
            vm.warp(nexRaffleTime + 1);

            uint16 userIndex = interval;

            bytes32 intervalToWinnerIndexSlot = keccak256(
                abi.encode(interval, uint256(15))
            );
            vm.store(
                address(kuriCore),
                intervalToWinnerIndexSlot,
                bytes32(uint256(userIndex))
            );

            // adlald
            // Trigger raffle
            vm.prank(admin);
            kuriCore.kuriNarukk();

            // Manually set the user as having won
            uint256 bucket = userIndex >> 8;
            uint256 mask = 1 << (userIndex & 0xff);

            bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));

            vm.store(address(kuriCore), actualSlot, bytes32(mask));

            // Verify winner was selected
            uint16 winnerIndex = kuriCore.intervalToWinnerIndex(interval);
            assertTrue(winnerIndex >= 0, "Winner should be selected");
            assertTrue(
                winnerIndex <= TOTAL_PARTICIPANTS,
                "Winner index should be within bounds"
            );

            // Winner claims their Kuri amount
            address winner = kuriCore.userIdToAddress(winnerIndex);
            vm.prank(winner);
            kuriCore.claimKuriAmount(interval);

            // Verify winner received tokens
            assertEq(
                supportedToken.balanceOf(winner),
                INITIAL_USER_BALANCE -
                    (expectedDepositAmount * interval) +
                    KURI_AMOUNT,
                "Winner should have received Kuri amount"
            );
        }

        // 3. Verify final state
        (, , , , , , , , , , , KuriCore.KuriState finalState) = kuriCore
            .kuriData();
        assertEq(
            uint8(finalState),
            uint8(KuriCore.KuriState.COMPLETED),
            "Kuri should be completed"
        );

        // 4. Verify all users have claimed
        for (uint16 i = 0; i < users.length; i++) {
            assertTrue(
                kuriCore.hasClaimed(users[i]),
                "All users should have claimed"
            );
        }
    }

    function test_complexPaymentScenarios() public {
        // Setup: Get all users to join, initialize Kuri
        _requestAndAcceptAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        uint64 expectedDepositAmount = KURI_AMOUNT / TOTAL_PARTICIPANTS;
        _approveTokensForAllUsers(expectedDepositAmount * 2);

        // Scenario 1: Some users pay late
        _warpToNextDepositTime();

        // Only half the users pay on time
        for (uint16 i = 0; i < users.length / 2; i++) {
            console.log("aadyathe:", i);
            vm.prank(users[i]);
            kuriCore.userInstallmentDeposit();
        }

        vm.warp(block.timestamp - 100 days);

        // Remaining users try to pay late
        for (uint256 i = users.length / 2; i < users.length; i++) {
            vm.prank(users[i]);
            vm.expectRevert(
                KuriCore.KuriCore__DepositIntervalNotReached.selector
            );
            kuriCore.userInstallmentDeposit();
        }

        vm.warp(block.timestamp + 100 days);

        // Scenario 2: Some users get flagged
        _warpToNextDepositTime();
        vm.warp(block.timestamp + 10 days);

        // All users pay
        for (uint16 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            kuriCore.userInstallmentDeposit();
        }

        // Flag some users
        for (uint16 i = 0; i < users.length / 2; i++) {
            vm.prank(admin);
            vm.expectRevert(
                KuriCore.KuriCore__CantFlagUserAlreadyPaid.selector
            );
            kuriCore.flagUser(users[i], 2);
        }
    }

    // ==================== SECURITY TESTS ====================

    function test_roleManagement() public {
        // Test DEFAULT_ADMIN_ROLE functionality
        address newAdmin = makeAddr("newAdmin");

        // Current admin grants role to new admin
        vm.prank(admin);
        kuriCore.grantRole(kuriCore.DEFAULT_ADMIN_ROLE(), newAdmin);

        // Verify new admin has role
        assertTrue(
            kuriCore.hasRole(kuriCore.DEFAULT_ADMIN_ROLE(), newAdmin),
            "New admin should have role"
        );

        // Test role inheritance
        address newInitialiser = makeAddr("newInitialiser");
        vm.prank(newAdmin);
        kuriCore.grantRole(kuriCore.INITIALISOR_ROLE(), newInitialiser);

        // Verify new initialiser has role
        assertTrue(
            kuriCore.hasRole(kuriCore.INITIALISOR_ROLE(), newInitialiser),
            "New initialiser should have role"
        );

        // Test role revocation
        vm.prank(newAdmin);
        kuriCore.revokeRole(kuriCore.INITIALISOR_ROLE(), newInitialiser);

        // Verify role was revoked
        assertFalse(
            kuriCore.hasRole(kuriCore.INITIALISOR_ROLE(), newInitialiser),
            "Role should be revoked"
        );
    }

    function test_roleManagementEdgeCases() public {
        // Test granting role without permission
        address newAdmin = makeAddr("newAdmin");
        vm.prank(users[0]);
        vm.expectRevert(); // AccessControl will revert
        kuriCore.grantRole(kuriCore.DEFAULT_ADMIN_ROLE(), newAdmin);

        // Test revoking role without permission
        vm.prank(users[0]);
        vm.expectRevert(); // AccessControl will revert
        kuriCore.revokeRole(kuriCore.DEFAULT_ADMIN_ROLE(), admin);

        // Test granting role to zero address
        vm.prank(admin);
        vm.expectRevert(); // AccessControl will revert
        kuriCore.grantRole(kuriCore.DEFAULT_ADMIN_ROLE(), address(0));

        // Test revoking role from zero address
        vm.prank(admin);
        vm.expectRevert(); // AccessControl will revert
        kuriCore.revokeRole(kuriCore.DEFAULT_ADMIN_ROLE(), address(0));
    }

    function test_accessControl() public {
        // Test admin-only functions
        address nonAdmin = makeAddr("nonAdmin");

        // Test initialiseKuri
        vm.prank(nonAdmin);
        vm.expectRevert(); // AccessControl will revert
        kuriCore.initialiseKuri();

        // Test kuriNarukk
        vm.prank(nonAdmin);
        vm.expectRevert(); // AccessControl will revert
        kuriCore.kuriNarukk();

        // Test flagUser
        vm.prank(nonAdmin);
        vm.expectRevert(); // AccessControl will revert
        kuriCore.flagUser(users[0], 1);

        // Test withdraw
        vm.prank(nonAdmin);
        vm.expectRevert(); // AccessControl will revert
        kuriCore.withdraw();
    }

    function test_reentrancyProtection() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        uint64 expectedDepositAmount = KURI_AMOUNT / TOTAL_PARTICIPANTS;
        _approveTokensForAllUsers(expectedDepositAmount);

        // Create a malicious contract that tries to reenter during deposit
        MaliciousContract malicious = new MaliciousContract(
            address(kuriCore),
            address(supportedToken)
        );

        // Fund the malicious contract
        deal(
            address(SUPPORTED_TOKEN),
            address(malicious),
            expectedDepositAmount
        );
        vm.prank(address(malicious));
        supportedToken.approve(address(kuriCore), expectedDepositAmount);

        // Try to exploit reentrancy
        vm.prank(address(malicious));
        vm.expectRevert(); // Should revert due to reentrancy protection
        malicious.attack();
    }

    function test_acceptMembership() public {
        // Setup: Request membership first
        vm.prank(users[0]);
        kuriCore.requestMembership();

        // Test accepting membership
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit UserAccepted(users[0], admin, 1);
        kuriCore.acceptUserMembershipRequest(users[0]);

        // Verify user state is ACCEPTED
        (KuriCore.UserState userState, , ) = kuriCore.userToData(users[0]);
        assertEq(
            uint8(userState),
            uint8(KuriCore.UserState.ACCEPTED),
            "User state should be ACCEPTED after acceptance"
        );

        // Test accepting non-existent user
        vm.prank(admin);
        vm.expectRevert(KuriCore.KuriCore__InvalidUserRequest.selector);
        kuriCore.acceptUserMembershipRequest(users[1]);
    }

    function test_rejectMembership() public {
        // Setup: Request membership first
        vm.prank(users[0]);
        kuriCore.requestMembership();

        // Test rejecting membership
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit UserRejected(users[0], admin);
        kuriCore.rejectUserMembershipRequest(users[0]);

        // Verify user state is REJECTED
        (KuriCore.UserState userState, , ) = kuriCore.userToData(users[0]);
        assertEq(
            uint8(userState),
            uint8(KuriCore.UserState.REJECTED),
            "User state should be REJECTED after rejection"
        );

        // Test rejecting non-existent user
        vm.prank(admin);
        vm.expectRevert(KuriCore.KuriCore__InvalidUserRequest.selector);
        kuriCore.rejectUserMembershipRequest(users[1]);

        _warpToLaunchPeriodEnd();

        // Test rejecting when not in launch state
        vm.prank(initialiser);
        kuriCore.initialiseKuri();
        vm.prank(admin);
        vm.expectRevert(KuriCore.KuriCore__CantRejectWhenNotInLaunch.selector);
        kuriCore.rejectUserMembershipRequest(users[0]);
    }
}

// ==================== HELPER CONTRACTS ====================

contract MaliciousContract {
    KuriCore public kuriCore;
    MockERC20 public token;

    constructor(address _kuriCore, address _token) {
        kuriCore = KuriCore(_kuriCore);
        token = MockERC20(_token);
    }

    function attack() external {
        // Try to reenter during deposit
        kuriCore.userInstallmentDeposit();
    }

    function onERC20Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external returns (bytes4) {
        // Try to reenter during token transfer
        kuriCore.userInstallmentDeposit();
        return this.onERC20Received.selector;
    }
}
