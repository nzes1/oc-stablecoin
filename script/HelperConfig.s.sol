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
    uint256 private constant LOCAL_ANVIL_CHAIN_ID = 31_337;

    // Array of deployment configs
    Structs.DeploymentConfig[] public deploymentConfigs;

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            setSepoliaEthConfig();
        } else if (block.chainid == LOCAL_ANVIL_CHAIN_ID) {
            setOrCreateAnvilChainNetworkConfig();
        }
    }

    function getConfigs() public view returns (Structs.DeploymentConfig[] memory sepoliaConfigs) {
        return deploymentConfigs;
    }

    /**
     * @dev Returns the configuration for the Sepolia network.
     * @return sepoliaConfigs struct array with the configuration for Sepolia.
     */
    function setSepoliaEthConfig() internal returns (Structs.DeploymentConfig[] memory sepoliaConfigs) {
        /// price feeds are picked the original feeds not the wrapped ones. e.g.
        /// the price feed for WETH is that of ETH/USD not WETH/USD as this
        /// does not exist on Sepolia.

        // save to storage then return the struct array afterwards.
        // this avoids creating a local array struct and copying it to storage which solidity
        // compiler currently does not support.

        // ETH and WETH share the price feed and liq thresholds.
        deploymentConfigs.push(
            Structs.DeploymentConfig({
                collId: "ETH",
                tokenAddr: address(0),
                liqThreshold: WETH_LIQ_THRESHOLD,
                priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // 8 decimals
                decimals: 18
            })
        );

        deploymentConfigs.push(
            Structs.DeploymentConfig({
                collId: "WETH",
                tokenAddr: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81, // 18 decimals token
                liqThreshold: WETH_LIQ_THRESHOLD,
                priceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // 8 decimals
                decimals: 18
            })
        );

        deploymentConfigs.push(
            Structs.DeploymentConfig({
                collId: "LINK",
                tokenAddr: 0x779877A7B0D9E8603169DdbD7836e478b4624789, // 18 decimals
                liqThreshold: LINK_LIQ_THRESHOLD,
                priceFeed: 0xc59E3633BAAC79493d908e63626716e204A45EdF, // 8 decimals
                decimals: 18
            })
        );

        deploymentConfigs.push(
            Structs.DeploymentConfig({
                collId: "USDT",
                tokenAddr: 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0, // 6 decimals on the token!!
                liqThreshold: USDT_LIQ_THRESHOLD,
                priceFeed: 0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46, // 18 decimals oracle
                decimals: 6
            })
        );

        deploymentConfigs.push(
            Structs.DeploymentConfig({
                collId: "DAI",
                tokenAddr: 0x68194a729C2450ad26072b3D33ADaCbcef39D574, // 18 decimals on the token!!
                liqThreshold: DAI_LIQ_THRESHOLD,
                priceFeed: 0x14866185B1962B63C3Ea9E03Bc1da838bab34C19, // 8 decimals
                decimals: 18
            })
        );

        return deploymentConfigs;
    }

    function setOrCreateAnvilChainNetworkConfig() internal returns (Structs.DeploymentConfig[] memory anvilConfigs) {
        // If previously deployed mocks exist, return them and not re-deploy
        if (deploymentConfigs.length > 0) {
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
        MockV3Aggregator daiFeed = new MockV3Aggregator(8, 10001e4); // $1
        vm.stopBroadcast();

        // ETH is also allowed on tests and shares WETH priceFeed
        deploymentConfigs.push(
            Structs.DeploymentConfig({
                collId: "ETH",
                tokenAddr: address(0),
                liqThreshold: WETH_LIQ_THRESHOLD,
                priceFeed: address(wethFeed),
                decimals: weth.decimals()
            })
        );

        deploymentConfigs.push(
            Structs.DeploymentConfig({
                collId: bytes32(bytes(weth.symbol())),
                tokenAddr: address(weth),
                liqThreshold: WETH_LIQ_THRESHOLD,
                priceFeed: address(wethFeed),
                decimals: weth.decimals()
            })
        );

        deploymentConfigs.push(
            Structs.DeploymentConfig({
                collId: bytes32(bytes(link.symbol())),
                tokenAddr: address(link),
                liqThreshold: LINK_LIQ_THRESHOLD,
                priceFeed: address(linkFeed),
                decimals: link.decimals()
            })
        );

        deploymentConfigs.push(
            Structs.DeploymentConfig({
                collId: bytes32(bytes(usdt.symbol())),
                tokenAddr: address(usdt),
                liqThreshold: USDT_LIQ_THRESHOLD,
                priceFeed: address(usdtFeed),
                decimals: usdt.decimals()
            })
        );

        deploymentConfigs.push(
            Structs.DeploymentConfig({
                collId: bytes32(bytes(dai.symbol())),
                tokenAddr: address(dai),
                liqThreshold: DAI_LIQ_THRESHOLD,
                priceFeed: address(daiFeed),
                decimals: dai.decimals()
            })
        );

        return deploymentConfigs;
    }
}
