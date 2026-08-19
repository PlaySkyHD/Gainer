import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests/pwa",
  reporter: [["list"]],
  use: { baseURL: "http://127.0.0.1:3200" },
  webServer: {
    command: "node tests/static-server.mjs",
    url: "http://127.0.0.1:3200",
    reuseExistingServer: false,
  },
  projects: [{ name: "chromium", use: devices["Desktop Chrome"] }],
});
