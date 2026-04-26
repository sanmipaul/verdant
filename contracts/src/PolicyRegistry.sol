// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {PremiumPool} from "./PremiumPool.sol";

/// @title PolicyRegistry
/// @notice Stores all crop insurance policies. Farmers register plots here,
///         pay premiums, and policies are tracked through their lifecycle.
/// @dev Feature: Policies can auto-expire based on endDate. Added expire functions, checks, and views. Supports batch operations.
contract PolicyRegistry {
    enum CoverageType {
        DROUGHT,
        FLOOD,
        EXTREME_HEAT,
        DRY_SPELL
    }

    enum PolicyStatus {
        ACTIVE,
        CLAIMED,
        EXPIRED,
        CANCELLED
    }

    struct Policy {
        bytes32 policyId;
        address farmer;
        int256 lat;              // GPS latitude scaled by 1e6
        int256 lng;              // GPS longitude scaled by 1e6
        CoverageType coverageType;
        uint256 coverageAmount;  // cUSD payout in wei
        uint256 premiumPaid;     // cUSD premium in wei
        uint40 startDate;
        uint40 endDate;
        PolicyStatus status;
    }

    IERC20 public immutable cUSD;
    PremiumPool public immutable premiumPool;
    address public immutable owner;
    address public authorizedAgent;

    // policyId => Policy
    mapping(bytes32 => Policy) public policies;

    // farmer => policyIds
    mapping(address => bytes32[]) public farmerPolicies;

    // Minimum premium: 0.00001 cUSD (matches Prova bounty scale)
    uint256 public constant MIN_PREMIUM = 1e13;

    // Maximum coverage per policy: 0.001 cUSD
    uint256 public constant MAX_COVERAGE = 1e15;
    
    // Minimum policy duration: 1 day
    uint256 public constant MIN_DURATION = 1 days;
    
    // Pause state
    bool private _paused;

    event PolicyRegistered(
        bytes32 indexed policyId,
        address indexed farmer,
        CoverageType coverageType,
        uint256 coverageAmount,
        uint40 endDate
    );
    event PolicyClaimed(bytes32 indexed policyId, address indexed farmer, uint256 payout);
    event PolicyExpired(bytes32 indexed policyId);
    event AgentUpdated(address indexed agent);
    event Paused(address account);
    event Unpaused(address account);

    error Unauthorized();
    error InvalidPremium();
    error InvalidCoverage();
    error InvalidDuration();
    error PolicyNotActive();
    error PolicyAlreadyExists();
    error TransferFailed();
    error ContractPaused();
    error DurationTooShort();

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier onlyAgent() {
        if (msg.sender != authorizedAgent) revert Unauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (_paused) revert ContractPaused();
        _;
    }

    modifier whenPaused() {
        if (!_paused) revert ContractPaused();
        _;
    }

    constructor(address _cUSD, address _premiumPool, address _owner) {
        cUSD = IERC20(_cUSD);
        premiumPool = PremiumPool(_premiumPool);
        owner = _owner;
    }

    /// @notice Check if farmer has an active policy for the given location and coverage type.
    /// This prevents duplicate policies for the same farmer at the same location with the same coverage type.
    /// Used internally in registerPolicy to enforce uniqueness.
    function _hasActivePolicyForLocation(
        address farmer,
        int256 lat,
        int256 lng,
        CoverageType coverageType
    ) internal view returns (bool) {
        bytes32[] memory policyIds = farmerPolicies[farmer];
        // Loop through all policies of the farmer
        // This is O(n) where n is number of policies per farmer, acceptable for typical use
        for (uint256 i = 0; i < policyIds.length; i++) {
            Policy memory p = policies[policyIds[i]];
            // Check if policy is active and matches the location and coverage type
            // If all conditions match, a duplicate exists
            if (p.status == PolicyStatus.ACTIVE && p.lat == lat && p.lng == lng && p.coverageType == coverageType) {
                return true; // Found a matching active policy
            }
        }
        return false; // No matching active policy found, registration allowed
    }

    /// @notice Public view to check if farmer has an active policy for location and type.
    /// Useful for frontend or external contracts to validate before registration.
    /// Returns true if an active policy exists for the given parameters.
    function hasActivePolicyForLocation(
        address farmer,
        int256 lat,
        int256 lng,
        CoverageType coverageType
    ) external view returns (bool) {
        return _hasActivePolicyForLocation(farmer, lat, lng, coverageType);
    }
    /// @notice Set the authorized Cloudflare agent wallet.
    function setAuthorizedAgent(address _agent) external onlyOwner {
        authorizedAgent = _agent;
        emit AgentUpdated(_agent);
    }

    /// @notice Pause contract - only owner, disables registrations/claims/expiry
    function pause() external onlyOwner whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause contract - only owner, re-enables registrations/claims/expiry
    function unpause() external onlyOwner whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Returns true if contract is paused
    function paused() public view returns (bool) {
        return _paused;
    }

    /// @notice Register a new insurance policy.
    /// @param lat      GPS latitude × 1e6 (e.g. 1.2921° = 1292100)
    /// @param lng      GPS longitude × 1e6
    /// @param coverageType  Type of weather event covered
    /// @param coverageAmount  cUSD payout amount in wei (max 50 cUSD)
    /// @param endDate  Policy expiry timestamp
    function registerPolicy(
        int256 lat,
        int256 lng,
        CoverageType coverageType,
        uint256 coverageAmount,
        uint40 endDate
    ) external whenNotPaused returns (bytes32 policyId) {
        if (coverageAmount == 0 || coverageAmount > MAX_COVERAGE) revert InvalidCoverage();
        if (endDate <= block.timestamp) revert InvalidDuration();
        if (endDate - block.timestamp < MIN_DURATION) revert DurationTooShort();

        // Prevent registering duplicate active policies for the same location and coverage type
        if (_hasActivePolicyForLocation(msg.sender, lat, lng, coverageType)) revert PolicyAlreadyExists();

        uint256 premium = _calculatePremium(coverageAmount);
        if (cUSD.allowance(msg.sender, address(this)) < premium) revert InvalidPremium();

        policyId = keccak256(
            abi.encodePacked(msg.sender, lat, lng, coverageType, block.timestamp)
        );
        if (policies[policyId].startDate != 0) revert PolicyAlreadyExists();

        // Transfer premium to pool
        cUSD.transferFrom(msg.sender, address(premiumPool), premium);

        // Cache current timestamp
        uint40 currentTime = uint40(block.timestamp);

        policies[policyId] = Policy({
            policyId: policyId,
            farmer: msg.sender,
            lat: lat,
            lng: lng,
            coverageType: coverageType,
            coverageAmount: coverageAmount,
            premiumPaid: premium,
            startDate: currentTime,
            endDate: endDate,
            status: PolicyStatus.ACTIVE
        });

        farmerPolicies[msg.sender].push(policyId);

        emit PolicyRegistered(policyId, msg.sender, coverageType, coverageAmount, endDate);
    }

    /// @notice Called by the authorized agent when a parametric trigger is confirmed.
    function markClaimed(bytes32 policyId) external onlyAgent whenNotPaused {
        Policy storage p = policies[policyId];
        if (p.status != PolicyStatus.ACTIVE) revert PolicyNotActive();
        if (block.timestamp > p.endDate) {
            p.status = PolicyStatus.EXPIRED;
            emit PolicyExpired(policyId);
            revert PolicyNotActive();
        }

        p.status = PolicyStatus.CLAIMED;

        emit PolicyClaimed(policyId, p.farmer, p.coverageAmount);
    }

    /// @notice Batch mark multiple policies as claimed (gas optimized).
    function batchMarkClaimed(bytes32[] calldata policyIds) external onlyAgent whenNotPaused {
        uint256 length = policyIds.length;
        uint40 currentTime = uint40(block.timestamp);

        for (uint256 i = 0; i < length; ) {
            bytes32 policyId = policyIds[i];
            Policy storage p = policies[policyId];

            if (p.status == PolicyStatus.ACTIVE && currentTime <= p.endDate) {
                p.status = PolicyStatus.CLAIMED;
                emit PolicyClaimed(policyId, p.farmer, p.coverageAmount);
            }

            unchecked { i++; }
        }
    }

    /// @notice Expire a policy that has passed its end date.
    /// @dev Anyone can call this to update the status.
    function expirePolicy(bytes32 policyId) external whenNotPaused {
        Policy storage p = policies[policyId];
        if (p.status != PolicyStatus.ACTIVE) revert PolicyNotActive();
        if (block.timestamp <= p.endDate) revert PolicyNotActive();

        p.status = PolicyStatus.EXPIRED;
        emit PolicyExpired(policyId);
    }

    /// @notice Batch expire multiple policies that have passed their end dates.
    /// @dev Skips policies that are not active or not expired.
    function batchExpirePolicies(bytes32[] calldata policyIds) external whenNotPaused {
        for (uint256 i = 0; i < policyIds.length; i++) {
            bytes32 policyId = policyIds[i];
            Policy storage p = policies[policyId];
            if (p.status == PolicyStatus.ACTIVE && block.timestamp > p.endDate) {
                p.status = PolicyStatus.EXPIRED;
                emit PolicyExpired(policyId);
            }
        }
    }

    /// @notice Get all policy IDs for a farmer.
    function getFarmerPolicies(address farmer) external view returns (bytes32[] memory) {
        return farmerPolicies[farmer];
    }
    /// @notice Calculate premium for a given coverage amount.
    ///         Premium = 1% of coverage amount, minimum 0.50 cUSD.
    function _calculatePremium(uint256 coverageAmount) internal pure returns (uint256) {
        uint256 calculated;
        assembly {
            calculated := div(coverageAmount, 100)
        }
        return calculated < MIN_PREMIUM ? MIN_PREMIUM : calculated;
    }

    /// @notice Public view for premium calculation.
    function calculatePremium(uint256 coverageAmount) external pure returns (uint256) {
        return _calculatePremium(coverageAmount);
    }



    function getActiveFarmerPolicies(address farmer) external view returns (bytes32[] memory) {
        bytes32[] memory allPolicies = farmerPolicies[farmer];
        uint256 length = allPolicies.length;
        uint256 activeCount;

        // First pass: count active policies
        for (uint256 i = 0; i < length; ) {
            if (policies[allPolicies[i]].status == PolicyStatus.ACTIVE) {
                activeCount++;
            }
            unchecked { i++; }
        }

        // Second pass: collect active policies
        bytes32[] memory activePolicies = new bytes32[](activeCount);
        uint256 index;
        for (uint256 i = 0; i < length; ) {
            bytes32 policyId = allPolicies[i];
            if (policies[policyId].status == PolicyStatus.ACTIVE) {
                activePolicies[index] = policyId;
                unchecked { index++; }
            }
            unchecked { i++; }
        }

        return activePolicies;
    }

    /// @notice Check if a policy is expired (gas optimized view).
    function isPolicyExpired(bytes32 policyId) external view returns (bool) {
        Policy storage p = policies[policyId];
        return p.status == PolicyStatus.ACTIVE && uint40(block.timestamp) > p.endDate;
    }
}
