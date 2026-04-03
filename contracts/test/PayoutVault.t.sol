// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PayoutVault} from "../src/PayoutVault.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {PremiumPool} from "../src/PremiumPool.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract PayoutVaultTest is Test {
    PayoutVault public vault;
    PolicyRegistry public registry;
    PremiumPool public pool;
    MockERC20 public cUSD;

    address public owner = makeAddr("owner");
    address public agent = makeAddr("agent");
    address public farmer = makeAddr("farmer");
    address public sponsor = makeAddr("sponsor");

    int256 constant LAT = -1292100;
    int256 constant LNG = 36821800;
    uint256 constant COVERAGE = 20e18;
    uint40 constant DURATION = 30 days;

    function setUp() public {
        cUSD = new MockERC20("Celo Dollar", "cUSD", 18);
        pool = new PremiumPool(address(cUSD), owner);
        registry = new PolicyRegistry(address(cUSD), address(pool), owner);
        vault = new PayoutVault(address(registry), address(pool), owner);

        vm.startPrank(owner);
        registry.setAuthorizedAgent(agent);
        vault.setAuthorizedAgent(agent);
        pool.setPayoutVault(address(vault));
        vm.stopPrank();

        // Fund pool with reserve capital
        cUSD.mint(sponsor, 500e18);
        vm.prank(sponsor);
        cUSD.approve(address(pool), 500e18);
        vm.prank(sponsor);
        pool.deposit(500e18);

        // Fund farmer for premiums
        cUSD.mint(farmer, 100e18);
    }

    function test_TriggerPayout() public {
        bytes32 policyId = _registerAndClaimPolicy();

        uint256 farmerBalanceBefore = cUSD.balanceOf(farmer);

        vm.prank(agent);
        vault.triggerPayout(policyId);

        assertEq(cUSD.balanceOf(farmer), farmerBalanceBefore + COVERAGE);
        assertTrue(vault.isPayoutExecuted(policyId));
    }

    function test_CannotPayoutTwice() public {
        bytes32 policyId = _registerAndClaimPolicy();

        vm.prank(agent);
        vault.triggerPayout(policyId);

        vm.expectRevert(PayoutVault.AlreadyPaidOut.selector);
        vm.prank(agent);
        vault.triggerPayout(policyId);
    }

    function test_CannotPayoutUnclaimedPolicy() public {
        bytes32 policyId = _registerPolicy();
        // Policy is ACTIVE not CLAIMED — vault should reject

        vm.expectRevert(PayoutVault.PolicyNotClaimable.selector);
        vm.prank(agent);
        vault.triggerPayout(policyId);
    }

    function test_OnlyAgentCanTrigger() public {
        bytes32 policyId = _registerAndClaimPolicy();

        vm.expectRevert(PayoutVault.Unauthorized.selector);
        vm.prank(farmer);
        vault.triggerPayout(policyId);
    }

    function test_BatchPayout() public {
        bytes32 id1 = _registerAndClaimPolicy();
        bytes32 id2 = _registerAndClaimPolicyWithType(PolicyRegistry.CoverageType.FLOOD);

        uint256 farmerBalanceBefore = cUSD.balanceOf(farmer);

        bytes32[] memory ids = new bytes32[](2);
        ids[0] = id1;
        ids[1] = id2;

        vm.prank(agent);
        vault.batchPayout(ids);

        assertEq(cUSD.balanceOf(farmer), farmerBalanceBefore + COVERAGE * 2);
    }

    function test_BatchPayout_SkipsAlreadyPaid() public {
        bytes32 id1 = _registerAndClaimPolicy();

        // Pay id1 first
        vm.prank(agent);
        vault.triggerPayout(id1);

        bytes32 id2 = _registerAndClaimPolicyWithType(PolicyRegistry.CoverageType.FLOOD);

        // Capture balance after all premiums paid, before batch runs
        uint256 balanceBeforeBatch = cUSD.balanceOf(farmer);

        bytes32[] memory ids = new bytes32[](2);
        ids[0] = id1; // already paid — should be skipped
        ids[1] = id2;

        vm.prank(agent);
        vault.batchPayout(ids);

        // Only id2 payout added
        assertEq(cUSD.balanceOf(farmer), balanceBeforeBatch + COVERAGE);
    }

    // --- helpers ---

    function _registerPolicy() internal returns (bytes32) {
        uint256 premium = registry.calculatePremium(COVERAGE);
        vm.startPrank(farmer);
        cUSD.approve(address(registry), premium);
        bytes32 policyId = registry.registerPolicy(
            LAT, LNG, PolicyRegistry.CoverageType.DROUGHT, COVERAGE, uint40(block.timestamp + DURATION)
        );
        vm.stopPrank();
        return policyId;
    }

    function _registerAndClaimPolicy() internal returns (bytes32 policyId) {
        policyId = _registerPolicy();
        vm.prank(agent);
        registry.markClaimed(policyId);
    }

    function _registerAndClaimPolicyWithType(PolicyRegistry.CoverageType t) internal returns (bytes32 policyId) {
        uint256 premium = registry.calculatePremium(COVERAGE);
        vm.startPrank(farmer);
        cUSD.approve(address(registry), premium);
        policyId = registry.registerPolicy(
            LAT + 100, LNG + 100, t, COVERAGE, uint40(block.timestamp + DURATION)
        );
        vm.stopPrank();
        vm.prank(agent);
        registry.markClaimed(policyId);
    }
}
