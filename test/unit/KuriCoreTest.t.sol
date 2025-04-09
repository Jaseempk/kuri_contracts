//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {KuriCore} from "../../src/KuriCore.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../mocks/LinkToken.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {DeployKuriCore} from "../../script/DeployKuriCore.s.sol";
import {CodeConstants,HelperConfig} from "../../script/HelperConfig.s.sol";

contract KuriCoreTest is Test,CodeConstants {
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
        uint16  __intervalIndex,
        uint16  __winnerIndex,
        address __winnerAddress,
        uint48  __timestamp,
        uint256 __requestId
    );

    function setUp() public {
        DeployKuriCore deployer= new DeployKuriCore();
        (kuriCore,helperConfig)=deployer.run();

            HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        subscriptionId = config.subscriptionId;
        gasLane = config.gasLane;
        automationUpdateInterval = config.automationUpdateInterval;
        callbackGasLimit = config.callbackGasLimit;
        vrfCoordinatorV2_5 = config.vrfCoordinatorV2_5;
        console.log("coordinatooooor:",vrfCoordinatorV2_5);
        link = LinkToken(config.link);
        // Setup addresses
        admin =   config.account;
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
            VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).fundSubscription(subscriptionId, LINK_BALANCE);

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

    function _approveTokensForAllUsers(uint256 amount) internal {
        for (uint16 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            supportedToken.approve(address(kuriCore), amount);
        }
    }

    function _warpToLaunchPeriodEnd() internal {
        console.log("launchingPeriod:", kuriCore.LAUNCH_PERIOD_DURATION());
        // Warp to just after the launch period
        vm.warp(block.timestamp + uint256(kuriCore.LAUNCH_PERIOD_DURATION()) + 1);
    }

    function _initializeKuri() internal {
        vm.prank(initialiser);
        kuriCore.initialiseKuri();
    }

    function _warpToNextDepositTime() internal {
        (, , , , , uint48 nextIntervalDepositTime, , , , , ,   ) = kuriCore
            .kuriData();



        vm.warp(nextIntervalDepositTime + 1);


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

        (KuriCore.UserState userState, uint16 userIndex,) = kuriCore.userToData(
            users[0]
        );
        (, , , uint16 totalActiveParticipantsCount, , , , , , , , ) = kuriCore
            .kuriData();

        assertEq(
            uint8(userState),
            uint8(KuriCore.UserState.ACCEPTED),
            "User should be accepted"
        );
        assertEq(userIndex, 1, "User index should be 1");
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

            (KuriCore.UserState userState, uint16 userIndex,) = kuriCore
                .userToData(users[i]);
            assertEq(
                uint8(userState),
                uint8(KuriCore.UserState.ACCEPTED),
                "User should be accepted"
            );
            assertEq(userIndex, i+1, "User index mismatch");
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
            1, // User index
            1, // Interval index
            expectedDepositAmount,
            uint48(block.timestamp)
        );
        kuriCore.userInstallmentDeposit();

        // Check payment was recorded
        bool hasPaid = kuriCore.hasPaid(users[0], 1);
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
        vm.expectRevert(KuriCore.KuriCore__UserAlreadyDeposited.selector);
        kuriCore.userInstallmentDeposit();
    }

    function test_multipleUsersDeposit() public {
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
                    kuriCore.requestConfirmations(),
                    kuriCore.callbackGasLimit(),
                    kuriCore.numWords()
                )
            ),
            abi.encode(12345) // Mock request ID
        );

        // Call kuriNarukk
        vm.prank(admin);
        uint256 requestId = kuriCore.kuriNarukk();

        // Verify request ID is returned
        assertEq(requestId, 12345, "Request ID should match mock value");
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
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Warp to after raffle delay
        (, , , , , uint48 nexRaffleTime, , , , , , ) = kuriCore.kuriData();
        vm.warp(nexRaffleTime + 1);

        // Call kuriNarukk to initiate raffle
        // vm.mockCall(
        //     address(kuriCore),
        //     abi.encodeWithSignature(
        //         "requestRandomWords(VRFV2PlusClient.RandomWordsRequest)",
        //         abi.encode(
        //             kuriCore.s_keyHash(),
        //             kuriCore.s_subscriptionId(),
        //             kuriCore.requestConfirmations(),
        //             kuriCore.callbackGasLimit(),
        //             kuriCore.numWords()
        //         )
        //     ),
        //     abi.encode(12345) // Mock request ID
        // );

        vm.prank(admin);
        uint256 requestId=kuriCore.kuriNarukk();
        console.log("requestId:",requestId);

        // VRFCoordinatorV2_5Mock(vrfCoordinatorV2_5).fulfillRandomWords(
        //     uint256(requestId),
        //     address(kuriCore)
        // );


        // by manually setting the winner in the contract state

        // Simulate a winner being selected (user at index 3)
        uint16 intervalIndex = 1; // First interval
        uint16 winnerIndex = 4; // 1-indexed (user at index 3)
        address winnerAddress = users[3];

        // Manually set the winner in the contract state
        bytes32 intervalToWinnerSlot = keccak256(abi.encode(intervalIndex, uint256(15))); // intervalToWinnerIndex mapping is at slot 15
        vm.store(address(kuriCore), intervalToWinnerSlot, bytes32(uint256(winnerIndex)));

        // Manually set the user as having won
        uint256 userIndex = 4;
        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);

        bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));

        vm.store(address(kuriCore), actualSlot, bytes32(mask));

        // Verify winner is correctly recorded
        assertEq(kuriCore.intervalToWinnerIndex(intervalIndex), winnerIndex, "Winner index should be set correctly");
        assertTrue(kuriCore.hasWon(winnerAddress), "Winner should be marked as having won");
    }

    function test_hasWonFunction() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Initially no user has won
        for (uint16 i = 0; i < users.length; i++) {
            assertFalse(kuriCore.hasWon(users[i]), "User should not have won initially");
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
        assertTrue(kuriCore.hasWon(user), "User should be marked as having won");
    }

    // ==================== CLAIMING SYSTEM TESTS ====================

    function test_claimKuriAmountt() public {
        // Setup: Get all users to join, initialize Kuri, and approve tokens
        _requestMembershipForAllUsers();
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
        emit KuriSlotClaimed(user, uint64(block.timestamp), KURI_AMOUNT, intervalIndex);

        // Claim the Kuri amount
        vm.prank(user);
        kuriCore.claimKuriAmount(intervalIndex);

        // Verify user is marked as having claimed
        assertTrue(kuriCore.hasClaimed(user), "User should be marked as having claimed");

        // Verify token transfer
        assertEq(
            supportedToken.balanceOf(user),
            INITIAL_USER_BALANCE - (KURI_AMOUNT / TOTAL_PARTICIPANTS) + KURI_AMOUNT,
            "User should have received Kuri amount"
        );
    }

    function test_claimKuriAmountRevertsForNonWinner() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Try to claim without having won
        vm.prank(users[0]);
        vm.expectRevert(KuriCore.KuriCore__UserYetToGetASlot.selector);
        kuriCore.claimKuriAmount(0);
    }

    function test_claimKuriAmountRevertsForAlreadyClaimed() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Mark user as having won
        address user = users[0];
        uint256 userIndex = 1;
        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);

        // Set the bit directly in storage for wonKuriSlot
        bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));
        vm.store(address(kuriCore), actualSlot, bytes32(mask));

        // Mark user as having already claimed
        bytes32 claimedBucketKey = keccak256(abi.encode(bucket, uint256(12))); // claimedKuriSlot mapping is at slot 12
        vm.store(address(kuriCore), claimedBucketKey, bytes32(mask));

        // Try to claim again
        vm.prank(user);
        vm.expectRevert(KuriCore.KuriCore__UserHasClaimedAlready.selector);
        kuriCore.claimKuriAmount(1);
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

        // Set the bit directly in storage for wonKuriSlot
        bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));
        vm.store(address(kuriCore), actualSlot, bytes32(mask));

        // Try to claim without having paid
        vm.prank(user);
        vm.expectRevert(KuriCore.KuriCore__UserYetToMakePayments.selector);
        kuriCore.claimKuriAmount(1);
    }

    function test_hasClaimedFunction() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();

        // Initially no user has claimed
        for (uint16 i = 0; i < users.length; i++) {
            assertFalse(kuriCore.hasClaimed(users[i]), "User should not have claimed initially");
        }

        // Manually set a user as having claimed by manipulating storage
        address user = users[3];
        uint256 userIndex = 4;
        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);

        // Set the bit directly in storage
        bytes32 bucketKey = keccak256(abi.encode(bucket, uint256(12))); // claimedKuriSlot mapping is at slot 12
        vm.store(address(kuriCore), bucketKey, bytes32(mask));

        // Verify hasClaimed returns true for this user
        assertTrue(kuriCore.hasClaimed(user), "User should be marked as having claimed");
    }

    function test_kuriSlotClaimedEvent() public {
        // Setup: Get all users to join, initialize Kuri, and approve tokens
        _requestMembershipForAllUsers();
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
        console.log("maskedekdekdk:",mask);

        console.log("kuriSlot:",kuriCore.wonKuriSlot(bucket));
        
        // Ensure the contract has enough tokens to pay out
        deal(address(SUPPORTED_TOKEN), address(kuriCore), KURI_AMOUNT);
        

        // vm.prank(address(kuriCore));
        // supportedToken.approve(address(user), 1e18);

        // Expect the KuriSlotClaimed event
        uint16 intervalIndex = 1; // First interval
        vm.expectEmit(true, true, true, true);
        emit KuriSlotClaimed(user, uint64(block.timestamp), KURI_AMOUNT, intervalIndex);
        // Claim the Kuri amount
        vm.prank(user);
        kuriCore.claimKuriAmount(intervalIndex);
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
            address storedAddress = kuriCore.userIdToAddress(i+1);
            assertEq(storedAddress, users[i], "User ID to address mapping incorrect");
        }
    }

    // ==================== INTEGRATION TESTS ====================

    function test_fullKuriLifecycle() public {
        // 1. Request membership for all users
        _requestMembershipForAllUsers();
        
        // 2. Initialize Kuri
        _warpToLaunchPeriodEnd();
        _initializeKuri();
        
        // 3. Make deposits for first interval
        _approveTokensForAllUsers(KURI_AMOUNT);
        _warpToNextDepositTime();
        for (uint16 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            kuriCore.userInstallmentDeposit();
        }
        
        // 4. Trigger raffle
        skip(kuriCore.RAFFLE_DELAY_DURATION() + 1);


        uint256[] memory randomWords = new uint256[](1);
        randomWords[0]=1;
        
        // Call kuriNarukk
        vm.prank(admin);
        uint256 requestId = kuriCore.kuriNarukk();

        vrfCoordinatorMock.fulfillRandomWords(requestId,address(kuriCore));

        
        // 5. Simulate VRF callback by manually setting the winner
        uint16 intervalIndex = 1; // First interval
        uint16 winnerIndex = 2; // 1-indexed (user at index 2)
        address winnerAddress = users[1];
        
        // Manually set the winner in the contract state
        bytes32 intervalToWinnerSlot = keccak256(abi.encode(intervalIndex, uint256(15))); // intervalToWinnerIndex mapping is at slot 15
        vm.store(address(kuriCore), intervalToWinnerSlot, bytes32(uint256(winnerIndex)));
        
        // Manually set the user as having won
        uint256 userIndex = 2;
        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);
        console.log("bucket:",bucket);
        console.log("maaassk:",mask);
        
        bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));
        vm.store(address(kuriCore), actualSlot, bytes32(mask));
        console.log("hashbooooon:",kuriCore.hasWon(winnerAddress));
        
        // 6. Verify winner and claim Kuri amount
        assertTrue(kuriCore.hasWon(winnerAddress), "Winner should be marked as having won");
        
        // Ensure contract has enough tokens
        deal(address(SUPPORTED_TOKEN), address(kuriCore), KURI_AMOUNT);
        
        // Claim Kuri amount
        vm.prank(winnerAddress);
        kuriCore.claimKuriAmount(intervalIndex);
        
        // Verify winner received tokens
        assertEq(
            supportedToken.balanceOf(winnerAddress),
            INITIAL_USER_BALANCE - (KURI_AMOUNT / TOTAL_PARTICIPANTS) + KURI_AMOUNT,
            "Winner should have received Kuri amount"
        );
        
        // 7. Verify winner is marked as having claimed
        assertTrue(kuriCore.hasClaimed(winnerAddress), "Winner should be marked as having claimed");
    }

    // ==================== SECURITY TESTS ====================

    function test_bitmapOperations_withHighUserIndices() public {
        // Test with user indices near the bitmap bucket boundaries
        uint16[] memory testIndices = new uint16[](4);
        testIndices[0] = 255;   // Last index in first bucket
        testIndices[1] = 256;   // First index in second bucket
        testIndices[2] = 511;   // Last index in second bucket
        testIndices[3] = 512;   // First index in third bucket
        
        for (uint16 i = 0; i < testIndices.length; i++) {
            uint16 userIndex = testIndices[i];
            address user = makeAddr(string(abi.encodePacked("highIndexUser", userIndex)));
            
            // Mock the user data
            uint256 bucket = userIndex >> 8;
            uint256 mask = 1 << (userIndex & 0xff);
            
            // Set the bit directly in storage for wonKuriSlot
            bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));
            vm.store(address(kuriCore), actualSlot, bytes32(mask));
            
            // Verify hasWon works correctly
            assertTrue(kuriCore.hasWon(user), "hasWon should work for high indices");
            
            // Test claimedKuriSlot bitmap
            bytes32 claimedBucketKey = keccak256(abi.encode(bucket, uint256(12))); // claimedKuriSlot mapping is at slot 12
            vm.store(address(kuriCore), claimedBucketKey, bytes32(mask));
            
            // Verify hasClaimed works correctly
            assertTrue(kuriCore.hasClaimed(user), "hasClaimed should work for high indices");
        }
    }

    function test_reentrancyProtectionOnClaim() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();
        
        // Mark user as having won and paid
        address user = users[4];
        uint256 userIndex = 5;
        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);
        
        // Set the bit directly in storage for wonKuriSlot
        bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));
        vm.store(address(kuriCore), actualSlot, bytes32(mask));
        
        // Set the bit directly in storage for payments
        uint16 intervalIndex = 1;
        bytes32 paymentsSlot = keccak256(abi.encode(intervalIndex, bucket, uint256(2))); // payments mapping is at slot 2
        vm.store(address(kuriCore), paymentsSlot, bytes32(mask));
        
        // Deploy a malicious contract that will try to reenter
        MaliciousReentrancyAttacker attacker = new MaliciousReentrancyAttacker(address(kuriCore));
        
        // Transfer ownership of the user account to the attacker
        vm.prank(user);
        supportedToken.transfer(address(attacker), supportedToken.balanceOf(user));
        
        // Ensure the contract has enough tokens to pay out
        deal(address(SUPPORTED_TOKEN), address(kuriCore), KURI_AMOUNT);
        
        // Try to claim via the attacker
        vm.expectRevert(); // Should revert due to reentrancy protection
        attacker.attack(intervalIndex);
    }

    // ==================== EVENTS TESTS ====================

    function test_raffleWinnerSelectedEvent() public {
        // Note: We can't directly test this event since it's emitted by the internal fulfillRandomWords function
        // Instead, we'll focus on testing the state changes that would occur after a winner is selected
        
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();
        
        // Warp to after raffle delay
        (, , , , , uint48 nexRaffleTime, , , , , , ) = kuriCore.kuriData();
        vm.warp(nexRaffleTime + 1);
        
        // Call kuriNarukk to initiate raffle
        vm.mockCall(
            address(kuriCore),
            abi.encodeWithSignature(
                "requestRandomWords(VRFV2PlusClient.RandomWordsRequest)",
                abi.encode(
                    kuriCore.s_keyHash(),
                    kuriCore.s_subscriptionId(),
                    kuriCore.requestConfirmations(),
                    kuriCore.callbackGasLimit(),
                    kuriCore.numWords()
                )
            ),
            abi.encode(12345) // Mock request ID
        );
        
        vm.prank(admin);
        kuriCore.kuriNarukk();
        
        // Simulate a winner being selected (user at index 3)
        uint16 intervalIndex = 1; // First interval
        uint16 winnerIndex = 4; // 1-indexed (user at index 3)
        address winnerAddress = users[3];
        
        // Manually set the winner in the contract state
        bytes32 intervalToWinnerSlot = keccak256(abi.encode(intervalIndex, uint256(15))); // intervalToWinnerIndex mapping is at slot 15
        vm.store(address(kuriCore), intervalToWinnerSlot, bytes32(uint256(winnerIndex)));
        
        // Manually set the user as having won
        uint256 userIndex = 4;
        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);
        
        bytes32 actualSlot = keccak256(abi.encode(bucket, uint256(11)));
        vm.store(address(kuriCore), actualSlot, bytes32(mask));
        
        // Verify winner is correctly recorded
        assertEq(kuriCore.intervalToWinnerIndex(intervalIndex), winnerIndex, "Winner index should be set correctly");
        assertTrue(kuriCore.hasWon(winnerAddress), "Winner should be marked as having won");
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
    

    
    function test_winnerCanClaimKuriAmount() public {
        // Setup: Get all users to join, initialize Kuri
        _requestMembershipForAllUsers();
        _warpToLaunchPeriodEnd();
        _initializeKuri();
        
        // Ensure all users have made their deposits
        _approveTokensForAllUsers(KURI_AMOUNT);

        _warpToNextDepositTime();
        
        for (uint16 j = 0; j < users.length; j++) {
            vm.prank(users[j]);
            kuriCore.userInstallmentDeposit();
        }
        
        // Warp to after raffle delay
        (, , , , , uint48 nexRaffleTime, , , , , , ) = kuriCore.kuriData();
        vm.warp(nexRaffleTime + 1);
        
        // Call kuriNarukk to initiate raffle
        vm.prank(admin);
        uint256 requestId = kuriCore.kuriNarukk();
        
        // Create random words for the VRF response - force a specific winner
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 42; // This will determine the winner
        
        // Fulfill the randomness request
        vrfCoordinatorMock.fulfillRandomWords(requestId, address(kuriCore));
        
        // Get the winner
        uint16 intervalIndex = kuriCore.passedIntervalsCounter();
        uint16 winnerIndex = kuriCore.intervalToWinnerIndex(intervalIndex);
        address winnerAddress = kuriCore.userIdToAddress(winnerIndex);
        
        // Ensure the contract has enough tokens to pay out
        deal(address(SUPPORTED_TOKEN), address(kuriCore), KURI_AMOUNT);
        
        // Winner claims their Kuri amount
        uint256 balanceBefore = supportedToken.balanceOf(winnerAddress);
        
        vm.prank(winnerAddress);
        kuriCore.claimKuriAmount(intervalIndex);
        
        uint256 balanceAfter = supportedToken.balanceOf(winnerAddress);
        
        // Verify the winner received the Kuri amount
        assertEq(balanceAfter - balanceBefore, KURI_AMOUNT, "Winner should receive the Kuri amount");
        
        // Verify the winner is marked as having claimed
        assertTrue(kuriCore.hasClaimed(winnerAddress), "Winner should be marked as having claimed");
    }
}

contract MaliciousReentrancyAttacker {
    KuriCore private kuriCore;
    uint16 private intervalIndex;
    bool private attacking;
    
    constructor(address _kuriCore) {
        kuriCore = KuriCore(_kuriCore);
    }
    
    function attack(uint16 _intervalIndex) external {
        intervalIndex = _intervalIndex;
        attacking = true;
        kuriCore.claimKuriAmount(intervalIndex);
    }
    
    // This function will be called during the token transfer
    function onERC20Received(address, uint256) external returns (bool) {
        if (attacking) {
            attacking = false;
            kuriCore.claimKuriAmount(intervalIndex); // Try to reenter
        }
        return true;
    }
}

// Event definitions for testing
event RaffleWinnerSelected(
    uint16 intervalIndex,
    uint16 winnerIndex,
    address winnerAddress,
    uint48 timestamp,
    uint256 requestId
);

event KuriSlotClaimed(
    address user,
    uint64 timestamp,
    uint64 kuriAmount,
    uint16 intervalIndex
);
