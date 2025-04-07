//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title KuriCore
 * @author anon
 * @notice Implementation of a Rotating Savings and Credit Association (ROSCA) system
 * @dev This contract manages a community savings group where members contribute funds
 * periodically and take turns receiving the pool. It includes membership management,
 * payment tracking, and role-based access control.
 */
contract KuriCore is AccessControl {
    //error messages
    error KuriCore__NoActiveKuri();
    error KuriCore__AlreadyRejected();
    error KuriCore__NotInLaunchState();
    error KuriCore__CallerNotAccepted();
    error KuriCore__LaunchPeriodNotOver();
    error KuriCore__UserAlreadyDeposited();
    error KuriCore__AlreadyPastLaunchPeriod();
    error KuriCore__DepositIntervalNotReached();
    error KuriCore__CantRequestWhenNotInLaunch();
    error KuriCore__InsufficientActiveParticipantCount();

    /// @notice Duration of a weekly interval in seconds (7 days)
    uint256 public constant WEEKLY_INTERVAL = 7 days;
    /// @notice Duration of a monthly interval in seconds (30 days)
    uint256 public constant MONTHLY_INTERVAL = 30 days;
    /// @notice Duration of the initial launch period in seconds (3 days)
    uint256 public constant LAUNCH_PERIOD_DURATION = 3 days;
    /// @notice Delay period after each interval before raffle in seconds (3 days)
    uint256 public constant RAFFLE_DELAY_DURATION = 3 days;
    /// @notice Role identifier for addresses authorized to initialize the Kuri
    bytes32 public constant INITIALISOR_ROLE = keccak256("INITIALISOR_ROLE");
    /// @notice Address of the token used for deposits(USDC in our case)
    address public constant SUPPORTED_TOKEN =
        0xC129124eA2Fd4D63C1Fc64059456D8f231eBbed1;

    /**
     * @notice Enum representing the possible states of a Kuri
     * @dev INLAUNCH: Initial state during member recruitment
     * @dev LAUNCHFAILED: State when not enough members joined during launch
     * @dev ACTIVE: Normal operating state after successful initialization
     * @dev COMPLETED: Final state after all cycles are complete
     */
    enum KuriState {
        INLAUNCH,
        LAUNCHFAILED,
        ACTIVE,
        COMPLETED
    }

    /**
     * @notice Enum representing the possible states of a user
     * @dev NONE: Default state
     * @dev ACCEPTED: User is an active member of the Kuri
     * @dev REJECTED: User has been rejected from the Kuri
     */
    enum UserState {
        NONE,
        ACCEPTED,
        REJECTED
    }

    /**
     * @notice Enum representing the interval type for the Kuri
     * @dev WEEK: Weekly payment intervals
     * @dev MONTH: Monthly payment intervals
     */
    enum IntervalType {
        WEEK,
        MONTH
    }

    /**
     * @notice Struct containing all data related to a Kuri instance
     * @dev Packed to optimize gas usage
     */
    struct Kuri {
        address creator; // Address that created the Kuri
        uint64 kuriAmount; // Total amount to be collected in the Kuri
        uint16 totalParticipantsCount; // Required number of participants
        uint16 totalActiveParticipantsCount; // Current number of active participants
        uint24 intervalDuration; // Duration of each interval in seconds
        uint48 nexRaffleTime; // Timestamp for the next raffle
        uint48 nextIntervalDepositTime; // Timestamp when next interval deposits can begin
        uint48 launchPeriod; // Timestamp when launch period ends
        uint48 startTime; // Timestamp when Kuri was initialized
        uint48 endTime; // Timestamp when Kuri will end
        IntervalType intervalType; // Type of interval (weekly/monthly)
        KuriState state; // Current state of the Kuri
    }

    /**
     * @notice Struct containing data for each user
     */
    struct UserData {
        UserState userState; // Current state of the user
        uint16 userIndex; // Index of the user in the participants list
    }

    /// @notice Mapping to store user data by address
    mapping(address => UserData) public userToData;
    /// @notice Main Kuri data structure
    Kuri public kuriData;

    /**
     * @notice Mapping to track payments for each interval
     * @dev Uses a bitmap for gas-efficient storage: intervalIndex => bucket => bitmap
     * where each bit in the bitmap represents whether a user has paid
     */
    mapping(uint256 => mapping(uint256 => uint256)) public payments; // month => bitmap

    /**
     * @notice Emitted when a Kuri is successfully initialized
     * @param _kuriData The Kuri data after initialization
     */
    event KuriInitialised(Kuri _kuriData);

    /**
     * @notice Emitted when a Kuri initialization fails
     * @param creator Address of the Kuri creator
     * @param kuriAmount Total amount of the Kuri
     * @param totalParticipantsCount Required number of participants
     * @param state New state of the Kuri (should be LAUNCHFAILED)
     */
    event KuriInitFailed(
        address creator,
        uint64 kuriAmount,
        uint16 totalParticipantsCount,
        KuriState state
    );

    /**
     * @notice Emitted when a user makes an installment deposit
     * @param user Address of the user making the deposit
     * @param userIndex Index of the user in the participants list
     * @param intervalIndex Index of the current interval
     * @param amountDeposited Amount deposited by the user
     * @param depositTimestamp Timestamp when the deposit was made
     */
    event UserDeposited(
        address user,
        uint256 userIndex,
        uint256 intervalIndex,
        uint64 amountDeposited,
        uint48 depositTimestamp
    );

    /**
     * @notice Creates a new Kuri instance
     * @dev Sets initial state to INLAUNCH and grants roles
     * @param _creator Address of the Kuri creator
     * @param _kuriAmount Total amount to be collected in the Kuri
     * @param _participantCount Required number of participants
     * @param _initialiser Address authorized to initialize the Kuri
     * @param _intervalType Type of interval (weekly/monthly)
     */
    constructor(
        address _creator,
        uint64 _kuriAmount,
        uint16 _participantCount,
        address _initialiser,
        IntervalType _intervalType
    ) {
        kuriData.creator = _creator;
        kuriData.kuriAmount = _kuriAmount;
        kuriData.totalParticipantsCount = _participantCount;
        kuriData.launchPeriod = uint48(
            block.timestamp + LAUNCH_PERIOD_DURATION
        );
        kuriData.intervalType = _intervalType;
        kuriData.state = KuriState.INLAUNCH;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(INITIALISOR_ROLE, _initialiser);
    }

    /**
     * @notice Initializes the Kuri after the launch period
     * @dev Can only be called by an address with the INITIALISOR_ROLE
     * @dev Transitions the Kuri from INLAUNCH to either ACTIVE or LAUNCHFAILED
     * @dev Sets up all timing parameters for the Kuri lifecycle
     * @return bool True if initialization was successful, false otherwise
     */
    function initialiseKuri()
        external
        onlyRole(INITIALISOR_ROLE)
        returns (bool)
    {
        // Verify the Kuri is in the correct state for initialization
        if (kuriData.state != KuriState.INLAUNCH)
            revert KuriCore__NotInLaunchState();
        if (kuriData.launchPeriod > block.timestamp)
            revert KuriCore__LaunchPeriodNotOver();

        // Check if enough participants have joined
        if (
            kuriData.totalParticipantsCount !=
            kuriData.totalActiveParticipantsCount
        ) {
            emit KuriInitFailed(
                kuriData.creator,
                kuriData.kuriAmount,
                kuriData.totalParticipantsCount,
                KuriState.LAUNCHFAILED
            );
            // set the state to launch failed
            kuriData.state = KuriState.LAUNCHFAILED;
            return false;
        }

        // Calculate the total number of intervals based on participants
        uint256 totalIntervals = kuriData.totalParticipantsCount;

        // Set the start time to current timestamp
        kuriData.startTime = uint48(block.timestamp);

        // Set interval duration based on the selected interval type
        kuriData.intervalDuration = kuriData.intervalType == IntervalType.WEEK
            ? uint24(WEEKLY_INTERVAL)
            : uint24(MONTHLY_INTERVAL);

        // Calculate the next interval deposit time
        kuriData.nextIntervalDepositTime = uint48(
            block.timestamp + kuriData.intervalDuration
        );

        // Calculate the end time based on total intervals
        // total time = interval duration * number of intervals + delay duration * number of intervals
        kuriData.endTime = uint48(
            block.timestamp +
                ((totalIntervals * kuriData.intervalDuration) +
                    (totalIntervals * RAFFLE_DELAY_DURATION))
        );

        // Calculate the next raffle time
        kuriData.nexRaffleTime = uint48(
            kuriData.nextIntervalDepositTime + RAFFLE_DELAY_DURATION
        );

        emit KuriInitialised(kuriData);

        // Set the Kuri state to active
        kuriData.state = KuriState.ACTIVE;

        return true;
    }

    /**
     * @notice Allows a user to request membership in the Kuri
     * @dev Can only be called during the launch period
     * @dev Adds the user to the participants list and increments the active participants count
     */
    function requestMembership() external {
        // check if the user is already a member
        if (userToData[msg.sender].userState == UserState.ACCEPTED) return;
        if (kuriData.state != KuriState.INLAUNCH)
            revert KuriCore__CantRequestWhenNotInLaunch();

        if (kuriData.launchPeriod < block.timestamp)
            revert KuriCore__AlreadyPastLaunchPeriod();

        // add the user to the accepted list
        userToData[msg.sender] = UserData(
            UserState.ACCEPTED,
            kuriData.totalActiveParticipantsCount
        );
        kuriData.totalActiveParticipantsCount++;
    }

    /**
     * @notice Allows a user to make an installment deposit
     * @dev Can only be called by accepted members when the Kuri is active
     * @dev Checks if the current interval's deposit time has been reached
     * @dev Prevents users from making multiple deposits in the same interval
     * @dev Transfers tokens from the user to the contract
     */
    function userInstallmentDeposit() external {
        // check if the user is already a member
        if (userToData[msg.sender].userState != UserState.ACCEPTED)
            revert KuriCore__CallerNotAccepted();
        if (kuriData.state != KuriState.ACTIVE) revert KuriCore__NoActiveKuri();

        if (kuriData.nextIntervalDepositTime > block.timestamp)
            revert KuriCore__DepositIntervalNotReached();

        // check if the user has already paid
        if (hasPaid(msg.sender, passedIntervalsCounter()))
            revert KuriCore__UserAlreadyDeposited();

        // Calculate the amount each user needs to deposit
        uint64 amountToDeposit = kuriData.kuriAmount /
            kuriData.totalParticipantsCount;

        emit UserDeposited(
            msg.sender,
            userToData[msg.sender].userIndex,
            passedIntervalsCounter(),
            amountToDeposit,
            uint48(block.timestamp)
        );

        // Update the payment status for the user
        updateUserPaymentStatus();

        // Transfer tokens from the user to the contract
        IERC20(SUPPORTED_TOKEN).transferFrom(
            msg.sender,
            address(this),
            amountToDeposit
        );
    }

    /**
     * @notice Updates the payment status for a user
     * @dev Uses a bitmap for gas-efficient storage
     * @dev Each bit in the bitmap represents a user's payment status for a specific interval
     */
    function updateUserPaymentStatus() internal {
        uint256 userIndex = userToData[msg.sender].userIndex;
        uint16 currentIntervalIndex = passedIntervalsCounter();

        // Calculate the bucket and mask for the bitmap
        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);

        // Set the bit for the user in the current interval
        payments[currentIntervalIndex][bucket] |= mask;
    }

    /**
     * @notice Checks if a user has paid for a specific interval
     * @dev Uses the bitmap storage to efficiently check payment status
     * @param user Address of the user to check
     * @param intervalIndex Index of the interval to check
     * @return bool True if the user has paid for the interval, false otherwise
     */
    function hasPaid(
        address user,
        uint256 intervalIndex
    ) public view returns (bool) {
        uint256 index = userToData[user].userIndex;
        uint256 bucket = index >> 8;
        uint256 mask = 1 << (index & 0xff);
        return (payments[intervalIndex][bucket] & mask) != 0;
    }

    /**
     * @notice Calculates the number of deposit intervals that have passed
     * @dev Used to determine the current interval index
     * @return numTotalDepositIntervalsPassed The number of intervals that have passed
     */
    function passedIntervalsCounter()
        internal
        view
        returns (uint16 numTotalDepositIntervalsPassed)
    {
        // Calculate the total time passed since the Kuri started
        uint256 totalDepositIntervalsPassed = (block.timestamp -
            kuriData.startTime) + RAFFLE_DELAY_DURATION;

        // Convert to interval count by dividing by the total interval duration
        numTotalDepositIntervalsPassed = uint16(
            totalDepositIntervalsPassed /
                (kuriData.intervalDuration + RAFFLE_DELAY_DURATION)
        );
    }

    /**
     * @notice Grants the initializer role to an address
     * @dev Can only be called by an address with the DEFAULT_ADMIN_ROLE
     * @param _initialiser Address to grant the INITIALISOR_ROLE to
     */
    function setInitialisor(
        address _initialiser
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(INITIALISOR_ROLE, _initialiser);
    }

    /**
     * @notice Revokes the initializer role from an address
     * @dev Can only be called by an address with the DEFAULT_ADMIN_ROLE
     * @param _initialiser Address to revoke the INITIALISOR_ROLE from
     */
    function revokeInitialisor(
        address _initialiser
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(INITIALISOR_ROLE, _initialiser);
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
}

/**
 * To DOs:
 * nextTimeInterval & nextTimeReferral update logic to be added,my assumption is it would be better off along with the raffle
 *
 * Raffle:
 * takes place after the raffle-delay
 * all the users must have made their payment before we could spin up the raffle.
 * what if there are users yet to make their payments when the raffle-delay is over?
 * for now we must go with the assumption that all the users have made their payments
 */
