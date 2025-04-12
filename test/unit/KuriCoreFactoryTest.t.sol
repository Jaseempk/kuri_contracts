//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {KuriCoreFactory} from "../../src/KuriCoreFactory.sol";
import {KuriCore} from "../../src/KuriCore.sol";
import {DeployKuriCoreFactory} from "../../script/DeployKuriCoreFactory.s.sol";
import {CodeConstants, HelperConfig} from "../../script/HelperConfig.s.sol";

contract KuriCoreFactoryTest is Test, CodeConstants {
    KuriCoreFactory kuriCoreFactory;
    HelperConfig helperConfig;

    // Constants
    uint64 public constant KURI_AMOUNT = 1000e6;
    uint16 public constant TOTAL_PARTICIPANTS = 10;

    // Test addresses
    address public creator;
    address public initialiser;
    address[] public users;

    // Events for testing
    event KuriMarketDeployed(
        address caller,
        address marketAddress,
        uint8 intervalType,
        uint256 timestamp
    );

    function setUp() public {
        DeployKuriCoreFactory deployer = new DeployKuriCoreFactory();
        (kuriCoreFactory, helperConfig) = deployer.run();

        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        // Setup addresses
        creator = config.account;
        initialiser = config.initialiser;

        // Create test users
        for (uint16 i = 0; i < TOTAL_PARTICIPANTS; i++) {
            users.push(makeAddr(string(abi.encodePacked("user", i))));
        }
    }

    // ==================== BASIC FUNCTIONALITY TESTS ====================

    function test_initialiseKuriMarket() public {
        // Test creating a KuriCore contract with weekly interval
        uint8 intervalType = uint8(KuriCore.IntervalType.WEEK);

        // Expect the KuriMarketDeployed event
        vm.expectEmit(true, true, true, false); // Don't check timestamp
        emit KuriMarketDeployed(
            address(this),
            address(0), // We don't know the address yet
            intervalType,
            0 // Don't check timestamp
        );

        // Create a new KuriCore contract
        kuriCoreFactory.initialiseKuriMarket(
            KURI_AMOUNT,
            TOTAL_PARTICIPANTS,
            intervalType
        );
    }

    function test_initialiseKuriMarketAsUser() public {
        // Test creating a KuriCore contract as a specific user
        uint8 intervalType = uint8(KuriCore.IntervalType.WEEK);

        vm.prank(users[0]);

        // Expect the KuriMarketDeployed event with the user as caller
        vm.expectEmit(true, true, true, false); // Don't check timestamp
        emit KuriMarketDeployed(
            users[0],
            address(0), // We don't know the address yet
            intervalType,
            0 // Don't check timestamp
        );

        // Create a new KuriCore contract
        kuriCoreFactory.initialiseKuriMarket(
            KURI_AMOUNT,
            TOTAL_PARTICIPANTS,
            intervalType
        );
    }

    // ==================== INTERVAL TYPE TESTS ====================

    function test_initialiseKuriMarketWithDifferentIntervals() public {
        // Test with different interval types
        uint8[] memory intervalTypes = new uint8[](3);
        intervalTypes[0] = uint8(KuriCore.IntervalType.WEEK);
        intervalTypes[1] = uint8(KuriCore.IntervalType.MONTH);

        for (uint8 i = 0; i < intervalTypes.length; i++) {
            // Expect the KuriMarketDeployed event
            vm.expectEmit(true, true, true, false); // Don't check timestamp
            emit KuriMarketDeployed(
                address(this),
                address(0), // We don't know the address yet
                intervalTypes[i],
                0 // Don't check timestamp
            );

            // Create a new KuriCore contract
            kuriCoreFactory.initialiseKuriMarket(
                KURI_AMOUNT,
                TOTAL_PARTICIPANTS,
                intervalTypes[i]
            );
        }
    }

    // ==================== PARAMETER VALIDATION TESTS ====================

    function test_initialiseKuriMarketWithInvalidIntervalType() public {
        // Test with an invalid interval type (3 is not defined in the enum)
        uint8 invalidIntervalType = 3;

        // This should revert because the enum conversion will fail
        vm.expectRevert();
        kuriCoreFactory.initialiseKuriMarket(
            KURI_AMOUNT,
            TOTAL_PARTICIPANTS,
            invalidIntervalType
        );
    }

    function test_initialiseKuriMarketWithZeroParticipants() public {
        // Test with zero participants
        uint8 intervalType = uint8(KuriCore.IntervalType.WEEK);
        uint16 zeroParticipants = 0;

        // This should revert in the KuriCore constructor
        vm.expectRevert();
        kuriCoreFactory.initialiseKuriMarket(
            KURI_AMOUNT,
            zeroParticipants,
            intervalType
        );
    }

    function test_initialiseKuriMarketWithZeroAmount() public {
        // Test with zero kuri amount
        uint8 intervalType = uint8(KuriCore.IntervalType.WEEK);
        uint64 zeroAmount = 0;

        // This should revert in the KuriCore constructor
        vm.expectRevert(KuriCoreFactory.KCF__InvalidInputs.selector);
        kuriCoreFactory.initialiseKuriMarket(
            zeroAmount,
            TOTAL_PARTICIPANTS,
            intervalType
        );
    }

    // ==================== INTEGRATION TESTS ====================

    function test_deployedKuriCoreInitialState() public {
        // Deploy a KuriCore contract
        uint8 intervalType = uint8(KuriCore.IntervalType.WEEK);

        // Create a new KuriCore contract and capture its address
        vm.recordLogs();
        address deployedAddress = kuriCoreFactory.initialiseKuriMarket(
            KURI_AMOUNT,
            TOTAL_PARTICIPANTS,
            intervalType
        );

        // Verify the deployed contract exists and has the correct initial state
        KuriCore deployedKuriCore = KuriCore(deployedAddress);

        // Check the initial state of the deployed contract
        (
            address _creator,
            uint64 _kuriAmount,
            uint16 _totalParticipantsCount,
            uint16 _totalActiveParticipantsCount,
            ,
            ,
            ,
            ,
            ,
            ,
            KuriCore.IntervalType _intervalType,
            KuriCore.KuriState _state
        ) = deployedKuriCore.kuriData();

        assertEq(
            _creator,
            address(kuriCoreFactory),
            "Creator address mismatch"
        );
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
        assertEq(uint8(_intervalType), intervalType, "Interval type mismatch");
        assertEq(
            uint8(_state),
            uint8(KuriCore.KuriState.INLAUNCH),
            "Initial state should be INLAUNCH"
        );

        // Check roles
        assertTrue(
            deployedKuriCore.hasRole(
                deployedKuriCore.DEFAULT_ADMIN_ROLE(),
                address(kuriCoreFactory)
            ),
            "Admin role not granted to creator"
        );
        assertTrue(
            deployedKuriCore.hasRole(
                deployedKuriCore.INITIALISOR_ROLE(),
                address(this)
            ),
            "Initialiser role not granted to creator"
        );
    }

    function test_multipleDeploymentsFromSameUser() public {
        // Test that a single user can deploy multiple KuriCore contracts
        uint8 intervalType = uint8(KuriCore.IntervalType.WEEK);

        // Deploy first contract
        vm.recordLogs();
        address deployedAddress1 = kuriCoreFactory.initialiseKuriMarket(
            KURI_AMOUNT,
            TOTAL_PARTICIPANTS,
            intervalType
        );

        // Deploy second contract
        vm.recordLogs();
        address deployedAddress2 = kuriCoreFactory.initialiseKuriMarket(
            KURI_AMOUNT * 2, // Different amount
            TOTAL_PARTICIPANTS + 5, // Different participant count
            intervalType
        );

        // Verify the addresses are different
        assertTrue(
            deployedAddress1 != deployedAddress2,
            "Deployed contracts should have different addresses"
        );

        // Verify the second contract has the correct parameters
        KuriCore deployedKuriCore2 = KuriCore(deployedAddress2);
        (
            ,
            uint64 _kuriAmount,
            uint16 _totalParticipantsCount,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = deployedKuriCore2.kuriData();

        assertEq(
            _kuriAmount,
            KURI_AMOUNT * 2,
            "Second contract kuri amount mismatch"
        );
        assertEq(
            _totalParticipantsCount,
            TOTAL_PARTICIPANTS + 5,
            "Second contract total participants count mismatch"
        );
    }

    function test_multipleDeploymentsFromDifferentUsers() public {
        // Test that different users can deploy KuriCore contracts
        uint8 intervalType = uint8(KuriCore.IntervalType.WEEK);

        // First user deploys a contract
        vm.prank(users[0]);
        vm.recordLogs();
        address deployedAddress1 = kuriCoreFactory.initialiseKuriMarket(
            KURI_AMOUNT,
            TOTAL_PARTICIPANTS,
            intervalType
        );

        // Second user deploys a contract
        vm.prank(users[1]);
        vm.recordLogs();
        address deployedAddress2 = kuriCoreFactory.initialiseKuriMarket(
            KURI_AMOUNT,
            TOTAL_PARTICIPANTS,
            intervalType
        );

        // Verify the addresses are different
        assertTrue(
            deployedAddress1 != deployedAddress2,
            "Deployed contracts should have different addresses"
        );

        // Verify the first contract has the correct creator
        KuriCore deployedKuriCore1 = KuriCore(deployedAddress1);
        (address _creator1, , , , , , , , , , , ) = deployedKuriCore1
            .kuriData();
        assertEq(
            _creator1,
            address(kuriCoreFactory),
            "First contract creator mismatch"
        );

        // Verify the second contract has the correct creator
        KuriCore deployedKuriCore2 = KuriCore(deployedAddress2);
        (address _creator2, , , , , , , , , , , ) = deployedKuriCore2
            .kuriData();
        assertEq(
            _creator2,
            address(kuriCoreFactory),
            "Second contract creator mismatch"
        );
    }

    // ==================== USER FLOW TESTS ====================

    function test_completeUserFlow() public {
        // Test a complete user flow: deploy contract, request membership, initialize
        uint8 intervalType = uint8(KuriCore.IntervalType.WEEK);

        // Deploy a KuriCore contract
        vm.recordLogs();
        vm.prank(users[0]); // First user is the creator
        address deployedAddress = kuriCoreFactory.initialiseKuriMarket(
            KURI_AMOUNT,
            TOTAL_PARTICIPANTS,
            intervalType
        );

        KuriCore deployedKuriCore = KuriCore(deployedAddress);

        // Users request membership
        for (uint16 i = 0; i < TOTAL_PARTICIPANTS; i++) {
            vm.prank(users[i]);

            deployedKuriCore.requestMembership();

            // Verify user state
            (
                KuriCore.UserState userState,
                uint16 userIndex,

            ) = deployedKuriCore.userToData(users[i]);
            assertEq(
                uint8(userState),
                uint8(KuriCore.UserState.ACCEPTED),
                "User should be accepted"
            );
            assertEq(userIndex, i + 1, "User index mismatch");
        }

        // Verify total active participants
        (
            ,
            ,
            ,
            uint16 totalActiveParticipantsCount,
            ,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = deployedKuriCore.kuriData();
        assertEq(
            totalActiveParticipantsCount,
            TOTAL_PARTICIPANTS,
            "Active participants count mismatch"
        );

        // Warp to after launch period
        (, , , , , , , uint48 launchPeriod, , , , ) = deployedKuriCore
            .kuriData();
        vm.warp(launchPeriod + 1);

        // Initialize Kuri
        vm.prank(users[0]); // Creator initializes
        bool success = deployedKuriCore.initialiseKuri();
        assertTrue(success, "Initialization should succeed");

        // Verify state is now ACTIVE
        (, , , , , , , , , , , KuriCore.KuriState state) = deployedKuriCore
            .kuriData();
        assertEq(
            uint8(state),
            uint8(KuriCore.KuriState.ACTIVE),
            "State should be ACTIVE after initialization"
        );
    }

    function test_failedInitialization() public {
        // Test a scenario where initialization fails due to not enough participants
        uint8 intervalType = uint8(KuriCore.IntervalType.WEEK);

        // Deploy a KuriCore contract
        vm.recordLogs();
        vm.prank(users[0]); // First user is the creator
        address deployedAddress = kuriCoreFactory.initialiseKuriMarket(
            KURI_AMOUNT,
            TOTAL_PARTICIPANTS,
            intervalType
        );

        KuriCore deployedKuriCore = KuriCore(deployedAddress);

        // Only half of the required users request membership
        for (uint16 i = 0; i < TOTAL_PARTICIPANTS / 2; i++) {
            vm.prank(users[i]);
            deployedKuriCore.requestMembership();
        }

        // Warp to after launch period
        (, , , , , , , uint48 launchPeriod, , , , ) = deployedKuriCore
            .kuriData();
        vm.warp(launchPeriod + 1);

        // Initialize Kuri - should fail
        vm.prank(users[0]); // Creator initializes
        bool success = deployedKuriCore.initialiseKuri();
        assertFalse(success, "Initialization should fail");

        // Verify state is now LAUNCHFAILED
        (, , , , , , , , , , , KuriCore.KuriState state) = deployedKuriCore
            .kuriData();
        assertEq(
            uint8(state),
            uint8(KuriCore.KuriState.LAUNCHFAILED),
            "State should be LAUNCHFAILED after failed initialization"
        );
    }

    // ==================== FUZZ TESTS ====================

    function testFuzz_initialiseKuriMarket(
        uint64 kuriAmount,
        uint16 participantCount,
        uint8 intervalType
    ) public {
        // Constrain inputs to reasonable values
        vm.assume(kuriAmount > 0 && kuriAmount < 1e18);
        vm.assume(participantCount > 0 && participantCount < 1000);
        vm.assume(intervalType < 3); // Valid interval types: 0, 1, 2

        // Create a new KuriCore contract
        vm.recordLogs();
        kuriCoreFactory.initialiseKuriMarket(
            kuriAmount,
            participantCount,
            intervalType
        );

        // Extract the deployed contract address from the emitted event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        address deployedAddress = address(
            uint160(uint256(entries[0].topics[2]))
        );

        // Verify the deployed contract exists and has the correct initial state
        KuriCore deployedKuriCore = KuriCore(deployedAddress);

        // Check the initial state of the deployed contract
        (
            address _creator,
            uint64 _kuriAmount,
            uint16 _totalParticipantsCount,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            KuriCore.IntervalType _intervalType,
            KuriCore.KuriState _state
        ) = deployedKuriCore.kuriData();

        assertEq(_creator, address(this), "Creator address mismatch");
        assertEq(_kuriAmount, kuriAmount, "Kuri amount mismatch");
        assertEq(
            _totalParticipantsCount,
            participantCount,
            "Total participants count mismatch"
        );
        assertEq(uint8(_intervalType), intervalType, "Interval type mismatch");
        assertEq(
            uint8(_state),
            uint8(KuriCore.KuriState.INLAUNCH),
            "Initial state should be INLAUNCH"
        );
    }
}
