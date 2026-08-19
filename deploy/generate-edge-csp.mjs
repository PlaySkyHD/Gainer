import { createHash } from "node:crypto";
import { readdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const placeholder = "__GAINER_INLINE_SCRIPT_HASHES__";
const inlineScriptPattern = /<script\b(?![^>]*\bsrc\s*=)[^>]*>([\s\S]*?)<\/script>/gi;

async function listHtmlFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(entries.map((entry) => {
    const path = resolve(directory, entry.name);
    return entry.isDirectory() ? listHtmlFiles(path) : Promise.resolve(entry.name.endsWith(".html") ? [path] : []);
  }));
  return files.flat();
}

export async function collectInlineScriptHashes(exportDirectory) {
  const htmlFiles = await listHtmlFiles(resolve(exportDirectory));
  if (htmlFiles.length === 0) throw new Error(`No HTML files found in ${exportDirectory}.`);

  const hashes = new Set();
  for (const htmlFile of htmlFiles) {
    const html = await readFile(htmlFile, "utf8");
    for (const match of html.matchAll(inlineScriptPattern)) {
      const content = match[1];
      if (content.length === 0) continue;
      hashes.add(`'sha256-${createHash("sha256").update(content, "utf8").digest("base64")}'`);
    }
  }

  if (hashes.size === 0) throw new Error(`No inline scripts found in ${exportDirectory}; refusing to emit an incomplete CSP.`);
  return [...hashes].sort();
}

export async function generateCaddyfile(exportDirectory, templatePath) {
  const template = await readFile(resolve(templatePath), "utf8");
  const occurrences = template.split(placeholder).length - 1;
  if (occurrences !== 1) throw new Error(`Expected exactly one ${placeholder} placeholder, found ${occurrences}.`);

  const hashes = await collectInlineScriptHashes(exportDirectory);
  const generated = template.replace(placeholder, hashes.join(" "));
  for (const hash of hashes) {
    if (!generated.includes(hash)) throw new Error(`Generated CSP is missing ${hash}.`);
  }
  return { generated, hashCount: hashes.length };
}

async function main() {
  const [exportDirectory, templatePath, outputPath] = process.argv.slice(2);
  if (!exportDirectory || !templatePath || !outputPath) {
    throw new Error("Usage: node generate-edge-csp.mjs <export-directory> <Caddyfile-template> <output-path|--check>");
  }

  const result = await generateCaddyfile(exportDirectory, templatePath);
  if (outputPath !== "--check") await writeFile(resolve(outputPath), result.generated, "utf8");
  process.stdout.write(`Validated ${result.hashCount} inline script CSP hashes.\n`);
}

const invokedDirectly = process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url;
if (invokedDirectly) main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
