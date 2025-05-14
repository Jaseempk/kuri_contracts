//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {VRFConsumerBaseV2Plus} from "chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {IVRFCoordinatorV2Plus} from "chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";

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
    error KuriCore__InvalidAddress();
    error KuriCore__AlreadyRejected();
    error KuriCore__NotInLaunchState();
    error KuriCore__AlreadySubscribed();
    error KuriCore__CallerNotAccepted();
    error KuriCore__UserYetToGetASlot();
    error KuriCore__KuriFilledAlready();
    error KuriCore__InvalidUserRequest();
    error KuriCore__UserAlreadyFlagged();
    error KuriCore__RaffleDelayNotOver();
    error KuriCore__UserAlreadyAccepted();
    error KuriCore__LaunchPeriodNotOver();
    error KuriCore__UserAlreadyRequested();
    error KuriCore__UserAlreadyDeposited();
    error KuriCore__InvalidIntervalIndex();
    error KuriCore__UserHasClaimedAlready();
    error KuriCore__UserYetToMakePayments();
    error KuriCore__CantFlagForFutureIndex();
    error KuriCore__MatketYetToBeSubscribed();
    error KuriCore__CantFlagUserAlreadyPaid();
    error KuriCore__AlreadyPastLaunchPeriod();
    error KuriCore__CantRejectWhenNotInLaunch();
    error KuriCore__CantAcceptWhenNotInLaunch();
    error KuriCore__DepositIntervalNotReached();
    error KuriCore__CantRequestWhenNotInLaunch();
    error KuriCore__CantWithdrawWhenCycleIsActive();
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

    /// @notice Role identifier for addresses authorized to vrf_subscription
    bytes32 public constant VRFSUBSCRIBER_ROLE =
        keccak256("VRFSUBSCRIBER_ROLE");

    /// @notice Address of the token used for deposits(USDC in our case)
    address public constant SUPPORTED_TOKEN =
        0xC129124eA2Fd4D63C1Fc64059456D8f231eBbed1;

    /// @notice Maximum number of consumers allowed per VRF subscription
    /// @dev Used to determine when to create a new subscription vs adding to existing one
    uint256 public constant MAX_CONSUMER_COUNT = 100;

    /// @notice Address of the Chainlink VRF Coordinator contract
    address public vrfCoordinator = 0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE;
    /// @notice Gas limit for Chainlink VRF callback
    uint32 public s_callbackGasLimit = 40000;
    /// @notice Number of confirmations required for Chainlink VRF requests
    uint16 public s_requestConfirmations = 3;
    /// @notice Number of random words to request from Chainlink VRF
    uint32 public s_numWords = 1;
    /// @notice Chainlink VRF key hash for randomness requests
    bytes32 public s_keyHash =
        0x9e1344a1247c8a1785d0a4681a27152bffdb43666ae5bf7d14d24a5efd44bf71;

    /// @notice Chainlink VRF subscription ID for randomness requests
    uint256 public s_subscriptionId;

    /// @notice Flag indicating if the contract is subscribed to Chainlink VRF service
    bool public isSubscribed;

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
     * @notice Enum representing the interval type for the Kuri
     * @dev WEEK: Weekly payment intervals
     * @dev MONTH: Monthly payment intervals
     */
    enum IntervalType {
        WEEK,
        MONTH
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
        REJECTED,
        FLAGGED,
        APPLIED
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

    ///@notice where the complete user indices are stored
    uint16[] public activeIndices;

    /**
     * @notice Emitted when a raffle winner is selected for a specific interval
     * @param intervalIndex The index of the interval for which the winner was selected
     * @param winnerIndex The position/index of the winning entry
     * @param winnerAddress The address of the winning participant
     * @param winnerTimestamp The timestamp when the winner was selected
     * @param requestId The Chainlink VRF request ID associated with winner selection
     */
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

    /**
     * @notice Emitted when a user claims their KURI tokens from a specific interval
     * @param user Address of the user claiming the tokens
     * @param timestamp Time when the claim was executed
     * @param kuriAmount Amount of KURI tokens claimed
     * @param intervalIndex Index of the interval from which tokens were claimed
     */
    event KuriSlotClaimed(
        address user,
        uint64 timestamp,
        uint64 kuriAmount,
        uint16 intervalIndex
    );

    /**
     * @notice Emitted when a new membership request is submitted
     * @param user Address of the user requesting membership
     * @param timestamp Block timestamp when request was made
     */
    event MembershipRequested(address user, uint256 timestamp);

    /**
     * @notice Emitted when a user is flagged for suspicious activity
     * @param user Address of the flagged user
     * @param intervalIndex Index of the interval when user was flagged
     */
    event UserFlagged(address user, uint16 intervalIndex);

    /**
     * @notice Emitted when a user is accepted into the system
     * @param user The address of the user that was accepted
     * @param caller The address of the account that accepted the user
     */
    event UserAccepted(
        address user,
        address caller,
        uint16 _totalActiveParticipantsCount
    );

    /**
     * @notice Emitted when a user is rejected from the system
     * @param user The address of the user that was rejected
     * @param caller The address of the account that rejected the user
     */
    event UserRejected(address user, address caller);

    event VRFIntegrationDone(
        address caller,
        uint256 subscriptionId,
        uint256 consumerCount,
        address contractAddress,
        uint256 timestamp
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
        address _kuriAdmin,
        address _vrfSubscriber,
        IntervalType _intervalType
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        kuriData.creator = _initialiser;
        kuriData.kuriAmount = _kuriAmount;
        kuriData.totalParticipantsCount = _participantCount;

        kuriData.launchPeriod = uint48(
            block.timestamp + LAUNCH_PERIOD_DURATION
        );
        kuriData.intervalType = _intervalType;
        kuriData.state = KuriState.INLAUNCH;

        _grantRole(DEFAULT_ADMIN_ROLE, _kuriAdmin);
        _grantRole(INITIALISOR_ROLE, _initialiser);
        _grantRole(VRFSUBSCRIBER_ROLE, _vrfSubscriber);
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
        if (kuriData.state != KuriState.INLAUNCH) {
            revert KuriCore__NotInLaunchState();
        }
        if (kuriData.launchPeriod > block.timestamp) {
            revert KuriCore__LaunchPeriodNotOver();
        }

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

        // Calculate the next raffle time
        kuriData.nexRaffleTime = uint48(
            kuriData.nextIntervalDepositTime + RAFFLE_DELAY_DURATION
        );

        // Calculate the end time based on total intervals
        // total time = interval duration * number of intervals + delay duration * number of intervals
        kuriData.endTime = uint48(
            block.timestamp +
                ((totalIntervals * kuriData.intervalDuration) +
                    (totalIntervals * RAFFLE_DELAY_DURATION))
        );

        emit KuriInitialised(kuriData);

        _updateAvailableIndices();

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

        if (userToData[msg.sender].userState == UserState.REJECTED) {
            revert KuriCore__AlreadyRejected();
        }

        if (userToData[msg.sender].userAddress == msg.sender) {
            revert KuriCore__UserAlreadyRequested();
        }

        if (kuriData.state != KuriState.INLAUNCH) {
            revert KuriCore__CantRequestWhenNotInLaunch();
        }

        if (kuriData.launchPeriod < block.timestamp) {
            revert KuriCore__AlreadyPastLaunchPeriod();
        }
        emit MembershipRequested(msg.sender, block.timestamp);
        userToData[msg.sender].userAddress = msg.sender;
        userToData[msg.sender].userState = UserState.APPLIED;
    }

    /**
     * @notice Accepts a user's membership request to join the Kuri platform
     * @dev Only callable by accounts with DEFAULT_ADMIN_ROLE
     * @param _user The address of the user whose membership request is being accepted
     */
    function acceptUserMembershipRequest(
        address _user
    ) public onlyRole(INITIALISOR_ROLE) {
        if (_user == address(0)) revert KuriCore__InvalidAddress();
        if (
            kuriData.totalParticipantsCount ==
            kuriData.totalActiveParticipantsCount
        ) {
            revert KuriCore__KuriFilledAlready();
        }

        if (
            userToData[_user].userAddress != _user ||
            userToData[_user].userState != UserState.APPLIED
        ) {
            revert KuriCore__InvalidUserRequest();
        }

        if (userToData[_user].userState == UserState.ACCEPTED) {
            revert KuriCore__UserAlreadyAccepted();
        }
        if (userToData[_user].userState == UserState.REJECTED) {
            revert KuriCore__AlreadyRejected();
        }
        if (kuriData.state != KuriState.INLAUNCH) {
            revert KuriCore__CantAcceptWhenNotInLaunch();
        }

        if (kuriData.launchPeriod < block.timestamp) {
            revert KuriCore__AlreadyPastLaunchPeriod();
        }
        emit UserAccepted(
            _user,
            msg.sender,
            kuriData.totalActiveParticipantsCount + 1
        );

        kuriData.totalActiveParticipantsCount++;

        userIdToAddress[kuriData.totalActiveParticipantsCount] = _user;

        // add the user to the accepted list
        userToData[_user] = UserData(
            UserState.ACCEPTED,
            kuriData.totalActiveParticipantsCount,
            _user
        );

        userToData[_user].userState = UserState.ACCEPTED;
    }

    /**
     * @notice Rejects a user's membership request to join the Kuri platform
     * @dev Only callable by accounts with DEFAULT_ADMIN_ROLE
     * @param _user The address of the user whose membership request is being rejected
     */
    function rejectUserMembershipRequest(
        address _user
    ) public onlyRole(INITIALISOR_ROLE) {
        if (kuriData.state != KuriState.INLAUNCH) {
            revert KuriCore__CantRejectWhenNotInLaunch();
        }
        if (_user == address(0)) revert KuriCore__InvalidAddress();
        if (userToData[_user].userState == UserState.ACCEPTED) {
            revert KuriCore__UserAlreadyAccepted();
        }
        if (userToData[_user].userState == UserState.REJECTED) {
            revert KuriCore__AlreadyRejected();
        }
        if (
            userToData[_user].userAddress != _user ||
            userToData[_user].userState != UserState.APPLIED
        ) {
            revert KuriCore__InvalidUserRequest();
        }

        emit UserRejected(_user, msg.sender);
        userToData[_user].userState = UserState.REJECTED;
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
        if (userToData[msg.sender].userState != UserState.ACCEPTED) {
            revert KuriCore__CallerNotAccepted();
        }
        if (kuriData.state != KuriState.ACTIVE) revert KuriCore__NoActiveKuri();

        if (kuriData.nextIntervalDepositTime > block.timestamp) {
            revert KuriCore__DepositIntervalNotReached();
        }

        // check if the user has already paid
        if (hasPaid(msg.sender, passedIntervalsCounter())) {
            revert KuriCore__UserAlreadyDeposited();
        }

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
        _updateUserPaymentStatus();

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
     * @return _requestId The ID of the Chainlink VRF request
     */
    function kuriNarukk()
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256 _requestId)
    {
        // Ensure the raffle delay period has passed
        if (kuriData.nexRaffleTime > block.timestamp) {
            revert KuriCore__RaffleDelayNotOver();
        }

        if (!isSubscribed) revert KuriCore__MatketYetToBeSubscribed();

        // Request random words from Chainlink VRF
        _requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: s_keyHash,
                subId: s_subscriptionId,
                requestConfirmations: s_requestConfirmations,
                callbackGasLimit: s_callbackGasLimit,
                numWords: s_numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );
    }

    /**
     * @notice Allows a winner to claim their Kuri amount
     * @dev Verifies the user has won and hasn't already claimed
     * @dev Transfers the full Kuri amount to the winner
     * @param _intervalIndex The index of the interval for which to claim
     */
    function claimKuriAmount(uint16 _intervalIndex) external {
        // Verify the user has won a Kuri slot
        if (!hasWon(msg.sender)) revert KuriCore__UserYetToGetASlot();

        // Verify the user hasn't already claimed
        if (hasClaimed(msg.sender)) revert KuriCore__UserHasClaimedAlready();

        // Verify the interval index is valid
        if (_intervalIndex > kuriData.totalParticipantsCount) {
            revert KuriCore__InvalidIntervalIndex();
        }

        // Verify the user has made their payment for this interval
        if (!hasPaid(msg.sender, _intervalIndex)) {
            revert KuriCore__UserYetToMakePayments();
        }

        if (
            kuriData.endTime <= block.timestamp &&
            _intervalIndex == kuriData.totalParticipantsCount
        ) {
            kuriData.state = KuriState.COMPLETED; //Marking kuri as completed if the cycle duration have elapsed
        }

        // Emit event for the claim
        emit KuriSlotClaimed(
            msg.sender,
            uint64(block.timestamp),
            kuriData.kuriAmount,
            _intervalIndex
        );

        // Update the user's claim status
        _updateUserKuriSlotClaimStatus();

        // Transfer the full Kuri amount to the winner
        IERC20(SUPPORTED_TOKEN).transfer(msg.sender, kuriData.kuriAmount);
    }

    /**
     * @notice Allows admin to withdraw tokens after cycle completion
     * @dev Only callable by admin role when cycle is not active
     */
    function withdraw() external onlyRole(INITIALISOR_ROLE) {
        if (kuriData.endTime > block.timestamp) {
            revert KuriCore__CantWithdrawWhenCycleIsActive();
        }

        if (kuriData.state != KuriState.COMPLETED) {
            revert KuriCore__CantWithdrawWhenCycleIsActive();
        }
        uint256 balance = IERC20(SUPPORTED_TOKEN).balanceOf(address(this));
        IERC20(SUPPORTED_TOKEN).transferFrom(
            address(this),
            msg.sender,
            balance
        );
    }

    /**
     * @notice Flags a user as defaulter and removes them from active indices
     * @dev Only callable by admin. Removes user from activeIndices array and marks them as flagged
     * @param _user Address of the user to be flagged
     * @param _intervalIndex The interval index to check payment status
     * @custom:throws KuriCore__CantFlagUserAlreadyPaid if user has already paid for the interval
     * @custom:throws KuriCore__UserAlreadyFlagged if user is already flagged
     * @custom:access Restricted to DEFAULT_ADMIN_ROLE
     */
    function flagUser(
        address _user,
        uint16 _intervalIndex
    ) external onlyRole(INITIALISOR_ROLE) {
        uint16 userIndex = userToData[_user].userIndex;
        if (hasPaid(_user, _intervalIndex)) {
            revert KuriCore__CantFlagUserAlreadyPaid();
        }
        if (userToData[_user].userState == UserState.FLAGGED) {
            revert KuriCore__UserAlreadyFlagged();
        }

        if (passedIntervalsCounter() < _intervalIndex) {
            revert KuriCore__CantFlagForFutureIndex();
        }

        emit UserFlagged(_user, _intervalIndex);

        for (uint16 i = 0; i < activeIndices.length; i++) {
            if (activeIndices[i] == userIndex) {
                activeIndices[i] = activeIndices[activeIndices.length - 1];
                userToData[_user].userState = UserState.FLAGGED;
                activeIndices.pop();
                break;
            }
        }
    }

    /**
     * @notice Creates a new VRF subscription or adds this contract as a consumer to an existing one
     * @dev Only callable by accounts with VRFSUBSCRIBER_ROLE
     * @param _subscriptionId The ID of the VRF subscription to use or add to
     * @return The subscription ID that was created or used
     * @custom:throws KuriCore__AlreadySubscribed if contract is already subscribed to VRF
     */
    function createSubscriptionOrAddConsumer(
        uint256 _subscriptionId
    ) external onlyRole(VRFSUBSCRIBER_ROLE) returns (uint256) {
        // Check if contract is already subscribed to VRF
        if (isSubscribed) revert KuriCore__AlreadySubscribed();

        // Get current subscription details from VRF coordinator
        (, , , , address[] memory consumers) = IVRFCoordinatorV2Plus(
            vrfCoordinator
        ).getSubscription(_subscriptionId);

        // Create new subscription if consumer limit reached
        if (consumers.length == MAX_CONSUMER_COUNT) {
            s_subscriptionId = IVRFCoordinatorV2Plus(vrfCoordinator)
                .createSubscription();
        } else {
            // Use existing subscription
            s_subscriptionId = _subscriptionId;
        }

        // Emit event for VRF integration
        emit VRFIntegrationDone(
            msg.sender,
            s_subscriptionId,
            consumers.length,
            address(this),
            block.timestamp
        );

        // Register this contract as a consumer with VRF coordinator
        IVRFCoordinatorV2Plus(vrfCoordinator).addConsumer(
            s_subscriptionId,
            address(this)
        );

        // Mark contract as subscribed
        isSubscribed = true;

        return s_subscriptionId;
    }

    /**
     * @notice Callback function called by Chainlink VRF with random values
     * @dev Overrides the function in VRFConsumerBaseV2Plus
     * @dev Selects a winner based on the random value and updates state
     * @param _requestId The ID of the request that was fulfilled
     * @param _randomWords Array of random values from Chainlink VRF
     */
    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] calldata _randomWords
    ) internal override {
        // Transform the result to a number between 1 and totalActiveParticipantsCount (inclusive)
        uint16 d20ValueIndex = uint16((_randomWords[0] % activeIndices.length));

        uint16 userIndex = activeIndices[d20ValueIndex];

        activeIndices[d20ValueIndex] = activeIndices[activeIndices.length - 1];

        uint16 intervalIndex = passedIntervalsCounter();

        // Get the user address from the selected index
        address idtoUser = userIdToAddress[userIndex];

        // User is out of the Kuri
        if (!hasPaid(idtoUser, intervalIndex)) return;

        // Update the next interval deposit time and raffle time
        kuriData.nextIntervalDepositTime = uint48(
            block.timestamp + kuriData.intervalDuration
        );
        kuriData.nexRaffleTime = uint48(
            kuriData.nextIntervalDepositTime + RAFFLE_DELAY_DURATION
        );

        // Record the winner for this interval
        intervalToWinnerIndex[intervalIndex] = userIndex;

        // Emit event with winner information
        emit RaffleWinnerSelected(
            intervalIndex,
            uint16(userIndex),
            userIdToAddress[userIndex],
            uint48(block.timestamp),
            _requestId
        );

        activeIndices.pop();

        // Update the winner's status in the bitmap
        _updateUserKuriSlotStatus(idtoUser);
    }

    /**
     * @notice Checks if a user has already claimed their Kuri amount
     * @dev Uses the bitmap storage to efficiently check claim status
     * @param _user Address of the user to check
     * @return bool True if the user has claimed, false otherwise
     */
    function hasClaimed(address _user) public view returns (bool) {
        // Get the user's index
        uint256 index = userToData[_user].userIndex;
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
     * @param _user Address of the user to check
     * @return bool True if the user has won, false otherwise
     */
    function hasWon(address _user) public view returns (bool) {
        // Get the user's index
        uint256 index = userToData[_user].userIndex;
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
     * @param _user Address of the user to check
     * @param _intervalIndex Index of the interval to check
     * @return bool True if the user has paid for the interval, false otherwise
     */
    function hasPaid(
        address _user,
        uint256 _intervalIndex
    ) public view returns (bool) {
        if (
            _intervalIndex == 0 ||
            _intervalIndex > kuriData.totalActiveParticipantsCount
        ) revert KuriCore__InvalidIntervalIndex();

        // Get the user's index
        uint256 index = userToData[_user].userIndex;
        if (index == 0) revert KuriCore__InvalidUser();

        // Calculate the bucket and mask
        uint256 bucket = index >> 8; // Divide by 256 to get the bucket
        uint256 mask = 1 << (index & 0xff); // Get the bit position within the bucket

        // Check if the bit is set in the payment bitmap
        return (payments[_intervalIndex][bucket] & mask) != 0;
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
    ) external onlyRole(INITIALISOR_ROLE) {
        revokeRole(INITIALISOR_ROLE, _initialiser);
    }

    /**
     * @notice Returns the total number of active index positions
     * @dev Returns the length of the activeIndices array
     * @return uint256 The number of active indices
     */
    function getActiveIndicesLength() external view returns (uint256) {
        return activeIndices.length;
    }

    /**
     * @notice Internal function to update available indices for participants
     * @dev Resets the activeIndices array by assigning sequential numbers from 1 to totalParticipantsCount
     * @dev Used to maintain a list of available participant indices
     * @dev The indices start from 1 (i + 1) rather than 0
     */
    function _updateAvailableIndices() internal {
        for (uint16 i = 0; i < kuriData.totalParticipantsCount; i++) {
            activeIndices.push(i + 1);
        }
    }

    /**
     * @notice Updates the claim status for a user who has claimed their Kuri amount
     * @dev Uses a bitmap for gas-efficient storage
     * @dev Each bit in the bitmap represents whether a user has claimed their Kuri amount
     */
    function _updateUserKuriSlotClaimStatus() internal {
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
    function _updateUserKuriSlotStatus(address user) internal {
        // Get the user's index
        uint256 userIndex = userToData[user].userIndex;

        // Calculate the bucket and mask for the bitmap
        uint256 bucket = userIndex >> 8; // Divide by 256 to get the bucket
        uint256 mask = 1 << (userIndex & 0xff); // Get the bit position within the bucket(& operation extracts the LS8B)

        // Set the bit for the user in the won bitmap
        wonKuriSlot[bucket] |= mask;
    }

    /**
     * @notice Updates the payment status for a user
     * @dev Uses a bitmap for gas-efficient storage
     * @dev Each bit in the bitmap represents a user's payment status for a specific interval
     */
    function _updateUserPaymentStatus() internal {
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
