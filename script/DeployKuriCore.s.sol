// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {KuriCore} from "../src/KuriCore.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";
import {CodeConstants} from "./HelperConfig.s.sol";

/**
 * @title DeployKuriCore
 * @notice Deploys the KuriCore contract with proper VRF configuration
 */
contract DeployKuriCore is CodeConstants, Script {
    function run() external returns (KuriCore, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        // Handle VRF subscription setup
        if (config.subscriptionId == 0) {
            console.log(
                "No subscription ID found. Creating a new subscription..."
            );
            CreateSubscription createSubscription = new CreateSubscription();
            (
                config.subscriptionId,
                config.vrfCoordinatorV2_5
            ) = createSubscription.createSubscription(
                config.vrfCoordinatorV2_5,
                config.account
            );

            // Fund the subscription
            console.log("Funding the subscription...");
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(
                config.vrfCoordinatorV2_5,
                config.subscriptionId,
                config.link,
                config.account
            );
        }

        // Deploy KuriCore
        console.log("Deploying KuriCore...");

        vm.startBroadcast(config.account);
        KuriCore kuriCore = new KuriCore(
            config.kuriAmount,
            config.participantCount,
            config.initialiser,
            config.initialiser,
            config.initialiser,
            config.intervalType
        );

        vm.stopBroadcast();

        // Add KuriCore as a consumer to the VRF subscription
        console.log("Adding KuriCore as a consumer to the VRF subscription...");
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(
            address(kuriCore),
            config.vrfCoordinatorV2_5,
            config.subscriptionId,
            config.account
        );

        console.log("KuriCore deployed at: ", address(kuriCore));
        console.log("VRF Subscription ID: ", config.subscriptionId);

        return (kuriCore, helperConfig);
    }
}
