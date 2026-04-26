"use client";

import { useState } from "react";
import { useWriteContract, useReadContract, useAccount, useSwitchChain } from "wagmi";
import { parseUnits, formatUnits } from "viem";
import { celo } from "viem/chains";
import {
  POLICY_REGISTRY_ADDRESS,
  POLICY_REGISTRY_ABI,
  CUSD_ADDRESS,
  CUSD_ABI,
  COVERAGE_TYPES,
  COVERAGE_TRIGGERS,
} from "@/lib/contracts";

interface Props {
  address: `0x${string}`;
  onSuccess: () => void;
}

type Step = "idle" | "approving" | "registering" | "done";

export function RegisterPolicyForm({ onSuccess }: Props) {
  const [latDeg, setLatDeg] = useState("");
  const [lngDeg, setLngDeg] = useState("");
  const [coverageType, setCoverageType] = useState(0);
  // MAX_COVERAGE in contract = 1e15 wei = 0.001 cUSD
  const [coverageAmountCUSD, setCoverageAmountCUSD] = useState("0.001");
  const [durationMonths, setDurationMonths] = useState(3);
  const [step, setStep] = useState<Step>("idle");
  const [error, setError] = useState("");

  const { address, chainId: walletChainId } = useAccount();
  const { switchChain, isPending: isSwitching } = useSwitchChain();
  const isWrongChain = walletChainId !== celo.id;

  const coverageAmountWei = parseUnits(coverageAmountCUSD || "0", 18);

  const { data: premiumWei, isLoading: isPremiumLoading } = useReadContract({
    address: POLICY_REGISTRY_ADDRESS,
    abi: POLICY_REGISTRY_ABI,
    functionName: "calculatePremium",
    args: [coverageAmountWei],
    chainId: celo.id,
    query: { enabled: coverageAmountWei > 0n && !!POLICY_REGISTRY_ADDRESS },
  });

  const { data: cusdBalance } = useReadContract({
    address: CUSD_ADDRESS,
    abi: CUSD_ABI,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    chainId: celo.id,
    query: { enabled: !!address },
  });

  const { data: currentAllowance } = useReadContract({
    address: CUSD_ADDRESS,
    abi: CUSD_ABI,
    functionName: "allowance",
    args: address ? [address, POLICY_REGISTRY_ADDRESS] : undefined,
    chainId: celo.id,
    query: { enabled: !!address && !!POLICY_REGISTRY_ADDRESS },
  });

  const hasSufficientBalance = cusdBalance !== undefined && premiumWei !== undefined && cusdBalance >= premiumWei;
  const needsApproval = currentAllowance === undefined || premiumWei === undefined || currentAllowance < premiumWei;

  const { writeContractAsync } = useWriteContract();

  function detectLocation() {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLatDeg(pos.coords.latitude.toFixed(6));
        setLngDeg(pos.coords.longitude.toFixed(6));
        setError("");
      },
      () => setError("Location access denied. Enter coordinates manually.")
    );
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");

    if (isWrongChain) {
      setError("Please switch to Celo Mainnet first.");
      return;
    }
    if (!premiumWei) {
      setError("Premium not loaded yet. Wait a moment and try again.");
      return;
    }
    if (!latDeg || !lngDeg) {
      setError("Enter your farm coordinates.");
      return;
    }

    const latScaled = BigInt(Math.round(parseFloat(latDeg) * 1e6));
    const lngScaled = BigInt(Math.round(parseFloat(lngDeg) * 1e6));
    const endDate = Math.floor(Date.now() / 1000) + durationMonths * 30 * 24 * 60 * 60;

    if (!hasSufficientBalance) {
      setError(`Insufficient cUSD balance. You need ${formatUnits(premiumWei, 18)} cUSD but have ${formatUnits(cusdBalance ?? 0n, 18)} cUSD.`);
      return;
    }

    try {
      if (needsApproval) {
        setStep("approving");
        await writeContractAsync({
          address: CUSD_ADDRESS,
          abi: CUSD_ABI,
          functionName: "approve",
          args: [POLICY_REGISTRY_ADDRESS, premiumWei],
          chainId: celo.id,
        });
      }

      setStep("registering");
      await writeContractAsync({
        address: POLICY_REGISTRY_ADDRESS,
        abi: POLICY_REGISTRY_ABI,
        functionName: "registerPolicy",
        args: [latScaled, lngScaled, coverageType, coverageAmountWei, endDate],
        chainId: celo.id,
      });

      setStep("done");
      setTimeout(onSuccess, 1500);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : "Transaction failed.";
      setError(msg.length > 120 ? msg.slice(0, 120) + "…" : msg);
      setStep("idle");
    }
  }

  if (step === "done") {
    return (
      <div className="text-center py-14">
        <div className="text-5xl mb-3">✅</div>
        <p className="font-semibold text-verdant-700 text-lg">
          Policy Registered!
        </p>
        <p className="text-sm text-gray-400 mt-1">
          Your coverage is now active.
        </p>
      </div>
    );
  }

  const isSubmitting = step === "approving" || step === "registering";

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      {isWrongChain && (
        <div className="bg-amber-50 border border-amber-200 rounded-2xl p-4 flex items-center justify-between gap-3">
          <p className="text-sm text-amber-800 font-medium">
            Switch to Celo Mainnet to continue.
          </p>
          <button
            type="button"
            onClick={() => switchChain({ chainId: celo.id })}
            disabled={isSwitching}
            className="shrink-0 bg-amber-600 hover:bg-amber-700 disabled:opacity-50 text-white font-semibold px-4 py-2 rounded-xl text-xs transition-colors"
          >
            {isSwitching ? "Switching…" : "Switch Network"}
          </button>
        </div>
      )}

      <div className="bg-verdant-50 border border-verdant-100 rounded-2xl p-4 text-sm text-verdant-800 leading-relaxed">
        Payouts are automatic — the AI agent monitors your region daily and
        sends cUSD directly to your wallet when a threshold is breached.
      </div>

      {/* Location */}
      <div>
        <div className="flex items-center justify-between mb-1.5">
          <label className="text-sm font-medium text-gray-700">
            Farm Location
          </label>
          <button
            type="button"
            onClick={detectLocation}
            className="text-xs text-verdant-600 underline"
          >
            Use my location
          </button>
        </div>
        <div className="grid grid-cols-2 gap-2">
          <input
            placeholder="Latitude (e.g. 1.2921)"
            value={latDeg}
            onChange={(e) => setLatDeg(e.target.value)}
            required
            className="border border-gray-200 rounded-xl px-3 py-2.5 text-sm w-full focus:outline-none focus:ring-2 focus:ring-verdant-400"
          />
          <input
            placeholder="Longitude (e.g. 36.8219)"
            value={lngDeg}
            onChange={(e) => setLngDeg(e.target.value)}
            required
            className="border border-gray-200 rounded-xl px-3 py-2.5 text-sm w-full focus:outline-none focus:ring-2 focus:ring-verdant-400"
          />
        </div>
      </div>

      {/* Coverage type */}
      <div>
        <label className="text-sm font-medium text-gray-700 block mb-1.5">
          Coverage Type
        </label>
        <div className="grid grid-cols-2 gap-2">
          {COVERAGE_TYPES.map((type, i) => (
            <button
              key={i}
              type="button"
              onClick={() => setCoverageType(i)}
              className={`text-left p-3 rounded-xl border text-sm transition-colors ${
                coverageType === i
                  ? "border-verdant-500 bg-verdant-50 text-verdant-800"
                  : "border-gray-200 text-gray-600 hover:border-gray-300"
              }`}
            >
              <p className="font-medium">{type}</p>
              <p className="text-xs text-gray-400 mt-0.5">
                {COVERAGE_TRIGGERS[i]}
              </p>
            </button>
          ))}
        </div>
      </div>

      {/* Coverage amount */}
      <div>
        <label className="text-sm font-medium text-gray-700 block mb-1.5">
          Coverage Amount
        </label>
        <div className="flex gap-2">
          {["0.0001", "0.0005", "0.001"].map((amount) => (
            <button
              key={amount}
              type="button"
              onClick={() => setCoverageAmountCUSD(amount)}
              className={`flex-1 py-2.5 rounded-xl border text-sm font-medium transition-colors ${
                coverageAmountCUSD === amount
                  ? "border-verdant-500 bg-verdant-50 text-verdant-700"
                  : "border-gray-200 text-gray-600 hover:border-gray-300"
              }`}
            >
              {amount} cUSD
            </button>
          ))}
        </div>
      </div>

      {/* Duration */}
      <div>
        <label className="text-sm font-medium text-gray-700 block mb-1.5">
          Duration
        </label>
        <div className="flex gap-2">
          {[1, 3, 6].map((months) => (
            <button
              key={months}
              type="button"
              onClick={() => setDurationMonths(months)}
              className={`flex-1 py-2.5 rounded-xl border text-sm font-medium transition-colors ${
                durationMonths === months
                  ? "border-verdant-500 bg-verdant-50 text-verdant-700"
                  : "border-gray-200 text-gray-600 hover:border-gray-300"
              }`}
            >
              {months} mo
            </button>
          ))}
        </div>
      </div>

      {/* Summary */}
      {isPremiumLoading && (
        <div className="bg-gray-50 rounded-2xl p-4 text-sm text-gray-400 text-center animate-pulse">
          Loading premium…
        </div>
      )}
      {!isPremiumLoading && premiumWei !== undefined && (
        <div className="bg-gray-50 rounded-2xl p-4 space-y-1.5 text-sm">
          <div className="flex justify-between">
            <span className="text-gray-500">Coverage payout</span>
            <span className="font-medium">{coverageAmountCUSD} cUSD</span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-500">Premium</span>
            <span className="font-semibold text-verdant-700">
              {formatUnits(premiumWei, 18)} cUSD
            </span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-500">Duration</span>
            <span className="font-medium">{durationMonths} month(s)</span>
          </div>
          {cusdBalance !== undefined && (
            <div className="flex justify-between border-t border-gray-200 pt-1.5 mt-1.5">
              <span className="text-gray-500">Your cUSD balance</span>
              <span className={`font-medium ${hasSufficientBalance ? "text-gray-800" : "text-red-600"}`}>
                {formatUnits(cusdBalance, 18)} cUSD
                {!hasSufficientBalance && " ⚠ insufficient"}
              </span>
            </div>
          )}
        </div>
      )}
      {!isPremiumLoading && premiumWei === undefined && POLICY_REGISTRY_ADDRESS && (
        <p className="text-xs text-amber-600 bg-amber-50 rounded-xl px-3 py-2">
          Could not load premium from contract. Check your network connection.
        </p>
      )}

      {error && (
        <p className="text-red-500 text-xs bg-red-50 rounded-xl px-3 py-2">
          {error}
        </p>
      )}

      <button
        type="submit"
        disabled={isSubmitting || isPremiumLoading}
        className="w-full bg-verdant-600 hover:bg-verdant-700 disabled:opacity-50 text-white font-semibold py-3.5 rounded-2xl text-sm transition-colors"
      >
        {step === "approving"
          ? "Approving cUSD spend… (1/2)"
          : step === "registering"
          ? needsApproval ? "Registering policy… (2/2)" : "Registering policy…"
          : isPremiumLoading
          ? "Loading…"
          : "Activate Coverage"}
      </button>
    </form>
  );
}
