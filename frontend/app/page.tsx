"use client";

import { useState } from "react";
import { useAccount, useConnect, useDisconnect, useReadContract } from "wagmi";
import { injected } from "wagmi/connectors";
import { useMiniPay } from "@/hooks/useMiniPay";
import { PolicyCard } from "@/components/PolicyCard";
import { RegisterPolicyForm } from "@/components/RegisterPolicyForm";
import { POLICY_REGISTRY_ABI, POLICY_REGISTRY_ADDRESS } from "@/lib/contracts";

type Tab = "policies" | "register";

export default function Home() {
  const [tab, setTab] = useState<Tab>("policies");

  const { address: wagmiAddress, isConnected } = useAccount();
  const { connect } = useConnect();
  const { disconnect } = useDisconnect();
  const { isMiniPay, address: miniPayAddress } = useMiniPay();

  // MiniPay injects the wallet; fall back to wagmi for browser wallets
  const address = miniPayAddress ?? (isConnected ? wagmiAddress : undefined);

  const { data: policyIds, refetch } = useReadContract({
    address: POLICY_REGISTRY_ADDRESS,
    abi: POLICY_REGISTRY_ABI,
    functionName: "getFarmerPolicies",
    args: address ? [address] : undefined,
    query: { enabled: !!address && !!POLICY_REGISTRY_ADDRESS },
  });

  function handleRegistered() {
    refetch();
    setTab("policies");
  }

  return (
    <main className="min-h-screen bg-gradient-to-b from-verdant-50 to-white">
      {/* Header */}
      <header className="bg-verdant-700 text-white px-4 py-4 flex items-center justify-between">
        <div>
          <h1 className="text-lg font-bold tracking-tight">Verdant</h1>
          <p className="text-verdant-200 text-xs">Crop Insurance on Celo</p>
        </div>

        <div className="text-right">
          {address ? (
            <div>
              <p className="text-xs text-verdant-200">
                {isMiniPay ? "MiniPay" : "Connected"}
              </p>
              <p className="text-xs font-mono">
                {address.slice(0, 6)}…{address.slice(-4)}
              </p>
              {!isMiniPay && (
                <button
                  onClick={() => disconnect()}
                  className="text-xs text-verdant-300 underline mt-0.5"
                >
                  Disconnect
                </button>
              )}
            </div>
          ) : (
            <button
              onClick={() => connect({ connector: injected() })}
              className="bg-white text-verdant-700 text-sm font-semibold px-3 py-1.5 rounded-lg"
            >
              Connect Wallet
            </button>
          )}
        </div>
      </header>

      <div className="max-w-lg mx-auto px-4 py-6">
        {!address ? (
          /* Landing state */
          <div className="text-center py-16 px-4">
            <div className="text-6xl mb-5">🌱</div>
            <h2 className="text-2xl font-bold text-verdant-900 mb-3">
              Protect Your Harvest
            </h2>
            <p className="text-gray-500 text-sm leading-relaxed mb-8 max-w-xs mx-auto">
              Automatic payouts when weather threatens your crops — drought,
              flood, or extreme heat. No claims, no paperwork.
            </p>
            <button
              onClick={() => connect({ connector: injected() })}
              className="bg-verdant-600 hover:bg-verdant-700 text-white font-semibold px-7 py-3.5 rounded-2xl text-sm transition-colors"
            >
              Connect Wallet to Get Started
            </button>

            <div className="mt-10 grid grid-cols-3 gap-4 text-center">
              {[
                { icon: "🌧️", label: "Drought" },
                { icon: "🌊", label: "Flood" },
                { icon: "🌡️", label: "Extreme Heat" },
              ].map(({ icon, label }) => (
                <div key={label} className="bg-white rounded-2xl p-3 shadow-sm">
                  <p className="text-2xl mb-1">{icon}</p>
                  <p className="text-xs font-medium text-gray-600">{label}</p>
                </div>
              ))}
            </div>
          </div>
        ) : (
          <>
            {/* Tab bar */}
            <div className="flex gap-1 bg-gray-100 rounded-xl p-1 mb-6">
              <button
                onClick={() => setTab("policies")}
                className={`flex-1 py-2 text-sm font-medium rounded-lg transition-colors ${
                  tab === "policies"
                    ? "bg-white text-verdant-700 shadow-sm"
                    : "text-gray-500 hover:text-gray-700"
                }`}
              >
                My Policies
                {policyIds && policyIds.length > 0 && (
                  <span className="ml-1.5 bg-verdant-100 text-verdant-700 text-xs px-1.5 py-0.5 rounded-full">
                    {policyIds.length}
                  </span>
                )}
              </button>
              <button
                onClick={() => setTab("register")}
                className={`flex-1 py-2 text-sm font-medium rounded-lg transition-colors ${
                  tab === "register"
                    ? "bg-white text-verdant-700 shadow-sm"
                    : "text-gray-500 hover:text-gray-700"
                }`}
              >
                + Get Coverage
              </button>
            </div>

            {/* Tab content */}
            {tab === "policies" ? (
              <div>
                {!policyIds || policyIds.length === 0 ? (
                  <div className="text-center py-14">
                    <p className="text-gray-400 text-sm mb-5">
                      No active policies yet.
                    </p>
                    <button
                      onClick={() => setTab("register")}
                      className="bg-verdant-600 hover:bg-verdant-700 text-white text-sm font-semibold px-6 py-3 rounded-xl transition-colors"
                    >
                      Register Your First Policy
                    </button>
                  </div>
                ) : (
                  <div className="space-y-4">
                    {(policyIds as `0x${string}`[]).map((id) => (
                      <PolicyCard key={id} policyId={id} />
                    ))}
                  </div>
                )}
              </div>
            ) : (
              <RegisterPolicyForm
                address={address}
                onSuccess={handleRegistered}
              />
            )}
          </>
        )}
      </div>
    </main>
  );
}
