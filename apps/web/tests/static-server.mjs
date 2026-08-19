import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, resolve, sep } from "node:path";

const root = resolve("out");
const port = Number(process.env.PORT ?? 3200);
const contentTypes = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".ico": "image/x-icon",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".webmanifest": "application/manifest+json; charset=utf-8",
  ".woff2": "font/woff2",
};

const server = createServer(async (request, response) => {
  try {
    const pathname = decodeURIComponent(new URL(request.url ?? "/", `http://${request.headers.host}`).pathname);
    if (pathname.startsWith("/api/")) {
      serveTestApi(request, response, pathname);
      return;
    }
    const relative = pathname === "/" ? "index.html" : pathname.replace(/^\//, "");
    let file = resolve(root, relative);
    if (file !== root && !file.startsWith(`${root}${sep}`)) throw new Error("Invalid path");
    if (!(await exists(file)) && !extname(file)) file = `${file}.html`;
    const body = await readFile(file);
    response.writeHead(200, {
      "Content-Type": contentTypes[extname(file)] ?? "application/octet-stream",
      "Cache-Control": "no-store",
    });
    response.end(body);
  } catch {
    response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" });
    response.end("Not found");
  }
});

server.listen(port, "127.0.0.1");

async function exists(path) {
  try {
    return (await stat(path)).isFile();
  } catch {
    return false;
  }
}

function serveTestApi(request, response, pathname) {
  const headers = { "Cache-Control": "no-store" };
  if (pathname.endsWith("/antiforgery")) {
    response.writeHead(200, { ...headers, "Content-Type": "application/json" });
    response.end(JSON.stringify({ requestToken: "pwa-test-token" }));
  } else if (pathname.endsWith("/login") && request.method === "POST") {
    response.writeHead(204, { ...headers, "Set-Cookie": "pwa-auth=1; Path=/; SameSite=Lax" });
    response.end();
  } else if (pathname.endsWith("/session") && request.headers.cookie?.includes("pwa-auth=1")) {
    response.writeHead(200, { ...headers, "Content-Type": "application/json" });
    response.end(JSON.stringify({
      userId: "33333333-3333-4333-8333-333333333333",
      email: "private-pwa-user@example.test",
      isAccountOperator: false,
    }));
  } else {
    response.writeHead(401, headers);
    response.end();
  }
}
