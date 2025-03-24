// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Like} from "../test/mocks/ERC20Like.sol";
import {Structs} from "../src/Structs.sol";

contract HelperConfig is Script {
    // OCR ratios are as follows
    // WETH = 170% => LT = (1e18 * 100 )/ 170 == 588235294117647058.8
    // LINK = 160% => LT = (1e18 * 100 )/ 160 == 625000000000000000
    // USDT = 120% => LT = (1e18 * 100 )/ 120 == 833333333333333333.3
    // DAI = 110% => LT = (1e18 * 100 )/ 110 == 909090909090909090.9
    uint256 public constant WETH_LIQ_THRESHOLD = 588235294117647058; // 58.82%%
    uint256 public constant LINK_LIQ_THRESHOLD = 625000000000000000; // 62.5%
    uint256 public constant USDT_LIQ_THRESHOLD = 833333333333333333; // 83.33%
    uint256 public constant DAI_LIQ_THRESHOLD = 909090909090909090; // 90.91%
    uint256 private constant SEPOLIA_CHAIN_ID = 11_155_111;
    uint256 private constant LOCAL_ANVIL_CHAIN_ID = 31337;

    // Array of deployment configs
    Structs.DeploymentConfig[] public deploymentConfigs;

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            deploymentConfigs = getSepoliaEthConfig();
        } else if (block.chainid == LOCAL_ANVIL_CHAIN_ID) {
            deploymentConfigs = getOrCreateAnvilChainNetworkConfig();
        }
    }

    function getDeploymentConfigs()
        public
        view
        returns (Structs.DeploymentConfig[] memory)
    {
        uint256 len = deploymentConfigs.length;
        Structs.DeploymentConfig[]
            memory configs = new Structs.DeploymentConfig[](len);

        for (uint256 k = 0; k < len; k++) {
            configs[k] = deploymentConfigs[k];
        }

        return configs;
    }

    /**
     * @dev Returns the configuration for the Sepolia network.
     * @return sepoliaConfigs struct array with the configuration for Sepolia.
     */
    function getSepoliaEthConfig()
        public
        pure
        returns (Structs.DeploymentConfig[] memory sepoliaConfigs)
    {
        /// price feeds are picked the original feeds not the wrapped ones. e.g.
        /// the price feed for WETH is that of ETH/USD not WETH/USD as this
        /// does not exist on Sepolia.

        // a fixed-size local memory array - which is simply dynamic array that can be returned
        Structs.DeploymentConfig[]
            memory collaterals = new Structs.DeploymentConfig[](4);

        collaterals[0] = Structs.DeploymentConfig({
            collId: "WETH",
            tokenAddr: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81, // 18 decimals token
            liqThreshold: WETH_LIQ_THRESHOLD,
            priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // 8 decimals
            decimals: 18
        });

        collaterals[1] = Structs.DeploymentConfig({
            collId: "LINK",
            tokenAddr: 0x779877A7B0D9E8603169DdbD7836e478b4624789, // 18 decimals
            liqThreshold: LINK_LIQ_THRESHOLD,
            priceFeed: 0xc59E3633BAAC79493d908e63626716e204A45EdF, // 8 decimals
            decimals: 18
        });

        collaterals[2] = Structs.DeploymentConfig({
            collId: "USDT",
            tokenAddr: 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0, // 6 decimals on the token!!
            liqThreshold: USDT_LIQ_THRESHOLD,
            priceFeed: 0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46, // 18 decimals oracle
            decimals: 6
        });

        collaterals[3] = Structs.DeploymentConfig({
            collId: "DAI",
            tokenAddr: 0x68194a729C2450ad26072b3D33ADaCbcef39D574, // 18 decimals on the token!!
            liqThreshold: DAI_LIQ_THRESHOLD,
            priceFeed: 0x14866185B1962B63C3Ea9E03Bc1da838bab34C19, // 8 decimals
            decimals: 18
        });

        return collaterals;
    }

    function getOrCreateAnvilChainNetworkConfig()
        public
        returns (Structs.DeploymentConfig[] memory anvilConfigs)
    {
        Structs.DeploymentConfig[]
            memory mocks = new Structs.DeploymentConfig[](4);

        if (deploymentConfigs[0].tokenAddr != address(0)) {
            return deploymentConfigs;
        }

        // collateral token mocks
        // the decimals mirror what is on mainnet
        vm.startBroadcast();
        ERC20Like weth = new ERC20Like("WETHMock", "WETH", 18);
        ERC20Like link = new ERC20Like("LINKMock", "LINK", 18);
        ERC20Like usdt = new ERC20Like("USDTMock", "USDT", 6);
        ERC20Like dai = new ERC20Like("DAIMock", "DAI", 18);

        // price feeds
        MockV3Aggregator wethFeed = new MockV3Aggregator(8, 201635e6); // $2016.35
        MockV3Aggregator linkFeed = new MockV3Aggregator(8, 1474e6); // $14.74
        MockV3Aggregator usdtFeed = new MockV3Aggregator(18, 10001e14); // $1
        MockV3Aggregator daiFeed = new MockV3Aggregator(8, 10001e14); // $1
        vm.stopBroadcast();

        mocks[0] = Structs.DeploymentConfig({
            collId: bytes32(bytes(weth.symbol())),
            tokenAddr: address(weth),
            liqThreshold: WETH_LIQ_THRESHOLD,
            priceFeed: address(wethFeed),
            decimals: weth.decimals()
        });

        mocks[1] = Structs.DeploymentConfig({
            collId: bytes32(bytes(link.symbol())),
            tokenAddr: address(link),
            liqThreshold: LINK_LIQ_THRESHOLD,
            priceFeed: address(linkFeed),
            decimals: link.decimals()
        });

        mocks[2] = Structs.DeploymentConfig({
            collId: bytes32(bytes(usdt.symbol())),
            tokenAddr: address(usdt),
            liqThreshold: USDT_LIQ_THRESHOLD,
            priceFeed: address(usdtFeed),
            decimals: usdt.decimals()
        });

        mocks[3] = Structs.DeploymentConfig({
            collId: bytes32(bytes(dai.symbol())),
            tokenAddr: address(dai),
            liqThreshold: DAI_LIQ_THRESHOLD,
            priceFeed: address(daiFeed),
            decimals: dai.decimals()
        });

        return mocks;
    }
}
