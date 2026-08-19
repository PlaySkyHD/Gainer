import type { NextConfig } from "next";
import withSerwistInit from "@serwist/next";

const withSerwist = withSerwistInit({
  swSrc: "src/app/sw.ts",
  swDest: "public/sw.js",
  disable: process.env.NODE_ENV !== "production",
  globPublicPatterns: ["**/*.{html,css,js,svg,png,webmanifest,woff2}"],
  additionalPrecacheEntries: [
    { url: "/", revision: "gainer-shell-v1" },
    { url: "/accept-invitation", revision: "gainer-shell-v1" },
    { url: "/manifest.webmanifest", revision: "gainer-shell-v1" },
    { url: "/icon.svg", revision: "gainer-icon-v1" },
    { url: "/maskable-icon.svg", revision: "gainer-icon-v1" },
  ],
});

const nextConfig: NextConfig = {
  output: "export",
  images: {
    unoptimized: true,
  },
};

export default withSerwist(nextConfig);
