//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {KuriCoreFactory} from "../src/KuriCoreFactory.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployKuriCoreFactory is Script {
    function run() external returns (KuriCoreFactory, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        vm.startBroadcast();
        KuriCoreFactory kuriCoreFactory = new KuriCoreFactory();
        vm.stopBroadcast();

        return (kuriCoreFactory, helperConfig);
    }
}
