// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PolicyRegistry} from "./PolicyRegistry.sol";
import {PremiumPool} from "./PremiumPool.sol";

/// @title PayoutVault
/// @notice Receives trigger signals from the authorized Cloudflare agent and
///         executes cUSD payouts by pulling funds from PremiumPool.
/// @dev Payout amounts calculated proportionally to premium paid.
contract PayoutVault {
    PolicyRegistry public immutable registry;
    PremiumPool public immutable pool;
    address public immutable owner;
    address public authorizedAgent;

    // Minimum premium: 0.50 cUSD (18 decimals)
    uint256 public constant MIN_PREMIUM = 0.5e18;

    // policyId => whether a payout has been executed (prevents double-payout)
    mapping(bytes32 => bool) public payoutExecuted;

    event PayoutExecuted(bytes32 indexed policyId, address indexed farmer, uint256 amount);
    event BatchPayoutExecuted(uint256 count, uint256 totalAmount);
    event AgentUpdated(address indexed agent);

    error Unauthorized();
    error AlreadyPaidOut();
    error PolicyNotClaimable();

    modifier onlyAgent() {
        if (msg.sender != authorizedAgent) revert Unauthorized();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor(address _registry, address _pool, address _owner) {
        registry = PolicyRegistry(_registry);
        pool = PremiumPool(_pool);
        owner = _owner;
    }

    /// @notice Update the authorized agent wallet.
    function setAuthorizedAgent(address _agent) external onlyOwner {
        authorizedAgent = _agent;
        emit AgentUpdated(_agent);
    }

    /// @notice Trigger a payout for a single policy.
    ///         Agent must call PolicyRegistry.markClaimed() before calling this.
    function triggerPayout(bytes32 policyId) external onlyAgent {
        if (payoutExecuted[policyId]) revert AlreadyPaidOut();

        PolicyRegistry.Policy memory p = registry.getPolicy(policyId);
        if (p.status != PolicyRegistry.PolicyStatus.CLAIMED) revert PolicyNotClaimable();

        payoutExecuted[policyId] = true;

        // Calculate payout proportional to premium paid relative to minimum premium
        uint256 amount = p.premiumPaid == 0 ? 0 : p.coverageAmount * p.premiumPaid / MIN_PREMIUM;

        pool.withdrawForPayout(amount, p.farmer);

        emit PayoutExecuted(policyId, p.farmer, amount);
    }

    /// @notice Batch payout for multiple triggered policies in a single transaction.
    function batchPayout(bytes32[] calldata policyIds) external onlyAgent {
        uint256 count;
        uint256 totalAmount;
        uint256 length = policyIds.length;

        for (uint256 i = 0; i < length; ) {
            bytes32 policyId = policyIds[i];

            if (!payoutExecuted[policyId]) {
                PolicyRegistry.Policy memory p = registry.getPolicy(policyId);
                if (p.status == PolicyRegistry.PolicyStatus.CLAIMED) {
                    payoutExecuted[policyId] = true;
                    // Calculate payout proportional to premium paid relative to minimum premium
                    uint256 amount = p.premiumPaid == 0 ? 0 : p.coverageAmount * p.premiumPaid / MIN_PREMIUM;
                    totalAmount += amount;
                    count++;

                    pool.withdrawForPayout(amount, p.farmer);

                    emit PayoutExecuted(policyId, p.farmer, amount);
                }
            }

            unchecked { i++; }
        }

        if (count > 0) {
            emit BatchPayoutExecuted(count, totalAmount);
        }
    }

    /// @notice Check if a payout has been executed for a policy.
    function isPayoutExecuted(bytes32 policyId) external view returns (bool) {
        return payoutExecuted[policyId];
    }

    /// @notice Calculate the payout amount for a policy.
    /// @dev Returns 0 if premiumPaid is 0 to avoid division issues, though MIN_PREMIUM > 0.
    function calculatePayout(bytes32 policyId) external view returns (uint256) {
        PolicyRegistry.Policy memory p = registry.getPolicy(policyId);
        if (p.premiumPaid == 0) return 0;
        return p.coverageAmount * p.premiumPaid / MIN_PREMIUM;
    }
}
