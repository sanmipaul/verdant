// Contract addresses — set via environment variables after deployment
export const POLICY_REGISTRY_ADDRESS = (
  process.env.NEXT_PUBLIC_POLICY_REGISTRY_ADDRESS ?? ""
) as `0x${string}`;

// cUSD on Celo mainnet. Override via env for Alfajores.
export const CUSD_ADDRESS = (
  process.env.NEXT_PUBLIC_CUSD_ADDRESS ??
  "0x765DE816845861e75A25fCA122bb6898B8B1282a"
) as `0x${string}`;

// ─── Enums ────────────────────────────────────────────────────────────────────

export const COVERAGE_TYPES = ["Drought", "Flood", "Extreme Heat", "Dry Spell"];

export const COVERAGE_TRIGGERS: Record<number, string> = {
  0: "Rainfall < 20mm over 30 days",
  1: "Rainfall > 200mm over 7 days",
  2: "Avg temp > 38°C over 14 days",
  3: "< 5mm rain in first 21 days",
};

export const POLICY_STATUS = ["Active", "Claimed", "Expired", "Cancelled"];

export const STATUS_COLORS: Record<number, string> = {
  0: "bg-green-100 text-green-700",
  1: "bg-blue-100 text-blue-700",
  2: "bg-gray-100 text-gray-500",
  3: "bg-red-100 text-red-600",
};

// ─── PolicyRegistry ABI ───────────────────────────────────────────────────────

export const POLICY_REGISTRY_ABI = [
  {
    name: "registerPolicy",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "lat", type: "int256" },
      { name: "lng", type: "int256" },
      { name: "coverageType", type: "uint8" },
      { name: "coverageAmount", type: "uint256" },
      { name: "endDate", type: "uint40" },
    ],
    outputs: [{ name: "policyId", type: "bytes32" }],
  },
  {
    name: "getFarmerPolicies",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "farmer", type: "address" }],
    outputs: [{ name: "", type: "bytes32[]" }],
  },
  {
    name: "getPolicy",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "policyId", type: "bytes32" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "policyId", type: "bytes32" },
          { name: "farmer", type: "address" },
          { name: "lat", type: "int256" },
          { name: "lng", type: "int256" },
          { name: "coverageType", type: "uint8" },
          { name: "coverageAmount", type: "uint256" },
          { name: "premiumPaid", type: "uint256" },
          { name: "startDate", type: "uint40" },
          { name: "endDate", type: "uint40" },
          { name: "status", type: "uint8" },
        ],
      },
    ],
  },
  {
    name: "calculatePremium",
    type: "function",
    stateMutability: "pure",
    inputs: [{ name: "coverageAmount", type: "uint256" }],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

// ─── cUSD ERC-20 ABI (subset) ─────────────────────────────────────────────────

export const CUSD_ABI = [
  {
    name: "approve",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "allowance",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;
