import { spawnSync } from "node:child_process";

const npmCli = process.env.npm_execpath;
if (!npmCli) throw new Error("npm_execpath is not available.");
const build = spawnSync(process.execPath, [npmCli, "run", "build"], { stdio: "inherit" });
if (build.status !== 0) process.exit(build.status ?? 1);

const tests = spawnSync(process.execPath, ["node_modules/@playwright/test/cli.js", "test", "--config", "playwright.pwa.config.ts"], {
  stdio: "inherit",
});
process.exit(tests.status ?? 1);
