// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts@5.1.0/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    /// Struct to hold the configs for deployment of DSCEngine
    /// 2 collateral tokens (WETH and WBTC) and their respective USD price feeds.
    struct NetworkConfig {
        address wETH;
        address wBTC;
        address wETHUsdPriceFeed;
        address wBTCUsdPriceFeed;
        address broadcastAccount;
    }

    uint8 private constant PRICE_FEED_DECIMALS = 8;
    int256 public constant WETH_INITIAL_PRICE_ANSWER = 3383e8;
    int256 public constant WBTC_INITIAL_PRICE_ANSWER = 96935e8;
    uint256 private constant ETH_SEPOLIA_CHAIN_ID = 11_155_111;
    uint256 private constant LOCAL_ANVIL_CHAIN_ID = 31337;

    NetworkConfig public activeChainNetworkConfig;

    constructor() {
        if (block.chainid == ETH_SEPOLIA_CHAIN_ID) {
            activeChainNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == LOCAL_ANVIL_CHAIN_ID) {
            activeChainNetworkConfig = getOrCreateAnvilChainNetworkConfig();
        }
    }

    /**
     * @dev Returns the configuration for the Sepolia network.
     * @return sepoliaNetworkConfig struct with the configuration for Sepolia.
     */
    function getSepoliaEthConfig() public pure returns (NetworkConfig memory sepoliaNetworkConfig) {
        /// price feeds are picked the original feeds not the wrapped ones. e.g.
        /// wETHUsdPriceFeed is the price feed for ETH/USD not WETH/USD as this
        /// does not exist on Sepolia.
        return NetworkConfig({
            wETH: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wBTC: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            wETHUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wBTCUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            broadcastAccount: 0xda2E5DC778F054d7FB2eE00dD65ab5C977903E40
        });
    }

    function getOrCreateAnvilChainNetworkConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        if (activeChainNetworkConfig.wETH != address(0)) {
            return activeChainNetworkConfig;
        }

        /// Mocks for Anvil chain.
        vm.startBroadcast();
        ERC20Mock wETHMock = new ERC20Mock();
        ERC20Mock wBTCMock = new ERC20Mock();

        MockV3Aggregator wETHPriceFeed = new MockV3Aggregator(PRICE_FEED_DECIMALS, WETH_INITIAL_PRICE_ANSWER);
        MockV3Aggregator wBTCPriceFeed = new MockV3Aggregator(PRICE_FEED_DECIMALS, WBTC_INITIAL_PRICE_ANSWER);
        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            wETH: address(wETHMock),
            wBTC: address(wBTCMock),
            wETHUsdPriceFeed: address(wETHPriceFeed),
            wBTCUsdPriceFeed: address(wBTCPriceFeed),
            /// For Anvil testing, we'll set the broadcast account to be the default foundry account
            /// which is available in lib/forge-std/src/Base.sol::DEFAULT_SENDER
            broadcastAccount: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
        });

        return anvilNetworkConfig;
    }
}
