import {
  syncProtocolVersion,
  SyncHttpError,
  type ClientRegistration,
  type PullResponse,
  type PushResponse,
  type SyncTransport,
} from "../offline/sync-engine.ts";

export class BrowserSyncTransport implements SyncTransport {
  private readonly expectedAccountId: string;

  constructor(expectedAccountId: string) {
    if (!isAccountId(expectedAccountId)) throw new TypeError("A valid expected account ID is required for sync requests.");
    this.expectedAccountId = expectedAccountId;
  }

  async register(clientId: string, takeOverWriting: boolean): Promise<ClientRegistration> {
    return request(`/api/v1/sync/clients/${clientId}`, {
      method: "PUT",
      body: {
        clientId,
        displayName: browserDisplayName(),
        protocolVersion: syncProtocolVersion,
        takeOverWriting,
      },
    }, this.expectedAccountId);
  }

  async push(mutationId: string, body: unknown): Promise<PushResponse> {
    return request(`/api/v1/sync/mutations/${mutationId}`, { method: "PUT", body }, this.expectedAccountId);
  }

  async pull(after: number): Promise<PullResponse> {
    return request(`/api/v1/sync/changes?after=${after}&limit=200`, { method: "GET" }, this.expectedAccountId);
  }
}

async function request<T>(
  path: string,
  options: { method: "GET" | "PUT"; body?: unknown },
  expectedAccountId: string,
): Promise<T> {
  const headers: Record<string, string> = { "X-Gainer-Account-Id": expectedAccountId };
  if (options.body !== undefined) {
    headers["Content-Type"] = "application/json";
    headers["X-CSRF-TOKEN"] = await antiforgeryToken(expectedAccountId);
  }
  const response = await fetch(path, {
    method: options.method,
    credentials: "include",
    cache: "no-store",
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
  if (!response.ok) {
    const problem = await response.json().catch(() => null) as {
      title?: string;
      detail?: string;
      code?: string;
      extensions?: { code?: string };
    } | null;
    const code = String(problem?.code ?? problem?.extensions?.code ?? `http_${response.status}`);
    throw new SyncHttpError(response.status, code, problem?.detail ?? problem?.title ?? "Synchronisation fehlgeschlagen.");
  }
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

function browserDisplayName(): string {
  if (typeof navigator === "undefined") return "Browser";
  const platform = navigator.platform;
  return platform ? `Browser · ${platform}`.slice(0, 100) : "Browser";
}
