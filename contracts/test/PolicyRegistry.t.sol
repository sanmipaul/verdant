// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PolicyRegistry} from "../src/PolicyRegistry.sol";
import {PremiumPool} from "../src/PremiumPool.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @dev Tests for PolicyRegistry, including expiration features.
contract PolicyRegistryTest is Test {
    PolicyRegistry public registry;
    PremiumPool public pool;
    MockERC20 public cUSD;

    address public owner = makeAddr("owner");
    address public agent = makeAddr("agent");
    address public farmer = makeAddr("farmer");

    // Nairobi coordinates × 1e6
    int256 constant LAT = -1292100;
    int256 constant LNG = 36821800;

    uint256 constant COVERAGE = 20e18; // 20 cUSD
    uint40 constant DURATION = 30 days;

    function setUp() public {
        cUSD = new MockERC20("Celo Dollar", "cUSD", 18);
        pool = new PremiumPool(address(cUSD), owner);
        registry = new PolicyRegistry(address(cUSD), address(pool), owner);

        vm.prank(owner);
        registry.setAuthorizedAgent(agent);

        // Fund farmer
        cUSD.mint(farmer, 100e18);
    }

    function test_RegisterPolicy() public {
        uint256 premium = registry.calculatePremium(COVERAGE);
        uint40 endDate = uint40(block.timestamp + DURATION);

        vm.startPrank(farmer);
        cUSD.approve(address(registry), premium);

        bytes32 policyId = registry.registerPolicy(
            LAT, LNG, PolicyRegistry.CoverageType.DROUGHT, COVERAGE, endDate
        );
        vm.stopPrank();

        PolicyRegistry.Policy memory p = registry.getPolicy(policyId);
        assertEq(p.farmer, farmer);
        assertEq(p.coverageAmount, COVERAGE);
        assertEq(uint8(p.status), uint8(PolicyRegistry.PolicyStatus.ACTIVE));
        assertEq(p.lat, LAT);
        assertEq(p.lng, LNG);
    }

    function test_PremiumFlowsToPremiumPool() public {
        uint256 premium = registry.calculatePremium(COVERAGE);
        uint40 endDate = uint40(block.timestamp + DURATION);

        vm.startPrank(farmer);
        cUSD.approve(address(registry), premium);
        registry.registerPolicy(LAT, LNG, PolicyRegistry.CoverageType.FLOOD, COVERAGE, endDate);
        vm.stopPrank();

        assertEq(cUSD.balanceOf(address(pool)), premium);
    }

    function test_MinimumPremium() public {
        // Coverage of 10 cUSD → 1% = 0.10 cUSD, below min → should charge 0.50 cUSD
        uint256 lowCoverage = 10e18;
        uint256 premium = registry.calculatePremium(lowCoverage);
        assertEq(premium, 0.5e18);
    }

    function test_MarkClaimed_OnlyAgent() public {
        bytes32 policyId = _registerPolicy();

        vm.expectRevert(PolicyRegistry.Unauthorized.selector);
        vm.prank(farmer);
        registry.markClaimed(policyId);
    }

    function test_MarkClaimed_Success() public {
        bytes32 policyId = _registerPolicy();

        vm.prank(agent);
        registry.markClaimed(policyId);

        PolicyRegistry.Policy memory p = registry.getPolicy(policyId);
        assertEq(uint8(p.status), uint8(PolicyRegistry.PolicyStatus.CLAIMED));
    }

    function test_MarkClaimed_AutoExpire() public {
        bytes32 policyId = _registerPolicy();

        // Warp past end date
        vm.warp(block.timestamp + DURATION + 1);

        vm.expectRevert(PolicyRegistry.PolicyNotActive.selector);
        vm.prank(agent);
        registry.markClaimed(policyId);

        PolicyRegistry.Policy memory p = registry.getPolicy(policyId);
        assertEq(uint8(p.status), uint8(PolicyRegistry.PolicyStatus.EXPIRED));
    }

    function test_CannotClaimTwice() public {
        bytes32 policyId = _registerPolicy();

        vm.prank(agent);
        registry.markClaimed(policyId);

        vm.expectRevert(PolicyRegistry.PolicyNotActive.selector);
        vm.prank(agent);
        registry.markClaimed(policyId);
    }

    function test_CannotRegisterWithZeroCoverage() public {
        vm.prank(farmer);
        vm.expectRevert(PolicyRegistry.InvalidCoverage.selector);
        registry.registerPolicy(LAT, LNG, PolicyRegistry.CoverageType.DROUGHT, 0, uint40(block.timestamp + 1 days));
    }

    function test_CannotRegisterExceedingMaxCoverage() public {
        vm.prank(farmer);
        vm.expectRevert(PolicyRegistry.InvalidCoverage.selector);
        registry.registerPolicy(LAT, LNG, PolicyRegistry.CoverageType.DROUGHT, 51e18, uint40(block.timestamp + 1 days));
    }

    function test_ExpirePolicy() public {
        bytes32 policyId = _registerPolicy();

        // Warp past end date
        vm.warp(block.timestamp + DURATION + 1);
        registry.expirePolicy(policyId);

        PolicyRegistry.Policy memory p = registry.getPolicy(policyId);
        assertEq(uint8(p.status), uint8(PolicyRegistry.PolicyStatus.EXPIRED));
    }

    function test_IsPolicyExpired() public {
        bytes32 policyId = _registerPolicy();

        // Initially not expired
        assertFalse(registry.isPolicyExpired(policyId));

        // Warp past end date
        vm.warp(block.timestamp + DURATION + 1);
        assertTrue(registry.isPolicyExpired(policyId));

        // After expiring
        registry.expirePolicy(policyId);
        assertTrue(registry.isPolicyExpired(policyId));
    }

    function test_BatchExpirePolicies() public {
        bytes32 id1 = _registerPolicy();
        bytes32 id2 = _registerPolicyWithType(PolicyRegistry.CoverageType.FLOOD);

        // Warp past end date
        vm.warp(block.timestamp + DURATION + 1);

        bytes32[] memory ids = new bytes32[](2);
        ids[0] = id1;
        ids[1] = id2;

        registry.batchExpirePolicies(ids);

        assertEq(uint8(registry.getPolicy(id1).status), uint8(PolicyRegistry.PolicyStatus.EXPIRED));
        assertEq(uint8(registry.getPolicy(id2).status), uint8(PolicyRegistry.PolicyStatus.EXPIRED));
    }

    function test_GetActiveFarmerPolicies() public {
        bytes32 id1 = _registerPolicy();
        bytes32 id2 = _registerPolicyWithType(PolicyRegistry.CoverageType.FLOOD);

        // Initially both active
        bytes32[] memory active = registry.getActiveFarmerPolicies(farmer);
        assertEq(active.length, 2);

        // Expire one
        vm.warp(block.timestamp + DURATION + 1);
        registry.expirePolicy(id1);

        active = registry.getActiveFarmerPolicies(farmer);
        assertEq(active.length, 1);
        assertEq(active[0], id2);
    }

    // Additional test for edge case

    function test_GetFarmerPolicies() public {
        bytes32 id1 = _registerPolicy();
        // Register second policy with different coverage type
        uint256 premium = registry.calculatePremium(COVERAGE);
        vm.startPrank(farmer);
        cUSD.approve(address(registry), premium);
        bytes32 id2 = registry.registerPolicy(LAT, LNG, PolicyRegistry.CoverageType.FLOOD, COVERAGE, uint40(block.timestamp + DURATION));
        vm.stopPrank();

        bytes32[] memory farmerPolicies = registry.getFarmerPolicies(farmer);
        assertEq(farmerPolicies.length, 2);
        assertEq(farmerPolicies[0], id1);
        assertEq(farmerPolicies[1], id2);
    }

    // --- helpers ---

    function test_PauseUnpause_OnlyOwner() public {
        vm.prank(owner);
        registry.pause();
        assertTrue(registry.paused());
        
        vm.prank(owner);
        registry.unpause();
        assertFalse(registry.paused());
    }

    function test_Pause_Unauthorized() public {
        vm.expectRevert(PolicyRegistry.Unauthorized.selector);
        vm.prank(farmer);
        registry.pause();
    }

    function test_Unpause_Unauthorized() public {
        vm.prank(owner);
        registry.pause();
        
        vm.expectRevert(PolicyRegistry.Unauthorized.selector);
        vm.prank(farmer);
        registry.unpause();
    }

    function test_PauseWhenAlreadyPaused() public {
        vm.prank(owner);
        registry.pause();
        
        vm.expectRevert(PolicyRegistry.ContractPaused.selector);
        vm.prank(owner);
        registry.pause();
    }

    function test_UnpauseWhenNotPaused() public {
        vm.expectRevert(PolicyRegistry.ContractPaused.selector);
        vm.prank(owner);
        registry.unpause();
    }

    function test_RegisterWhenPaused_Fails() public {
        vm.prank(owner);
        registry.pause();
        
        uint256 premium = registry.calculatePremium(COVERAGE);
        uint40 endDate = uint40(block.timestamp + DURATION);
        
        vm.startPrank(farmer);
        cUSD.approve(address(registry), premium);
        vm.expectRevert(PolicyRegistry.ContractPaused.selector);
        registry.registerPolicy(LAT, LNG, PolicyRegistry.CoverageType.DROUGHT, COVERAGE, endDate);
        vm.stopPrank();
    }

    function test_MarkClaimedWhenPaused_Fails() public {
        bytes32 policyId = _registerPolicy();
        
        vm.prank(owner);
        registry.pause();
        
        vm.expectRevert(PolicyRegistry.ContractPaused.selector);
        vm.prank(agent);
        registry.markClaimed(policyId);
    }

    function test_BatchMarkClaimedWhenPaused_Fails() public {
        bytes32 policyId = _registerPolicy();
        
        vm.prank(owner);
        registry.pause();
        
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = policyId;
        
        vm.expectRevert(PolicyRegistry.ContractPaused.selector);
        vm.prank(agent);
        registry.batchMarkClaimed(ids);
    }

    function test_ExpirePolicyWhenPaused_Fails() public {
        bytes32 policyId = _registerPolicy();
        
        vm.prank(owner);
        registry.pause();
        
        vm.warp(block.timestamp + DURATION + 1);
        vm.expectRevert(PolicyRegistry.ContractPaused.selector);
        registry.expirePolicy(policyId);
    }

    function test_BatchExpireWhenPaused_Fails() public {
        bytes32 policyId = _registerPolicy();
        
        vm.prank(owner);
        registry.pause();
        
        vm.warp(block.timestamp + DURATION + 1);
        
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = policyId;
        
        vm.expectRevert(PolicyRegistry.ContractPaused.selector);
        registry.batchExpirePolicies(ids);
    }

    function test_UnpauseRestoresFunctionality() public {
        bytes32 policyId = _registerPolicy();
        
        vm.prank(owner);
        registry.pause();
        vm.prank(owner);
        registry.unpause();
        
        assertFalse(registry.paused());
        
        vm.prank(agent);
        registry.markClaimed(policyId);
        
        PolicyRegistry.Policy memory p = registry.getPolicy(policyId);
        assertEq(uint8(p.status), uint8(PolicyRegistry.PolicyStatus.CLAIMED));
    }

    function test_MinimumDuration() public {
        uint256 premium = registry.calculatePremium(COVERAGE);
        uint40 endDate = uint40(block.timestamp + 12 hours); // Less than 1 day
        
        vm.startPrank(farmer);
        cUSD.approve(address(registry), premium);
        vm.expectRevert(PolicyRegistry.DurationTooShort.selector);
        registry.registerPolicy(LAT, LNG, PolicyRegistry.CoverageType.DROUGHT, COVERAGE, endDate);
        vm.stopPrank();
    }

    function test_MinimumDurationEdgeCase() public {
        uint256 premium = registry.calculatePremium(COVERAGE);
        uint40 endDate = uint40(block.timestamp + 1 days); // Exactly 1 day
        
        vm.startPrank(farmer);
        cUSD.approve(address(registry), premium);
        registry.registerPolicy(LAT, LNG, PolicyRegistry.CoverageType.DROUGHT, COVERAGE, endDate);
        vm.stopPrank();
        
        bytes32[] memory policies = registry.getFarmerPolicies(farmer);
        assertEq(policies.length, 1);
    }

    function test_PreventDuplicateActivePolicies() public {
        // Test that registering a second policy with same location and coverage type fails
        // This ensures no duplicate active policies for the same farmer, location, and type
        bytes32 policyId1 = _registerPolicy();

        // Try to register second policy with same location and type
        uint256 premium = registry.calculatePremium(COVERAGE);
        uint40 endDate = uint40(block.timestamp + DURATION);

        vm.startPrank(farmer);
        cUSD.approve(address(registry), premium);
        vm.expectRevert(PolicyRegistry.PolicyAlreadyExists.selector); // Should revert due to duplicate
        registry.registerPolicy(LAT, LNG, PolicyRegistry.CoverageType.DROUGHT, COVERAGE, endDate);
        vm.stopPrank();

        // Ensure only one policy exists
        bytes32[] memory policies = registry.getFarmerPolicies(farmer);
        assertEq(policies.length, 1);
    }

    function test_AllowDifferentCoverageType() public {
        // Test that different coverage types are allowed for same location
        // This verifies that only same type is prevented, not different types
        _registerPolicy();

        // Register second with different type, same location
        uint256 premium = registry.calculatePremium(COVERAGE);
        uint40 endDate = uint40(block.timestamp + DURATION);

        vm.startPrank(farmer);
        cUSD.approve(address(registry), premium);
        registry.registerPolicy(LAT, LNG, PolicyRegistry.CoverageType.FLOOD, COVERAGE, endDate);
        vm.stopPrank();

        bytes32[] memory policies = registry.getFarmerPolicies(farmer);
        assertEq(policies.length, 2);
    }

    function _registerPolicy() internal returns (bytes32 policyId) {
        uint256 premium = registry.calculatePremium(COVERAGE);
        vm.startPrank(farmer);
        cUSD.approve(address(registry), premium);
        policyId = registry.registerPolicy(
            LAT, LNG, PolicyRegistry.CoverageType.DROUGHT, COVERAGE, uint40(block.timestamp + DURATION)
        );
        vm.stopPrank();
    }

    function _registerPolicyWithType(PolicyRegistry.CoverageType t) internal returns (bytes32 policyId) {
        uint256 premium = registry.calculatePremium(COVERAGE);
        vm.startPrank(farmer);
        cUSD.approve(address(registry), premium);
        policyId = registry.registerPolicy(
            LAT + 100, LNG + 100, t, COVERAGE, uint40(block.timestamp + DURATION)
        );
        vm.stopPrank();
    }
}
