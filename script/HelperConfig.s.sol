// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {KuriCore} from "../src/KuriCore.sol";

/**
 * @title CodeConstants
 * @notice Contains constants used across the codebase
 */
contract CodeConstants {
    uint256 public constant LOCAL_CHAIN_ID = 31337;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant BASE_SEPOLIA_CHAIN_ID = 84532;

    // VRF Mock constants
    uint96 public constant MOCK_BASE_FEE = 0.25 ether; // 0.25 LINK
    uint96 public constant MOCK_GAS_PRICE_LINK = 1e9; // 1 gwei LINK
    uint256 public constant MOCK_WEI_PER_UINT_LINK = 1e18;
}

/**
 * @title HelperConfig
 * @notice Configuration helper for different networks
 */
contract HelperConfig is CodeConstants, Script {
    /**
     * uint64 kuriAmount;
     *     uint16 participantCount;
     *     address initialiser;
     *     IntervalType intervalType;
     */
    struct NetworkConfig {
        uint256 subscriptionId;
        bytes32 gasLane; // keyHash
        uint64 automationUpdateInterval;
        uint32 callbackGasLimit;
        address vrfCoordinatorV2_5;
        address link;
        address account;
        uint64 kuriAmount;
        uint16 participantCount;
        address initialiser;
        KuriCore.IntervalType intervalType;
    }

    NetworkConfig public networkConfig;

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            networkConfig = getSepoliaEthConfig();
        } else if (block.chainid == BASE_SEPOLIA_CHAIN_ID) {
            networkConfig = getBaseSepoliaConfig();
        } else {
            networkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory sepoliaNetworkConfig) {
        sepoliaNetworkConfig = NetworkConfig({
            subscriptionId: 0, // Update this with your subscription ID!
            gasLane: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae, // 30 gwei
            automationUpdateInterval: 30, // 30 seconds
            callbackGasLimit: 500000, // 500,000 gas
            vrfCoordinatorV2_5: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B, // Sepolia VRF Coordinator
            link: 0x779877A7B0D9E8603169DdbD7836e478b4624789, // Sepolia LINK token
            account: 0xF941d25cEB9A56f36B2E246eC13C125305544283,
            kuriAmount: 1000e6,
            participantCount: 10,
            initialiser: 0x66aAf3098E1eB1F24348e84F509d8bcfD92D0620,
            intervalType: KuriCore.IntervalType.WEEK
        });
    }

    function getBaseSepoliaConfig() public pure returns (NetworkConfig memory baseSepoliaNetworkConfig) {
        baseSepoliaNetworkConfig = NetworkConfig({
            subscriptionId: 111354311979648395489096536317869612424008220436069067319236829392818402563961, // Update this with your subscription ID!
            gasLane: 0x9e1344a1247c8a1785d0a4681a27152bffdb43666ae5bf7d14d24a5efd44bf71, // Base Sepolia gas lane
            automationUpdateInterval: 30, // 30 seconds
            callbackGasLimit: 2500000, // 500,000 gas
            vrfCoordinatorV2_5: 0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE, // Base Sepolia VRF Coordinator
            link: 0xE4aB69C077896252FAFBD49EFD26B5D171A32410, // Base Sepolia LINK token
            account: 0xF941d25cEB9A56f36B2E246eC13C125305544283,
            kuriAmount: 1000e6,
            participantCount: 10,
            initialiser: 0x66aAf3098E1eB1F24348e84F509d8bcfD92D0620,
            intervalType: KuriCore.IntervalType.WEEK
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        // Check if we already have an anvil config
        if (networkConfig.vrfCoordinatorV2_5 != address(0)) {
            return networkConfig;
        }

        uint96 baseFee = MOCK_BASE_FEE;
        uint96 gasPriceLink = MOCK_GAS_PRICE_LINK;
        uint256 weiPerUnitLink = MOCK_WEI_PER_UINT_LINK;

        vm.startBroadcast();
        VRFCoordinatorV2_5Mock vrfCoordinatorV2_5Mock =
            new VRFCoordinatorV2_5Mock(baseFee, gasPriceLink, int256(weiPerUnitLink));
        LinkToken link = new LinkToken();
        uint256 subscriptionId = vrfCoordinatorV2_5Mock.createSubscription();
        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            subscriptionId: subscriptionId, // This will be set during deployment
            gasLane: 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c, // doesn't matter for mock
            automationUpdateInterval: 30, // 30 seconds
            callbackGasLimit: 5000000, // 500,000 gas
            vrfCoordinatorV2_5: address(vrfCoordinatorV2_5Mock),
            link: address(link),
            account: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38,
            kuriAmount: 1000e6,
            participantCount: 10,
            initialiser: msg.sender,
            intervalType: KuriCore.IntervalType.WEEK
        });
    }

    function getConfig() public view returns (NetworkConfig memory) {
        return networkConfig;
    }

    function getConfigByChainId(uint256 chainId) public view returns (NetworkConfig memory) {
        if (chainId == SEPOLIA_CHAIN_ID) {
            return getSepoliaEthConfig();
        } else if (chainId == BASE_SEPOLIA_CHAIN_ID) {
            return getBaseSepoliaConfig();
        } else {
            return networkConfig; // Local config
        }
    }
}
