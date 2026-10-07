import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // next dev otherwise writes AGENTS.md / CLAUDE.md into the project
  agentRules: false,
  // one folder with server.js and only the packages it needs, for deploying
  output: "standalone",
};

export default nextConfig;
