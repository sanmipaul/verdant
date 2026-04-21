// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {PremiumPool} from "../src/PremiumPool.sol";
import {PayoutVault} from "../src/PayoutVault.sol";
import {WeatherOracle} from "../src/WeatherOracle.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice End-to-end test simulating the full parametric insurance lifecycle:
///         register → weather event → mark claimed → payout → audit trail
/// @dev Updated to use multiple API sources for weather events.
contract IntegrationTest is Test {
    PolicyRegistry registry;
    PremiumPool pool;
    PayoutVault vault;
    WeatherOracle oracle;
    MockERC20 cUSD;

    address owner   = makeAddr("owner");
    address agent   = makeAddr("agent");
    address farmer1 = makeAddr("farmer1");
    address farmer2 = makeAddr("farmer2");
    address sponsor = makeAddr("sponsor");

    int256 constant LAT = -1292100; // Nairobi
    int256 constant LNG = 36821800;

    function setUp() public {
        cUSD = new MockERC20("Celo Dollar", "cUSD", 18);

        pool     = new PremiumPool(address(cUSD), owner);
        registry = new PolicyRegistry(address(cUSD), address(pool), owner);
        vault    = new PayoutVault(address(registry), address(pool), owner);
        oracle   = new WeatherOracle(agent);

        vm.startPrank(owner);
        registry.setAuthorizedAgent(agent);
        vault.setAuthorizedAgent(agent);
        pool.setPayoutVault(address(vault));
        vm.stopPrank();

        // Sponsor seeds the pool
        cUSD.mint(sponsor, 1000e18);
        vm.startPrank(sponsor);
        cUSD.approve(address(pool), 1000e18);
        pool.deposit(1000e18);
        vm.stopPrank();

        cUSD.mint(farmer1, 50e18);
        cUSD.mint(farmer2, 50e18);
    }

    function test_FullDroughtLifecycle() public {
        // 1. Farmer registers drought coverage
        uint256 coverage = 30e18;
        uint256 premium  = registry.calculatePremium(coverage);
        uint40  endDate  = uint40(block.timestamp + 60 days);

        vm.startPrank(farmer1);
        cUSD.approve(address(registry), premium);
        bytes32 policyId = registry.registerPolicy(
            LAT, LNG, PolicyRegistry.CoverageType.DROUGHT, coverage, endDate
        );
        vm.stopPrank();

        // 2. Agent records a drought weather event after 30 days
        vm.warp(block.timestamp + 30 days);

        WeatherOracle.ApiData[] memory apiData = new WeatherOracle.ApiData[](2);
        apiData[0] = WeatherOracle.ApiData("open-meteo", 1500, uint40(block.timestamp));
        apiData[1] = WeatherOracle.ApiData("nasa-power", 1400, uint40(block.timestamp));

        vm.prank(agent);
        oracle.recordEvent(
            LAT, LNG,
            WeatherOracle.EventType.DROUGHT,
            apiData,
            uint40(block.timestamp)
        );

        // 3. Agent marks policy as claimed
        vm.prank(agent);
        registry.markClaimed(policyId);

        // 4. Agent triggers payout
        uint256 balanceBefore = cUSD.balanceOf(farmer1);

        vm.prank(agent);
        vault.triggerPayout(policyId);

        // 5. Farmer received coverage (proportional to premium paid)
        uint256 expectedPayout = vault.calculatePayout(policyId);
        assertEq(cUSD.balanceOf(farmer1), balanceBefore + expectedPayout);

        // 6. Policy status is CLAIMED
        PolicyRegistry.Policy memory p = registry.getPolicy(policyId);
        assertEq(uint8(p.status), uint8(PolicyRegistry.PolicyStatus.CLAIMED));

        // 7. Oracle has the weather event on-chain
        bytes32[] memory events = oracle.getRegionEvents(LAT, LNG);
        assertEq(events.length, 1);
    }

    function test_MultipleRegionsIndependent() public {
        // Farmer1 in Nairobi, Farmer2 in Lagos (different region)
        int256 lagosLat = 6452200;
        int256 lagosLng = 3395800;

        uint256 coverage = 20e18;
        uint40  endDate  = uint40(block.timestamp + 60 days);

        // Both register policies
        vm.startPrank(farmer1);
        cUSD.approve(address(registry), registry.calculatePremium(coverage));
        bytes32 policy1 = registry.registerPolicy(LAT, LNG, PolicyRegistry.CoverageType.DROUGHT, coverage, endDate);
        vm.stopPrank();

        vm.startPrank(farmer2);
        cUSD.approve(address(registry), registry.calculatePremium(coverage));
        bytes32 policy2 = registry.registerPolicy(lagosLat, lagosLng, PolicyRegistry.CoverageType.FLOOD, coverage, endDate);
        vm.stopPrank();

        // Agent records event only in Nairobi region
        WeatherOracle.ApiData[] memory apiData = new WeatherOracle.ApiData[](2);
        apiData[0] = WeatherOracle.ApiData("open-meteo", 1000, uint40(block.timestamp));
        apiData[1] = WeatherOracle.ApiData("nasa-power", 950, uint40(block.timestamp));

        vm.prank(agent);
        oracle.recordEvent(LAT, LNG, WeatherOracle.EventType.DROUGHT, apiData, uint40(block.timestamp));

        // Only Nairobi policy gets claimed
        vm.prank(agent);
        registry.markClaimed(policy1);

        vm.prank(agent);
        vault.triggerPayout(policy1);

        // Farmer1 received payout, Farmer2 did not
        uint256 expectedPayout1 = vault.calculatePayout(policy1);
        assertEq(cUSD.balanceOf(farmer1), 50e18 - registry.calculatePremium(coverage) + expectedPayout1);
        assertEq(cUSD.balanceOf(farmer2), 50e18 - registry.calculatePremium(coverage));
        assertFalse(vault.isPayoutExecuted(policy2));
    }

    function test_BatchPayoutForRegionWideEvent() public {
        uint256 coverage = 10e18;
        uint40  endDate  = uint40(block.timestamp + 60 days);

        // Three farmers in the same region register drought policies
        address[] memory farmers = new address[](3);
        bytes32[] memory ids = new bytes32[](3);
        farmers[0] = makeAddr("f1");
        farmers[1] = makeAddr("f2");
        farmers[2] = makeAddr("f3");

        for (uint256 i = 0; i < 3; i++) {
            cUSD.mint(farmers[i], 10e18);
            uint256 premium = registry.calculatePremium(coverage);
            vm.startPrank(farmers[i]);
            cUSD.approve(address(registry), premium);
            ids[i] = registry.registerPolicy(
                LAT + int256(i * 1000), LNG, PolicyRegistry.CoverageType.DROUGHT, coverage, endDate
            );
            vm.stopPrank();
        }

        // Agent claims all three
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(agent);
            registry.markClaimed(ids[i]);
        }

        // Single batch payout transaction
        vm.prank(agent);
        vault.batchPayout(ids);

        // All three received payouts
        for (uint256 i = 0; i < 3; i++) {
            assertTrue(vault.isPayoutExecuted(ids[i]));
            assertGe(cUSD.balanceOf(farmers[i]), coverage);
        }
    }
}
