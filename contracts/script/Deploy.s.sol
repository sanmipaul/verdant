// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {PremiumPool} from "../src/PremiumPool.sol";
import {PayoutVault} from "../src/PayoutVault.sol";
import {WeatherOracle} from "../src/WeatherOracle.sol";

contract Deploy is Script {
    // Celo mainnet cUSD
    address constant CUSD_MAINNET = 0x765DE816845861e75A25fCA122bb6898B8B1282a;
    // Alfajores testnet cUSD
    address constant CUSD_ALFAJORES = 0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1;

    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        address agentWallet = vm.envAddress("AGENT_WALLET_ADDRESS");
        bool isMainnet = vm.envOr("MAINNET", false);

        address cUSD = isMainnet ? CUSD_MAINNET : CUSD_ALFAJORES;

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        PremiumPool pool = new PremiumPool(cUSD, deployer);
        console.log("PremiumPool deployed:", address(pool));

        PolicyRegistry registry = new PolicyRegistry(cUSD, address(pool), deployer);
        console.log("PolicyRegistry deployed:", address(registry));

        PayoutVault vault = new PayoutVault(address(registry), address(pool), deployer);
        console.log("PayoutVault deployed:", address(vault));

        WeatherOracle oracle = new WeatherOracle(agentWallet);
        console.log("WeatherOracle deployed:", address(oracle));

        // Wire up
        pool.setPayoutVault(address(vault));
        registry.setAuthorizedAgent(agentWallet);
        vault.setAuthorizedAgent(agentWallet);

        console.log("---");
        console.log("Agent wallet:", agentWallet);
        console.log("cUSD:", cUSD);
        console.log("Network:", isMainnet ? "Celo Mainnet" : "Alfajores Testnet");

        vm.stopBroadcast();
    }
}
