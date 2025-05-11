// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {KuriCore} from "./KuriCore.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title KuriCoreFactory
/// @notice Deploys new instances of KuriCore contracts with specified parameters.
/// @dev Minimal factory contract to instantiate and emit metadata for new KuriCore markets.
contract KuriCoreFactory is AccessControl {
    /// @notice Reverts when provided input values are invalid (e.g., zero values).
    error KCF__InvalidInputs();
    error KCF__InvalidAdminAddy();

    address public s_kuriAdmin = 0x66aAf3098E1eB1F24348e84F509d8bcfD92D0620;

    /**
     * @notice Emitted when a new KuriCore market is successfully deployed.
     * @param caller Address of the user who initialized the market.
     * @param marketAddress Address of the deployed KuriCore contract.
     * @param intervalType Type of interval used in the KuriCore market (mapped from uint8 to enum).
     * @param timestamp Block timestamp when the market was deployed.
     */
    event KuriMarketDeployed(
        address indexed caller,
        address indexed marketAddress,
        uint8 intervalType,
        uint256 timestamp
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Deploys a new KuriCore contract with the given parameters.
     * @dev Validates inputs before creating the contract. Converts intervalType from uint8 to enum.
     * @param kuriAmount Total Kuri amount to be distributed in the market.
     * @param kuriParticipantCount Total number of participants expected in the market.
     * @param intervalType Numeric representation of the interval type (mapped to enum).
     * @return Address of the newly deployed KuriCore contract.
     */
    function initialiseKuriMarket(
        uint64 kuriAmount,
        uint16 kuriParticipantCount,
        uint8 intervalType
    ) external returns (address) {
        // Revert if kuriAmount or participant count is zero
        if (kuriAmount == 0 || kuriParticipantCount == 0) {
            revert KCF__InvalidInputs();
        }

        // Cast the uint8 intervalType into the KuriCore enum
        KuriCore.IntervalType _intervalType = KuriCore.IntervalType(
            intervalType
        );

        // Deploy a new instance of KuriCore using the provided parameters
        KuriCore kuriCore = new KuriCore(
            kuriAmount,
            kuriParticipantCount,
            msg.sender,
            s_kuriAdmin,
            _intervalType
        );

        // Emit event with deployment metadata
        emit KuriMarketDeployed(
            msg.sender,
            address(kuriCore),
            intervalType,
            block.timestamp
        );

        // Return address of the deployed contract
        return address(kuriCore);
    }

    function setKuriAdmin(
        address _newAdmin
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newAdmin == address(0)) revert KCF__InvalidAdminAddy();
        s_kuriAdmin = _newAdmin;
    }
}
