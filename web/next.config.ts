import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Standalone output so the build ships to the VPS as a self-contained
  // server (node_modules pruned) — no npm install on the shared box.
  output: "standalone",
};

export default nextConfig;
