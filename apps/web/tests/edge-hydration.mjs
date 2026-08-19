import { chromium, devices } from "playwright";

const baseUrl = process.env.EDGE_BASE_URL ?? "http://127.0.0.1:18081";
const browser = await chromium.launch({ headless: true });

try {
  for (const profile of [
    { name: "desktop", options: {} },
    { name: "mobile", options: devices["iPhone 13"] },
  ]) {
    const context = await browser.newContext(profile.options);
    const page = await context.newPage();
    const failures = [];
    page.on("pageerror", (error) => failures.push(`page error: ${error.message}`));
    page.on("console", (message) => {
      if (message.type() === "error" && message.text().includes("Content Security Policy")) {
        failures.push(`CSP error: ${message.text()}`);
      }
    });

    const response = await page.goto(baseUrl, { waitUntil: "domcontentloaded" });
    if (!response?.ok()) failures.push(`document returned HTTP ${response?.status() ?? "unknown"}`);
    await page.getByRole("heading", { name: "Anmelden" }).waitFor({ state: "visible" });
    await page.waitForTimeout(250);

    await context.close();
    if (failures.length > 0) throw new Error(`${profile.name}:\n${failures.join("\n")}`);
    process.stdout.write(`Edge hydration succeeded for ${profile.name} at ${baseUrl}.\n`);
  }
} finally {
  await browser.close();
}
