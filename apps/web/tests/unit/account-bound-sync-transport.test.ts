import assert from "node:assert/strict";
import { test } from "node:test";
import { BrowserSyncHandoverTransport } from "../../src/lib/api/sync-handover-transport.ts";
import { BrowserSyncTransport } from "../../src/lib/api/sync-transport.ts";
import { SyncHttpError } from "../../src/lib/offline/sync-engine.ts";

const accountA = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const accountB = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

test("sync transport refuses a token bootstrap for another profile before sending a write", async () => {
  const originalFetch = globalThis.fetch;
  const calls: string[] = [];
  globalThis.fetch = (async (input: RequestInfo | URL) => {
    const path = String(input);
    calls.push(path);
    return Response.json({ requestToken: "token-b", authenticatedUserId: accountB });
  }) as typeof fetch;
  try {
    await assert.rejects(
      new BrowserSyncTransport(accountA).register(crypto.randomUUID(), false),
      (error: unknown) => error instanceof SyncHttpError && error.code === "account_changed",
    );
    assert.deepEqual(calls, ["/api/v1/auth/antiforgery"]);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("handover transport refuses a token bootstrap for another profile before begin", async () => {
  const originalFetch = globalThis.fetch;
  const calls: string[] = [];
  globalThis.fetch = (async (input: RequestInfo | URL) => {
    calls.push(String(input));
    return Response.json({ requestToken: "token-b", authenticatedUserId: accountB });
  }) as typeof fetch;
  try {
    await assert.rejects(
      new BrowserSyncHandoverTransport(accountA).begin({
        requestId: crypto.randomUUID(),
        sourceClientId: crypto.randomUUID(),
        expectedRevision: 0,
      }),
      (error: unknown) => error instanceof SyncHttpError && error.code === "account_changed",
    );
    assert.deepEqual(calls, ["/api/v1/auth/antiforgery"]);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("older API token bootstrap without identity metadata requires an API upgrade", async () => {
  const originalFetch = globalThis.fetch;
  const calls: string[] = [];
  globalThis.fetch = (async (input: RequestInfo | URL) => {
    calls.push(String(input));
    return Response.json({ requestToken: "legacy-token" });
  }) as typeof fetch;
  try {
    await assert.rejects(
      new BrowserSyncTransport(accountA).register(crypto.randomUUID(), false),
      (error: unknown) => error instanceof SyncHttpError && error.code === "api_upgrade_required",
    );
    assert.deepEqual(calls, ["/api/v1/auth/antiforgery"]);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("scoped sync reads and writes carry the expected account header", async () => {
  const originalFetch = globalThis.fetch;
  const calls: Array<{ path: string; method: string; headers: Headers }> = [];
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const path = String(input);
    const headers = new Headers(init?.headers);
    if (path === "/api/v1/auth/antiforgery") {
      return Response.json({ requestToken: "token-a", authenticatedUserId: accountA });
    }
    calls.push({ path, method: init?.method ?? "GET", headers });
    return Response.json({});
  }) as typeof fetch;
  try {
    const transport = new BrowserSyncTransport(accountA);
    await transport.register(crypto.randomUUID(), false);
    await transport.push(crypto.randomUUID(), {});
    await transport.pull(0);

    assert.deepEqual(calls.map((call) => call.method), ["PUT", "PUT", "GET"]);
    for (const call of calls) {
      assert.equal(call.headers.get("X-Gainer-Account-Id"), accountA);
    }
    assert.equal(calls[0]?.headers.get("X-CSRF-TOKEN"), "token-a");
    assert.equal(calls[2]?.headers.get("X-CSRF-TOKEN"), null);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("all handover writes carry the expected account header", async () => {
  const originalFetch = globalThis.fetch;
  const calls: Array<{ path: string; headers: Headers }> = [];
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const path = String(input);
    if (path === "/api/v1/auth/antiforgery") {
      return Response.json({ requestToken: "token-a", authenticatedUserId: accountA });
    }
    const headers = new Headers(init?.headers);
    calls.push({ path, headers });
    return path.endsWith("/cancel")
      ? new Response(null, { status: 204 })
      : Response.json({});
  }) as typeof fetch;
  try {
    const transport = new BrowserSyncHandoverTransport(accountA);
    const handoverId = crypto.randomUUID();
    await transport.begin({
      requestId: crypto.randomUUID(),
      sourceClientId: crypto.randomUUID(),
      expectedRevision: 0,
    });
    await transport.complete(handoverId, {
      oneTimeCode: "test-code",
      targetClientId: crypto.randomUUID(),
      caughtUpRevision: 0,
    });
    await transport.cancel(handoverId, crypto.randomUUID());

    assert.equal(calls.length, 3);
    for (const call of calls) {
      assert.equal(call.headers.get("X-Gainer-Account-Id"), accountA);
      assert.equal(call.headers.get("X-CSRF-TOKEN"), "token-a");
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("scoped transports require a UUID account identifier", () => {
  assert.throws(() => new BrowserSyncTransport("not-a-uuid"), TypeError);
  assert.throws(() => new BrowserSyncHandoverTransport("not-a-uuid"), TypeError);
});
