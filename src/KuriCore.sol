//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {VRFConsumerBaseV2Plus} from "chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title KuriCore
 * @author anon
 * @notice Implementation of a Rotating Savings and Credit Association (ROSCA) system
 * @dev This contract manages a community savings group where members contribute funds
 * periodically and take turns receiving the pool. It includes membership management,
 * payment tracking, and role-based access control.
 */
contract KuriCore is AccessControl, VRFConsumerBaseV2Plus {
    //error messages
    error KuriCore__InvalidUser();
    error KuriCore__NoActiveKuri();
    error KuriCore__AlreadyRejected();
    error KuriCore__NotInLaunchState();
    error KuriCore__CallerNotAccepted();
    error KuriCore__UserAlreadyExists();
    error KuriCore__UserYetToGetASlot();
    error KuriCore__KuriFilledAlready();
    error KuriCore__RaffleDelayNotOver();
    error KuriCore__LaunchPeriodNotOver();
    error KuriCore__UserAlreadyDeposited();
    error KuriCore__InvalidIntervalIndex();
    error KuriCore__UserHasClaimedAlready();
    error KuriCore__UserYetToMakePayments();
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

    /// @notice Chainlink VRF subscription ID for randomness requests
    uint256 public s_subscriptionId =
        111354311979648395489096536317869612424008220436069067319236829392818402563961;
    /// @notice Chainlink VRF key hash for randomness requests
    bytes32 public s_keyHash =
        0x9e1344a1247c8a1785d0a4681a27152bffdb43666ae5bf7d14d24a5efd44bf71;
    /// @notice Address of the Chainlink VRF Coordinator contract
    address public vrfCoordinator = 0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE;
    /// @notice Gas limit for Chainlink VRF callback
    uint32 public callbackGasLimit = 40000;
    /// @notice Number of confirmations required for Chainlink VRF requests
    uint16 public requestConfirmations = 3;
    /// @notice Number of random words to request from Chainlink VRF
    uint32 public numWords = 1;

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
        address userAddress; // Address of the user
    }

    /// @notice Main Kuri data structure
    Kuri public kuriData;

    /**
     * @notice Mapping to track payments for each interval
     * @dev Uses a bitmap for gas-efficient storage: intervalIndex => bucket => bitmap
     * where each bit in the bitmap represents whether a user has paid
     */
    mapping(uint256 => mapping(uint256 => uint256)) public payments; // month => bitmap

    /// @notice Bitmap to track which users have won a Kuri slot
    /// @dev Uses a bitmap for gas-efficient storage: bucket => bitmap
    mapping(uint256 => uint256) public wonKuriSlot;

    /// @notice Bitmap to track which users have claimed their Kuri amount
    /// @dev Uses a bitmap for gas-efficient storage: bucket => bitmap
    mapping(uint256 => uint256) public claimedKuriSlot;

    /// @notice Mapping to store user data by address
    mapping(address => UserData) public userToData;

    /// @notice Mapping to store user addresses by index
    mapping(uint16 => address) public userIdToAddress;

    /// @notice Mapping to store raflfle winners by interval index
    mapping(uint16 => uint16) public intervalToWinnerIndex;

    event RaffleWinnerSelected(
        uint16 intervalIndex,
        uint16 winnerIndex,
        address winnerAddress,
        uint48 winnerTimestamp,
        uint256 requestId
    );

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

    event KuriSlotClaimed(
        address user,
        uint64 timestamp,
        uint64 kuriAmount,
        uint16 intervalIndex
    );

    /**
     * @notice Creates a new Kuri instance
     * @dev Sets initial state to INLAUNCH and grants roles
     * @param _kuriAmount Total amount to be collected in the Kuri
     * @param _participantCount Required number of participants
     * @param _initialiser Address authorized to initialize the Kuri
     * @param _intervalType Type of interval (weekly/monthly)
     */
    constructor(
        uint64 _kuriAmount,
        uint16 _participantCount,
        address _initialiser,
        IntervalType _intervalType
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        kuriData.creator = msg.sender;
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
        if (
            userIdToAddress[kuriData.totalActiveParticipantsCount] == msg.sender
        ) revert KuriCore__UserAlreadyExists();
        if (kuriData.state != KuriState.INLAUNCH)
            revert KuriCore__CantRequestWhenNotInLaunch();

        if (kuriData.launchPeriod < block.timestamp)
            revert KuriCore__AlreadyPastLaunchPeriod();
        if (
            kuriData.totalParticipantsCount ==
            kuriData.totalActiveParticipantsCount
        ) revert KuriCore__KuriFilledAlready();

        kuriData.totalActiveParticipantsCount++;

        userIdToAddress[kuriData.totalActiveParticipantsCount] = msg.sender;

        // add the user to the accepted list
        userToData[msg.sender] = UserData(
            UserState.ACCEPTED,
            kuriData.totalActiveParticipantsCount,
            msg.sender
        );
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
     * @notice Initiates a raffle to select a winner for the current interval
     * @dev Can only be called by an address with the DEFAULT_ADMIN_ROLE
     * @dev Uses Chainlink VRF to get a random winner
     * @dev Can only be called after the raffle delay period has passed
     * @return requestId The ID of the Chainlink VRF request
     */
    function kuriNarukk()
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256 requestId)
    {
        // Ensure the raffle delay period has passed
        if (kuriData.nexRaffleTime > block.timestamp)
            revert KuriCore__RaffleDelayNotOver();

        // Request random words from Chainlink VRF
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );
    }

    /**
     * @notice Callback function called by Chainlink VRF with random values
     * @dev Overrides the function in VRFConsumerBaseV2Plus
     * @dev Selects a winner based on the random value and updates state
     * @param requestId The ID of the request that was fulfilled
     * @param randomWords Array of random values from Chainlink VRF
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) internal override {
        // Transform the result to a number between 1 and totalActiveParticipantsCount (inclusive)
        uint16 d20Value = uint16(
            (randomWords[0] % kuriData.totalActiveParticipantsCount) + 1
        );

        // Get the user address from the selected index
        address idtoUser = userIdToAddress[d20Value];

        // Check if the user has already won in a previous interval
        if (!hasWon(idtoUser)) {
            // Update the next interval deposit time and raffle time
            kuriData.nextIntervalDepositTime = uint48(
                block.timestamp + kuriData.intervalDuration
            );
            kuriData.nexRaffleTime = uint48(
                kuriData.nextIntervalDepositTime + RAFFLE_DELAY_DURATION
            );

            // Get the current interval index
            uint16 intervalIndex = passedIntervalsCounter();

            // Emit event with winner information
            emit RaffleWinnerSelected(
                intervalIndex,
                uint16(d20Value),
                userIdToAddress[d20Value],
                uint48(block.timestamp),
                requestId
            );

            // Update the winner's status in the bitmap
            updateUserKuriSlotStatus(idtoUser);

            // Record the winner for this interval
            intervalToWinnerIndex[intervalIndex] = d20Value;
        } else {
            // If the selected user has already won, request a new random number
            kuriNarukk();
        }
    }

    /**
     * @notice Allows a winner to claim their Kuri amount
     * @dev Verifies the user has won and hasn't already claimed
     * @dev Transfers the full Kuri amount to the winner
     * @param intervalIndex The index of the interval for which to claim
     */
    function claimKuriAmount(uint16 intervalIndex) public {
        // Verify the user has won a Kuri slot
        if (!hasWon(msg.sender)) revert KuriCore__UserYetToGetASlot();

        // Verify the user hasn't already claimed
        if (hasClaimed(msg.sender)) revert KuriCore__UserHasClaimedAlready();

        // Verify the interval index is valid
        if (intervalIndex > kuriData.totalParticipantsCount)
            revert KuriCore__InvalidIntervalIndex();

        // Verify the user has made their payment for this interval
        if (!hasPaid(msg.sender, intervalIndex))
            revert KuriCore__UserYetToMakePayments();

        // Emit event for the claim
        emit KuriSlotClaimed(
            msg.sender,
            uint64(block.timestamp),
            kuriData.kuriAmount,
            intervalIndex
        );

        // Update the user's claim status
        updateUserKuriSlotClaimStatus();

        // Transfer the full Kuri amount to the winner
        IERC20(SUPPORTED_TOKEN).transfer(msg.sender, kuriData.kuriAmount);
    }

    /**
     * @notice Updates the claim status for a user who has claimed their Kuri amount
     * @dev Uses a bitmap for gas-efficient storage
     * @dev Each bit in the bitmap represents whether a user has claimed their Kuri amount
     */
    function updateUserKuriSlotClaimStatus() internal {
        // Get the user's index
        uint256 userIndex = userToData[msg.sender].userIndex;

        // Calculate the bucket and mask for the bitmap
        uint256 bucket = userIndex >> 8; // Divide by 256 to get the bucket
        uint256 mask = 1 << (userIndex & 0xff); // Get the bit position within the bucket

        // Set the bit for the user in the claimed bitmap
        claimedKuriSlot[bucket] |= mask;
    }

    /**
     * @notice Updates the winner status for a user who has won a Kuri slot
     * @dev Uses a bitmap for gas-efficient storage
     * @dev Each bit in the bitmap represents whether a user has won a Kuri slot
     * @param user Address of the user who won
     */
    function updateUserKuriSlotStatus(address user) internal {
        // Get the user's index
        uint256 userIndex = userToData[user].userIndex;

        // Calculate the bucket and mask for the bitmap
        uint256 bucket = userIndex >> 8; // Divide by 256 to get the bucket
        uint256 mask = 1 << (userIndex & 0xff); // Get the bit position within the bucket

        // Set the bit for the user in the won bitmap
        wonKuriSlot[bucket] |= mask;
    }

    /**
     * @notice Updates the payment status for a user
     * @dev Uses a bitmap for gas-efficient storage
     * @dev Each bit in the bitmap represents a user's payment status for a specific interval
     */
    function updateUserPaymentStatus() internal {
        // Get the user's index
        uint256 userIndex = userToData[msg.sender].userIndex;

        // Get the current interval index
        uint16 currentIntervalIndex = passedIntervalsCounter();

        // Calculate the bucket and mask for the bitmap
        uint256 bucket = userIndex >> 8; // Divide by 256 to get the bucket
        uint256 mask = 1 << (userIndex & 0xff); // Get the bit position within the bucket

        // Set the bit for the user in the payment bitmap
        payments[currentIntervalIndex][bucket] |= mask;
    }

    /**
     * @notice Checks if a user has already claimed their Kuri amount
     * @dev Uses the bitmap storage to efficiently check claim status
     * @param user Address of the user to check
     * @return bool True if the user has claimed, false otherwise
     */
    function hasClaimed(address user) public view returns (bool) {
        // Get the user's index
        uint256 index = userToData[user].userIndex;
        if (index == 0) revert KuriCore__InvalidUser();

        // Calculate the bucket and mask
        uint256 bucket = index >> 8; // Divide by 256 to get the bucket
        uint256 mask = 1 << (index & 0xff); // Get the bit position within the bucket

        // Check if the bit is set in the claimed bitmap
        return (claimedKuriSlot[bucket] & mask) != 0;
    }

    /**
     * @notice Checks if a user has won a Kuri slot
     * @dev Uses the bitmap storage to efficiently check winner status
     * @param user Address of the user to check
     * @return bool True if the user has won, false otherwise
     */
    function hasWon(address user) public view returns (bool) {
        // Get the user's index
        uint256 index = userToData[user].userIndex;
        if (index == 0) revert KuriCore__InvalidUser();

        // Calculate the bucket and mask
        uint256 bucket = index >> 8; // Divide by 256 to get the bucket
        uint256 mask = 1 << (index & 0xff); // Get the bit position within the bucket

        // Check if the bit is set in the won bitmap
        return (wonKuriSlot[bucket] & mask) != 0;
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
        // Get the user's index
        uint256 index = userToData[user].userIndex;
        if (index == 0) revert KuriCore__InvalidUser();

        // Calculate the bucket and mask
        uint256 bucket = index >> 8; // Divide by 256 to get the bucket
        uint256 mask = 1 << (index & 0xff); // Get the bit position within the bucket

        // Check if the bit is set in the payment bitmap
        return (payments[intervalIndex][bucket] & mask) != 0;
    }

    /**
     * @notice Calculates the number of deposit intervals that have passed
     * @dev Used to determine the current interval index
     * @return numTotalDepositIntervalsPassed The number of intervals that have passed
     */
    function passedIntervalsCounter()
        public
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
