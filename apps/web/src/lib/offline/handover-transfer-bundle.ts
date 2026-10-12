export const handoverTransferBundleKind = "gainer-sync-handover";
export const handoverTransferBundleVersion = 1;
export const handoverTransferBundleMaxBytes = 16 * 1024;

export function canonicalizeApiOrigin(value: string): string {
  try {
    const parsed = new URL(value);
    if ((parsed.protocol !== "https:" && parsed.protocol !== "http:") || parsed.username || parsed.password) return "";
    return parsed.origin;
  } catch {
    return "";
  }
}

export interface HandoverTransferBundle {
  kind: typeof handoverTransferBundleKind;
  version: typeof handoverTransferBundleVersion;
  accountId: string;
  apiOrigin: string;
  sourceClientId: string;
  handoverId: string;
  oneTimeCode: string;
  frozenRevision: number;
  expiresAtUtc: string;
}

export function createHandoverTransferBundle(input: Omit<HandoverTransferBundle, "kind" | "version">, now = Date.now()): string {
  const validated = validateHandoverTransferBundle({
    kind: handoverTransferBundleKind,
    version: handoverTransferBundleVersion,
    ...input,
  }, input.accountId, input.apiOrigin, now);
  return JSON.stringify(validated);
}

export function parseHandoverTransferBundle(
  encoded: string,
  expectedAccountId: string,
  expectedApiOrigin: string,
  now = Date.now(),
): HandoverTransferBundle {
  if (new TextEncoder().encode(encoded).byteLength > handoverTransferBundleMaxBytes) {
    throw new TypeError("Übergabepaket ist zu groß.");
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(encoded);
  } catch {
    throw new TypeError("Übergabepaket ist kein gültiges JSON.");
  }
  return validateHandoverTransferBundle(parsed, expectedAccountId, expectedApiOrigin, now);
}

function validateHandoverTransferBundle(
  value: unknown,
  expectedAccountId: string,
  expectedApiOrigin: string,
  now: number,
): HandoverTransferBundle {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new TypeError("Ungültiges Übergabepaket.");
  const record = value as Record<string, unknown>;
  const fields = ["kind", "version", "accountId", "apiOrigin", "sourceClientId", "handoverId", "oneTimeCode", "frozenRevision", "expiresAtUtc"];
  if (Object.keys(record).length !== fields.length || fields.some((field) => !(field in record))) {
    throw new TypeError("Ungültiges Übergabepaket.");
  }
  const { accountId, apiOrigin, sourceClientId, handoverId, oneTimeCode, frozenRevision, expiresAtUtc } = record;
  if (record.kind !== handoverTransferBundleKind || record.version !== handoverTransferBundleVersion ||
      typeof accountId !== "string" || !isUuid(accountId) || accountId.toLowerCase() !== expectedAccountId.toLowerCase() ||
      typeof apiOrigin !== "string" || !isCanonicalOrigin(apiOrigin) || apiOrigin !== canonicalOrigin(expectedApiOrigin) ||
      typeof sourceClientId !== "string" || !isUuid(sourceClientId) ||
      typeof handoverId !== "string" || !isUuid(handoverId) ||
      typeof oneTimeCode !== "string" || oneTimeCode.length < 1 || oneTimeCode.length > 128 || oneTimeCode.trim() !== oneTimeCode || /[\u0000-\u001f\u007f]/u.test(oneTimeCode) ||
      !Number.isSafeInteger(frozenRevision) || (frozenRevision as number) < 0 ||
      typeof expiresAtUtc !== "string" || expiresAtUtc.length > 40 || !/(?:Z|\+00:00)$/iu.test(expiresAtUtc)) {
    throw new TypeError("Übergabepaket passt nicht zu diesem Konto oder dieser App.");
  }
  const expiresAt = Date.parse(expiresAtUtc);
  if (!Number.isFinite(expiresAt) || expiresAt <= now || expiresAt - now > 24 * 60 * 60 * 1000) {
    throw new TypeError("Das Übergabepaket ist abgelaufen oder seine Gültigkeitsdauer ist ungültig.");
  }
  return {
    kind: handoverTransferBundleKind,
    version: handoverTransferBundleVersion,
    accountId,
    apiOrigin,
    sourceClientId,
    handoverId,
    oneTimeCode,
    frozenRevision: frozenRevision as number,
    expiresAtUtc,
  };
}

function isCanonicalOrigin(value: string): boolean {
  try {
    const parsed = new URL(value);
    return (parsed.protocol === "https:" || parsed.protocol === "http:") &&
      parsed.origin === value && !parsed.username && !parsed.password;
  } catch {
    return false;
  }
}

function canonicalOrigin(value: string): string {
  return canonicalizeApiOrigin(value);
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/iu.test(value);
}
