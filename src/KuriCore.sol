//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract KuriCore {

    //error messages
    error KuriCore__NotInLaunchState();
    error KuriCore__LaunchPeriodNotOver();
    error KuriCore__InsufficientActiveParticipantCount();

    uint256 public constant DAILY_INTERVAL = 1 days;
    uint256 public constant WEEKLY_INTERVAL = 7 days;
    uint256 public constant MONTHLY_INTERVAL = 30 days;
    uint256 public constant LAUNCH_PERIOD_DURATION = 3 days;

    enum KuriState { INLAUNCH,LAUNCHFAILED, ACTIVE, COMPLETED }
    enum UserState { ACCEPTED, REJECTED }
    enum IntervalType { DAY, WEEK, MONTH }


    struct Kuri {
        address creator;
        uint256 kuriAmount;
        uint256 totalParticipantsCount;
        uint256 acceptedParticipantsCount;
        uint256 launchPeriod;
        uint256 startTime;
        uint256 endTime;
        IntervalType intervalType;
        KuriState state;
    }


    Kuri public kuriData;

    mapping(address => UserState) public userStatus;

    constructor(
        address _creator,
        uint256 _kuriAmount,
        uint256 _participantCount,
        IntervalType _intervalType
    ) {
        kuriData.creator = _creator;
        kuriData.kuriAmount = _kuriAmount;
        kuriData.totalParticipantsCount = _participantCount;
        kuriData.launchPeriod = block.timestamp+LAUNCH_PERIOD_DURATION;
        kuriData.intervalType = _intervalType;
        kuriData.state = KuriState.INLAUNCH;
    }


    function initialiseKuri() external {
        if(kuriData.state!= KuriState.INLAUNCH) revert KuriCore__NotInLaunchState();
        if(kuriData.launchPeriod > block.timestamp) revert KuriCore__LaunchPeriodNotOver();
        if(kuriData.totalParticipantsCount!= kuriData.acceptedParticipantsCount) revert KuriCore__InsufficientActiveParticipantCount();
        

        require(block.timestamp >= kuriData.startTime, "Kuri launch period has not started yet");
        require(kuriData.participantCount > 0, "Participant count must be greater than 0");

        kuriData.state = KuriState.ACTIVE;
    }

}


/**
 * User-flow:
 * A function to initialise the kuri once the  required participant count is reached and kuri launch period is reached.
 * A function for the users to request to join the kuri.
 * A function to reject the requested user from the kuri since acceptence is by default true.
 * 
 */