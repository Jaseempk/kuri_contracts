//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {KuriCore} from "./KuriCore.sol";

contract KuriCoreFactory {
    //errors
    error KCF__InvalidInputs();

    event KuriMarketDeployed(
        address caller,
        address marketAddress,
        uint8 intervalType,
        uint256 timestamp
    );

    function initialiseKuriMarket(
        uint64 kuriAmount,
        uint16 kuriParticipantCount,
        uint8 intervalType
    ) external returns (address) {
        if (kuriAmount == 0 || kuriParticipantCount == 0)
            revert KCF__InvalidInputs();
        KuriCore.IntervalType _intervalType = KuriCore.IntervalType(
            intervalType
        );

        KuriCore kuriCore = new KuriCore(
            kuriAmount,
            kuriParticipantCount,
            msg.sender,
            _intervalType
        );
        emit KuriMarketDeployed(
            msg.sender,
            address(kuriCore),
            intervalType,
            block.timestamp
        );

        return address(kuriCore);
    }
}
