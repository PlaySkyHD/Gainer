import {
  syncProtocolVersion,
  SyncHttpError,
  type ClientRegistration,
  type PullResponse,
  type PushResponse,
  type SyncTransport,
} from "../offline/sync-engine.ts";

export class BrowserSyncTransport implements SyncTransport {
  async register(clientId: string, takeOverWriting: boolean): Promise<ClientRegistration> {
    return request(`/api/v1/sync/clients/${clientId}`, {
      method: "PUT",
      body: {
        clientId,
        displayName: browserDisplayName(),
        protocolVersion: syncProtocolVersion,
        takeOverWriting,
      },
    });
  }

  async push(mutationId: string, body: unknown): Promise<PushResponse> {
    return request(`/api/v1/sync/mutations/${mutationId}`, { method: "PUT", body });
  }

  async pull(after: number): Promise<PullResponse> {
    return request(`/api/v1/sync/changes?after=${after}&limit=200`, { method: "GET" });
  }
}

async function request<T>(
  path: string,
  options: { method: "GET" | "PUT"; body?: unknown },
): Promise<T> {
  const headers: Record<string, string> = {};
  if (options.body !== undefined) {
    headers["Content-Type"] = "application/json";
    headers["X-CSRF-TOKEN"] = await antiforgeryToken();
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

async function antiforgeryToken(): Promise<string> {
  const response = await fetch("/api/v1/auth/antiforgery", {
    credentials: "include",
    cache: "no-store",
  });
  if (!response.ok) throw new SyncHttpError(response.status, `http_${response.status}`, "CSRF-Token konnte nicht geladen werden.");
  const body = await response.json() as { requestToken: string };
  return body.requestToken;
}

function browserDisplayName(): string {
  if (typeof navigator === "undefined") return "Browser";
  const platform = navigator.platform;
  return platform ? `Browser · ${platform}`.slice(0, 100) : "Browser";
}
