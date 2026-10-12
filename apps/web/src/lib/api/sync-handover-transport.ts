import { SyncHttpError } from "../offline/sync-engine.ts";

export interface BeginHandoverRequest {
  requestId: string;
  sourceClientId: string;
  expectedRevision: number;
}

export interface BeginHandoverResponse {
  handoverId: string;
  oneTimeCode: string;
  frozenRevision: number;
  expiresAtUtc: string;
}

export interface CompleteHandoverRequest {
  oneTimeCode: string;
  targetClientId: string;
  caughtUpRevision: number;
}

export interface CompleteHandoverResponse {
  handoverId: string;
  targetClientId: string;
  frozenRevision: number;
  isActiveWriter: boolean;
  completedAtUtc: string;
}

export interface SyncHandoverTransport {
  begin(request: BeginHandoverRequest): Promise<BeginHandoverResponse>;
  complete(handoverId: string, request: CompleteHandoverRequest): Promise<CompleteHandoverResponse>;
  cancel(handoverId: string, sourceClientId: string): Promise<void>;
}

export class BrowserSyncHandoverTransport implements SyncHandoverTransport {
  private readonly expectedAccountId: string;

  constructor(expectedAccountId: string) {
    if (!isAccountId(expectedAccountId)) throw new TypeError("A valid expected account ID is required for handover requests.");
    this.expectedAccountId = expectedAccountId;
  }

  begin(request: BeginHandoverRequest): Promise<BeginHandoverResponse> {
    return send("/api/v1/sync/handovers", "POST", request, this.expectedAccountId);
  }

  complete(handoverId: string, request: CompleteHandoverRequest): Promise<CompleteHandoverResponse> {
    return send(`/api/v1/sync/handovers/${encodeURIComponent(handoverId)}/complete`, "POST", request, this.expectedAccountId);
  }

  async cancel(handoverId: string, sourceClientId: string): Promise<void> {
    await send<void>(`/api/v1/sync/handovers/${encodeURIComponent(handoverId)}/cancel`, "POST", { sourceClientId }, this.expectedAccountId);
  }
}

async function send<T>(path: string, method: "POST", body: unknown, expectedAccountId: string): Promise<T> {
  const response = await fetch(path, {
    method,
    credentials: "include",
    cache: "no-store",
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-TOKEN": await antiforgeryToken(expectedAccountId),
      "X-Gainer-Account-Id": expectedAccountId,
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    const problem = await response.json().catch(() => null) as { title?: string; detail?: string; code?: string } | null;
    throw new SyncHttpError(
      response.status,
      problem?.code ?? `http_${response.status}`,
      problem?.detail ?? problem?.title ?? "Geräteübergabe fehlgeschlagen.",
    );
  }
  if (response.status === 204) return undefined as T;
  return await response.json() as T;
}

function isAccountId(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

async function antiforgeryToken(expectedAccountId: string): Promise<string> {
  const response = await fetch("/api/v1/auth/antiforgery", {
    credentials: "include",
    cache: "no-store",
  });
  if (!response.ok) throw new SyncHttpError(response.status, `http_${response.status}`, "CSRF-Token konnte nicht geladen werden.");
  const body = await response.json() as { requestToken: string; authenticatedUserId?: string | null };
  if (typeof body.authenticatedUserId !== "string") {
    throw new SyncHttpError(426, "api_upgrade_required", "Die angemeldete Kontoidentität stimmt nicht mit dem lokalen Synchronisationsprofil überein. Bitte aktualisiere die App und melde dich erneut an.");
  }
  if (body.authenticatedUserId.toLowerCase() !== expectedAccountId.toLowerCase()) {
    throw new SyncHttpError(409, "account_changed", "Das angemeldete Konto hat sich geändert. Deine lokalen Änderungen bleiben erhalten; melde dich mit dem passenden Konto an.");
  }
  return body.requestToken;
}
