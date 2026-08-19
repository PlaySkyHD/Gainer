import fs from "node:fs";

const lock = JSON.parse(fs.readFileSync(new URL("../apps/web/package-lock.json", import.meta.url), "utf8"));
const allowed = new Set([
  "(MIT OR CC0-1.0)", "0BSD", "Apache-2.0", "Apache-2.0 AND LGPL-3.0-or-later",
  "Apache-2.0 AND LGPL-3.0-or-later AND MIT", "BSD-2-Clause", "BSD-3-Clause",
  "BlueOak-1.0.0", "CC-BY-4.0", "CC0-1.0", "ISC", "LGPL-3.0-or-later",
  "MIT", "MIT AND ISC", "MPL-2.0", "Python-2.0",
]);
const findings = [];
for (const [path, entry] of Object.entries(lock.packages)) {
  if (!path || !entry.version) continue;
  if (!entry.license) findings.push(`${path}: missing license metadata`);
  else if (!allowed.has(entry.license)) findings.push(`${path}: unapproved license ${entry.license}`);
}
if (findings.length) {
  console.error(findings.join("\n"));
  process.exit(1);
}
console.log(`npm license policy passed for ${Object.keys(lock.packages).length - 1} locked packages.`);
