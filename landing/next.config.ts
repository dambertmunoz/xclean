import type { NextConfig } from "next";

const config: NextConfig = {
  experimental: {
    serverActions: { bodySizeLimit: "10mb" } // payment screenshots can be chunky
  }
};

export default config;
