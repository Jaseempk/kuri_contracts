//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract KuriCore {
    //error messages
    error KuriCore__AlreadyRejected();
    error KuriCore__NotInLaunchState();
    error KuriCore__LaunchPeriodNotOver();
    error KuriCore__InsufficientActiveParticipantCount();

    uint256 public constant WEEKLY_INTERVAL = 7 days;
    uint256 public constant MONTHLY_INTERVAL = 30 days;
    uint256 public constant LAUNCH_PERIOD_DURATION = 3 days;
    uint256 public constant RAFFLE_DELAY_DURATION = 3 days;

    enum KuriState {
        INLAUNCH,
        LAUNCHFAILED,
        ACTIVE,
        COMPLETED
    }
    enum UserState {
        ACCEPTED,
        REJECTED
    }
    enum IntervalType {
        WEEK,
        MONTH
    }

    struct Kuri {
        address creator;
        uint256 kuriAmount;
        uint256 totalParticipantsCount;
        uint256 totalActiveParticipantsCount;
        uint256 nexRaffleTime;
        uint256 nextIntervalDepositTime;
        uint256 launchPeriod;
        uint256 startTime;
        uint256 endTime;
        uint256 intervalDuration;
        IntervalType intervalType;
        KuriState state;
    }

    struct UserData {
        UserState userState;
        uint256 userIndex;
    }

    Kuri public kuriData;

    mapping(address => UserState) public userStatus;
    mapping(address => UserData) public userToData;

    event KuriInitialised(Kuri _kuriData);

    event KuriInitFailed(
        address creator,
        uint256 kuriAmount,
        uint256 totalParticipantsCount,
        KuriState state
    );

    constructor(
        address _creator,
        uint256 _kuriAmount,
        uint256 _participantCount,
        IntervalType _intervalType
    ) {
        kuriData.creator = _creator;
        kuriData.kuriAmount = _kuriAmount;
        kuriData.totalParticipantsCount = _participantCount;
        kuriData.launchPeriod = block.timestamp + LAUNCH_PERIOD_DURATION;
        kuriData.intervalType = _intervalType;
        kuriData.state = KuriState.INLAUNCH;
    }

    function initialiseKuri() external returns (bool) {
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

        kuriData.startTime = block.timestamp;
        kuriData.intervalDuration = kuriData.intervalType == IntervalType.WEEK
            ? WEEKLY_INTERVAL
            : MONTHLY_INTERVAL;

        kuriData.nextIntervalDepositTime =
            block.timestamp +
            kuriData.intervalDuration;
        // total time = interval duration * number of intervals + delay duration * number of intervals
        kuriData.endTime =
            block.timestamp +
            ((totalIntervals * kuriData.intervalDuration) +
                (totalIntervals * RAFFLE_DELAY_DURATION));
        kuriData.nexRaffleTime =
            kuriData.nextIntervalDepositTime +
            RAFFLE_DELAY_DURATION;

        emit KuriInitialised(kuriData);

        kuriData.state = KuriState.ACTIVE;

        return true;
    }

    function requestMembership() external {
        // check if the user is already a member
        if (userStatus[msg.sender] == UserState.ACCEPTED) return;
        // check if the user is already rejected
        if (userStatus[msg.sender] == UserState.REJECTED)
            revert KuriCore__AlreadyRejected();

        // add the user to the accepted list
        userStatus[msg.sender] = UserState.ACCEPTED;
        kuriData.totalActiveParticipantsCount++;
    }
}

/**
 * User-flow:
 * A function to initialise the kuri once the  required participant count is reached and kuri launch period is reached.
 * A function for the users to request to join the kuri.
 * A function to reject the requested user from the kuri since acceptence is by default true.
 *
 */
