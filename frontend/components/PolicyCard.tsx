"use client";

import { useReadContract } from "wagmi";
import { formatUnits } from "viem";
import {
  POLICY_REGISTRY_ABI,
  POLICY_REGISTRY_ADDRESS,
  COVERAGE_TYPES,
  COVERAGE_TRIGGERS,
  POLICY_STATUS,
  STATUS_COLORS,
} from "@/lib/contracts";

interface Props {
  policyId: `0x${string}`;
}

export function PolicyCard({ policyId }: Props) {
  const { data: policy, isLoading } = useReadContract({
    address: POLICY_REGISTRY_ADDRESS,
    abi: POLICY_REGISTRY_ABI,
    functionName: "getPolicy",
    args: [policyId],
  });

  if (isLoading || !policy) {
    return (
      <div className="bg-white rounded-2xl p-4 shadow-sm border border-gray-100 animate-pulse h-32" />
    );
  }

  const coverageType = Number(policy.coverageType);
  const status = Number(policy.status);
  const endDate = new Date(Number(policy.endDate) * 1000);
  const latDeg = (Number(policy.lat) / 1e6).toFixed(4);
  const lngDeg = (Number(policy.lng) / 1e6).toFixed(4);

  return (
    <div className="bg-white rounded-2xl p-4 shadow-sm border border-gray-100">
      <div className="flex items-start justify-between mb-3">
        <div>
          <p className="font-semibold text-gray-900">
            {COVERAGE_TYPES[coverageType]}
          </p>
          <p className="text-xs text-gray-400 mt-0.5">
            {COVERAGE_TRIGGERS[coverageType]}
          </p>
        </div>
        <span
          className={`text-xs font-medium px-2.5 py-1 rounded-full ${STATUS_COLORS[status]}`}
        >
          {POLICY_STATUS[status]}
        </span>
      </div>

      <div className="grid grid-cols-2 gap-3 text-sm">
        <div>
          <p className="text-xs text-gray-400">Coverage</p>
          <p className="font-semibold text-gray-800">
            {formatUnits(policy.coverageAmount, 18)} cUSD
          </p>
        </div>
        <div>
          <p className="text-xs text-gray-400">Premium Paid</p>
          <p className="font-semibold text-gray-800">
            {formatUnits(policy.premiumPaid, 18)} cUSD
          </p>
        </div>
        <div>
          <p className="text-xs text-gray-400">Expires</p>
          <p className="font-semibold text-gray-800">
            {endDate.toLocaleDateString()}
          </p>
        </div>
        <div>
          <p className="text-xs text-gray-400">Location</p>
          <p className="font-semibold text-gray-800 text-xs">
            {latDeg}°, {lngDeg}°
          </p>
        </div>
      </div>
    </div>
  );
}
