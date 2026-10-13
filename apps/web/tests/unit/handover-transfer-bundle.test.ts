import assert from "node:assert/strict";
import { test } from "node:test";
import { createHandoverTransferBundle, parseHandoverTransferBundle } from "../../src/lib/offline/handover-transfer-bundle.ts";

const now = Date.parse("2026-10-12T12:00:00.000Z");
const accountId = "00000000-0000-4000-8000-000000000004";
const sourceClientId = "00000000-0000-4000-8000-000000000005";
const handoverId = "00000000-0000-4000-8000-000000000006";
const apiOrigin = "https://app.gainer.example";

test("creates and parses the shared native/PWA handover bundle", () => {
  const encoded = createHandoverTransferBundle({
    accountId,
    apiOrigin,
    sourceClientId,
    handoverId,
    oneTimeCode: "one-time-secret",
    frozenRevision: 42,
    expiresAtUtc: "2026-10-12T12:15:00.000Z",
  }, now);
  const parsed = parseHandoverTransferBundle(encoded, accountId, apiOrigin, now);

  assert.deepEqual(parsed, {
    kind: "gainer-sync-handover",
    version: 1,
    accountId,
    apiOrigin,
    sourceClientId,
    handoverId,
    oneTimeCode: "one-time-secret",
    frozenRevision: 42,
    expiresAtUtc: "2026-10-12T12:15:00.000Z",
  });
});

test("rejects a different account, API origin, malformed fields or stale expiry", () => {
  const encoded = createHandoverTransferBundle({
    accountId,
    apiOrigin,
    sourceClientId,
    handoverId,
    oneTimeCode: "one-time-secret",
    frozenRevision: 42,
    expiresAtUtc: "2026-10-12T12:15:00.000Z",
  }, now);
  assert.throws(() => parseHandoverTransferBundle(encoded, "00000000-0000-4000-8000-000000000007", apiOrigin, now));
  assert.throws(() => parseHandoverTransferBundle(encoded, accountId, "https://other.gainer.example", now));
  assert.throws(() => parseHandoverTransferBundle(encoded, accountId, apiOrigin, now + 16 * 60 * 1000));
  assert.throws(() => parseHandoverTransferBundle(encoded, accountId, apiOrigin, now - 24 * 60 * 60 * 1000));
});

test("rejects oversized bundles, non-UTC expiry, and unexpected fields", () => {
  assert.throws(() => parseHandoverTransferBundle("x".repeat(16 * 1024 + 1), accountId, apiOrigin, now));
  const encoded = createHandoverTransferBundle({
    accountId,
    apiOrigin,
    sourceClientId,
    handoverId,
    oneTimeCode: "one-time-secret",
    frozenRevision: 42,
    expiresAtUtc: "2026-10-12T12:15:00.000Z",
  }, now);
  const noUtc = JSON.parse(encoded) as Record<string, unknown>;
  noUtc.expiresAtUtc = "2026-10-12T14:15:00+02:00";
  assert.throws(() => parseHandoverTransferBundle(JSON.stringify(noUtc), accountId, apiOrigin, now));
  const extraField = JSON.parse(encoded) as Record<string, unknown>;
  extraField.extra = "ignored?";
  assert.throws(() => parseHandoverTransferBundle(JSON.stringify(extraField), accountId, apiOrigin, now));
});
