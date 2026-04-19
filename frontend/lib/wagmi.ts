import { createConfig, http } from "wagmi";
import { celo, celoAlfajores } from "viem/chains";
import { injected } from "wagmi/connectors";

export const wagmiConfig = createConfig({
  chains: [celo, celoAlfajores],
  connectors: [injected()],
  transports: {
    [celo.id]: http(),
    [celoAlfajores.id]: http(),
  },
});
