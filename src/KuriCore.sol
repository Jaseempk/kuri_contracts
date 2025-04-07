//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

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

    uint256 public constant WEEKLY_INTERVAL = 7 days;
    uint256 public constant MONTHLY_INTERVAL = 30 days;
    uint256 public constant LAUNCH_PERIOD_DURATION = 3 days;
    uint256 public constant RAFFLE_DELAY_DURATION = 3 days;
    bytes32 public constant INITIALISOR_ROLE = keccak256("INITIALISOR_ROLE");
    address public constant SUPPORTED_TOKEN =
        0xC129124eA2Fd4D63C1Fc64059456D8f231eBbed1;

    enum KuriState {
        INLAUNCH,
        LAUNCHFAILED,
        ACTIVE,
        COMPLETED
    }
    enum UserState {
        NONE,
        ACCEPTED,
        REJECTED
    }
    enum IntervalType {
        WEEK,
        MONTH
    }

    struct Kuri {
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
    }

    struct UserData {
        UserState userState;
        uint16 userIndex;
    }

    mapping(address => UserData) public userToData;
    Kuri public kuriData;

    mapping(address => UserState) public userStatus;
    mapping(uint256 => mapping(uint256 => uint256)) public payments; // month => bitmap

    event KuriInitialised(Kuri _kuriData);

    event KuriInitFailed(
        address creator,
        uint64 kuriAmount,
        uint16 totalParticipantsCount,
        KuriState state
    );

    event UserDeposited(
        address user,
        uint256 userIndex,
        uint256 intervalIndex,
        uint64 amountDeposited,
        uint48 depositTimestamp
    );

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

    function initialiseKuri()
        external
        onlyRole(INITIALISOR_ROLE)
        returns (bool)
    {
        if (kuriData.state != KuriState.INLAUNCH)
            revert KuriCore__NotInLaunchState();
        if (kuriData.launchPeriod > block.timestamp)
            revert KuriCore__LaunchPeriodNotOver();
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
        uint256 totalIntervals = kuriData.totalParticipantsCount;

        kuriData.startTime = uint48(block.timestamp);
        kuriData.intervalDuration = kuriData.intervalType == IntervalType.WEEK
            ? uint24(WEEKLY_INTERVAL)
            : uint24(MONTHLY_INTERVAL);

        kuriData.nextIntervalDepositTime = uint48(
            block.timestamp + kuriData.intervalDuration
        );
        // total time = interval duration * number of intervals + delay duration * number of intervals
        kuriData.endTime = uint48(
            block.timestamp +
                ((totalIntervals * kuriData.intervalDuration) +
                    (totalIntervals * RAFFLE_DELAY_DURATION))
        );
        kuriData.nexRaffleTime = uint48(
            kuriData.nextIntervalDepositTime + RAFFLE_DELAY_DURATION
        );

        emit KuriInitialised(kuriData);

        kuriData.state = KuriState.ACTIVE;

        return true;
    }

    function requestMembership() external {
        // check if the user is already a member
        if (userToData[msg.sender].userState == UserState.ACCEPTED) return;
        if (kuriData.state != KuriState.INLAUNCH)
            revert KuriCore__CantRequestWhenNotInLaunch();

        if (kuriData.launchPeriod < block.timestamp)
            revert KuriCore__AlreadyPastLaunchPeriod();

        // check if the user is already rejected
        if (userStatus[msg.sender] == UserState.REJECTED)
            revert KuriCore__AlreadyRejected();

        // add the user to the accepted list
        userToData[msg.sender] = UserData(
            UserState.ACCEPTED,
            kuriData.totalActiveParticipantsCount
        );
        kuriData.totalActiveParticipantsCount++;
    }

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

        if (kuriData.nextIntervalDepositTime <= block.timestamp) {
            kuriData.nextIntervalDepositTime = uint48(
                block.timestamp + kuriData.intervalDuration
            );
            kuriData.nexRaffleTime = uint48(
                kuriData.nextIntervalDepositTime + RAFFLE_DELAY_DURATION
            );
        }

        uint64 amountToDeposit = kuriData.kuriAmount /
            kuriData.totalParticipantsCount;

        emit UserDeposited(
            msg.sender,
            userToData[msg.sender].userIndex,
            passedIntervalsCounter(),
            amountToDeposit,
            uint48(block.timestamp)
        );

        updateUserPaymentStatus();

        IERC20(SUPPORTED_TOKEN).transferFrom(
            msg.sender,
            address(this),
            amountToDeposit
        );
    }

    function updateUserPaymentStatus() internal {
        uint256 userIndex = userToData[msg.sender].userIndex;
        uint16 currentIntervalIndex = passedIntervalsCounter();

        uint256 bucket = userIndex >> 8;
        uint256 mask = 1 << (userIndex & 0xff);

        payments[currentIntervalIndex][bucket] |= mask;
    }

    function hasPaid(
        address user,
        uint256 intervalIndex
    ) public view returns (bool) {
        uint256 index = userToData[user].userIndex;
        uint256 bucket = index >> 8;
        uint256 mask = 1 << (index & 0xff);
        return (payments[intervalIndex][bucket] & mask) != 0;
    }

    function passedIntervalsCounter()
        internal
        view
        returns (uint16 numTotalDepositIntervalsPassed)
    {
        uint256 totalDepositIntervalsPassed = (block.timestamp -
            kuriData.startTime) + RAFFLE_DELAY_DURATION;
        numTotalDepositIntervalsPassed = uint16(
            totalDepositIntervalsPassed /
                (kuriData.intervalDuration + RAFFLE_DELAY_DURATION)
        );
    }

    function setInitialisor(
        address _initialiser
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(INITIALISOR_ROLE, _initialiser);
    }

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
