# Verdant

**Parametric crop insurance for smallholder farmers, powered by AI and Celo.**

Verdant automatically pays out cUSD to farmers when weather conditions — drought, flood, or extreme heat — cross predefined thresholds. No claims process. No adjuster. No paperwork. An AI agent monitors real-time weather data and triggers on-chain payouts the moment a threshold is breached, directly to the farmer's MiniPay wallet.

---

## The Problem

Over 600 million smallholder farmers have no access to crop insurance. Traditional insurance is economically unviable below a $500 policy value because manual claims verification costs more than the payout. When harvests fail, farmers have no safety net — they spiral into debt or abandon farming entirely.

These farmers have smartphones and mobile money. What they lack is a financial product designed for them.

---

## How It Works

1. **Register a plot** — farmer inputs GPS coordinates and selects a coverage type (drought, flood, heat, dry spell) inside MiniPay
2. **Pay a micro-premium** — starting at 0.50 cUSD/month in cUSD stablecoins
3. **Smart contract locks the policy** — parametric trigger stored on-chain with GPS, event type, and threshold
4. **AI agent monitors daily** — Cloudflare Agents SDK polls Open-Meteo and NASA POWER APIs for the farmer's region
5. **Threshold breached → automatic payout** — agent submits on-chain transaction, cUSD lands in MiniPay wallet with no action from the farmer

---

## Coverage Types

| Event | Trigger | Base Payout |
|---|---|---|
| Drought | Rainfall < 20mm over 30 days | 10–50 cUSD |
| Flood | Rainfall > 200mm over 7 days | 10–50 cUSD |
| Extreme Heat | Avg temp > 38°C over 14 days | 10–30 cUSD |
| Early Dry Spell | < 5mm rain in first 21 days of planting season | 5–20 cUSD |

---

## Architecture

```
MiniPay Frontend (Next.js + viem)
        │
        ▼
Celo Smart Contracts
  PolicyRegistry · PremiumPool · PayoutVault · WeatherOracle
        │
        ▼
Cloudflare Agents SDK (Durable Objects)
  WeatherMonitorAgent · PolicyEvaluatorAgent · PayoutExecutorAgent
        │
        ▼
Cloudflare AI Gateway → Claude (edge case arbitration)
        │
        ▼
Weather APIs: Open-Meteo (primary) · NASA POWER (verification)
```

---

## Smart Contracts

| Contract | Purpose |
|---|---|
| `PolicyRegistry` | Stores all active policies with GPS, trigger conditions, and status. Supports pausable emergency stop. |
| `PremiumPool` | Holds collected premiums and protocol reserve funds. Protected by reentrancy guard. |
| `PayoutVault` | Receives trigger signals from the authorized agent and executes cUSD payouts |
| `WeatherOracle` | Immutable on-chain record of all weather events for auditability |

Contracts are written in Solidity and built with [Foundry](https://book.getfoundry.sh/).

---

## Cloudflare Agent System

**WeatherMonitorAgent** — one Durable Object per geographic region (50km grid). Polls weather APIs daily, stores rolling 90-day history in DO SQLite, emits events to evaluator agents.

**PolicyEvaluatorAgent** — one Durable Object per active policy. Evaluates rolling conditions against the parametric trigger. Escalates ambiguous readings to Claude via AI Gateway for resolution.

**PayoutExecutorAgent** — holds the authorized Celo wallet. Submits `triggerPayout()` on-chain when confirmed. Retries on failure, logs all executions.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Blockchain | Celo L2 |
| Smart Contracts | Solidity 0.8.x · Foundry |
| Frontend | Next.js 14 · viem · wagmi · Tailwind CSS |
| Agent Infrastructure | Cloudflare Agents SDK (Durable Objects) |
| AI Routing | Cloudflare AI Gateway → Claude |
| Weather Data | Open-Meteo · NASA POWER |
| Identity | Self Protocol / Worldcoin |
| Payments | cUSD via MiniPay |

---

## Project Structure

```
verdant/
├── contracts/               # Foundry project
│   ├── src/
│   │   ├── PolicyRegistry.sol
│   │   ├── PremiumPool.sol
│   │   ├── PayoutVault.sol
│   │   └── WeatherOracle.sol
│   ├── test/
│   │   ├── PolicyRegistry.t.sol
│   │   ├── PayoutVault.t.sol
│   │   └── Integration.t.sol
│   ├── script/
│   │   └── Deploy.s.sol
│   └── foundry.toml
├── agent/                   # Cloudflare Workers + Agents SDK
│   ├── src/
│   │   ├── agents/
│   │   │   ├── WeatherMonitorAgent.ts
│   │   │   ├── PolicyEvaluatorAgent.ts
│   │   │   └── PayoutExecutorAgent.ts
│   │   └── index.ts
│   └── wrangler.toml
├── frontend/                # Next.js MiniPay app
│   ├── app/
│   ├── components/
│   └── hooks/
│       └── useMiniPay.ts
└── README.md
```

---

## Getting Started

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js >= 18
- [Wrangler CLI](https://developers.cloudflare.com/workers/wrangler/install-and-update/)

### Contracts

```bash
cd contracts
forge install
forge build
forge test
```

### Deploy to Alfajores (Celo testnet)

```bash
forge script script/Deploy.s.sol \
  --rpc-url https://alfajores-forno.celo-testnet.org \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### Agent

```bash
cd agent
npm install
wrangler dev
```

### Frontend

```bash
cd frontend
npm install
npm run dev
```

For MiniPay testing, tunnel localhost with ngrok:

```bash
ngrok http 3000
```

Then load the HTTPS ngrok URL inside MiniPay.

---

## MiniPay Compatibility

The single required hook for MiniPay compatibility:

```typescript
useEffect(() => {
  if (window.ethereum && window.ethereum.isMiniPay) {
    setIsMiniPay(true);
    connectWallet(); // wallet is auto-injected, no modal needed
  }
}, []);
```

Key constraints:
- Use **viem** or **wagmi** — Ethers.js is incompatible with Celo fee abstraction
- Legacy transactions only — no EIP-1559 (`maxFeePerGas` / `maxPriorityFeePerGas`)
- Fee currency: `USDm` contract address on Celo

---

## Environment Variables

```bash
# contracts/.env
PRIVATE_KEY=
CELO_RPC_URL=https://forno.celo.org

# agent/.env
CELO_PRIVATE_KEY=
CLOUDFLARE_AI_GATEWAY_URL=
CLAUDE_API_KEY=
OPEN_METEO_BASE_URL=https://api.open-meteo.com/v1
NASA_POWER_BASE_URL=https://power.larc.nasa.gov/api

# frontend/.env.local
NEXT_PUBLIC_POLICY_REGISTRY_ADDRESS=
NEXT_PUBLIC_CELO_CHAIN_ID=42220
```

---

## Celo Proof of Ship

Built for [Celo Proof of Ship](https://www.celopg.eco/programs/proof-of-ship) — April 2025.

- MiniPay compatible
- Smart contracts deployed on Celo mainnet
- Humanity verification via Self Protocol
- AI agent executing real on-chain financial transactions

---

## License

MIT
