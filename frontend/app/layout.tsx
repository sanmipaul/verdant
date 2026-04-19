import type { Metadata } from "next";
import "./globals.css";
import { Providers } from "./providers";

export const metadata: Metadata = {
  title: "Verdant — Parametric Crop Insurance",
  description:
    "Automatic crop insurance payouts for smallholder farmers on Celo. No claims, no paperwork.",
  other: {
    "talentapp:project_verification":
      "87ad29b485bbabd3484e11578ecac5f77a8ba9ec9c894a0df30a23ce6536f27b826731bf72a75060dd8d6a3a1a40ebfb7b3c2d1d0a98f1925dba1374b71ad576",
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="font-sans antialiased">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
