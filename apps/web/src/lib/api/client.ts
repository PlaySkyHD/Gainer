import type { components } from "./generated";

export type Session = components["schemas"]["SessionResponse"];
export type AccountSummary = components["schemas"]["AccountSummaryResponse"];
export type Invitation = components["schemas"]["InvitationResponse"];
export type DashboardInsights = components["schemas"]["DashboardInsightsResponse"];
export type ExerciseProgress = components["schemas"]["ExerciseProgressResponse"];
export type CoachAnswer = components["schemas"]["CoachResponse"];

async function readError(response: Response): Promise<Error> {
  const problem = (await response.json().catch(() => null)) as components["schemas"]["ProblemDetails"] | null;
  return new Error(problem?.detail ?? problem?.title ?? "Die Anfrage ist fehlgeschlagen.");
}

async function readJson<T>(response: Response): Promise<T> {
  if (!response.ok) throw await readError(response);
  return (await response.json()) as T;
}

async function antiforgeryToken(): Promise<string> {
  const response = await fetch("/api/v1/auth/antiforgery", { credentials: "include", cache: "no-store" });
  const body = await readJson<components["schemas"]["AntiforgeryTokenResponse"]>(response);
  return body.requestToken;
}

async function mutate(path: string, method: "POST" | "PUT", body?: unknown): Promise<Response> {
  const token = await antiforgeryToken();
  const response = await fetch(path, {
    method,
    credentials: "include",
    cache: "no-store",
    headers: { "Content-Type": "application/json", "X-CSRF-TOKEN": token },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!response.ok) throw await readError(response);
  return response;
}

export async function getSession(): Promise<Session | null> {
  const response = await fetch("/api/v1/auth/session", { credentials: "include", cache: "no-store" });
  if (response.status === 401) return null;
  return readJson<Session>(response);
}

export async function login(email: string, password: string): Promise<Session> {
  await mutate("/api/v1/auth/login", "POST", { email, password });
  const session = await getSession();
  if (!session) throw new Error("Die Anmeldung konnte nicht bestätigt werden.");
  return session;
}

export async function logout(): Promise<void> {
  await mutate("/api/v1/auth/logout", "POST");
}

export async function listAccounts(): Promise<AccountSummary[]> {
  const response = await fetch("/api/v1/account-operator/accounts", { credentials: "include", cache: "no-store" });
  return readJson<AccountSummary[]>(response);
}

export async function createInvitation(email: string): Promise<Invitation> {
  const response = await mutate("/api/v1/account-operator/invitations", "POST", { email });
  return (await response.json()) as Invitation;
}

export async function setAccountStatus(accountId: string, isActive: boolean): Promise<void> {
  await mutate(`/api/v1/account-operator/accounts/${accountId}/status`, "PUT", { isActive });
}

export async function acceptInvitation(token: string, password: string): Promise<void> {
  await mutate("/api/v1/auth/invitations/accept", "POST", { token, password });
}

export async function getDashboardInsights(days = 30): Promise<DashboardInsights> {
  const response = await fetch(`/api/v1/insights/dashboard?days=${days}`, {
    credentials: "include", cache: "no-store",
  });
  return readJson<DashboardInsights>(response);
}

export async function getExerciseProgress(
  exerciseId: string,
  window: "7" | "30" | "90" | "all",
): Promise<ExerciseProgress> {
  const zone = Intl.DateTimeFormat().resolvedOptions().timeZone || "Europe/Berlin";
  const response = await fetch(
    `/api/v1/insights/exercises/${exerciseId}/progress?window=${window}&timeZone=${encodeURIComponent(zone)}`,
    { credentials: "include", cache: "no-store" },
  );
  return readJson<ExerciseProgress>(response);
}

export async function askCoach(question: string): Promise<CoachAnswer> {
  const response = await mutate("/api/v1/coach/responses", "POST", { question });
  return (await response.json()) as CoachAnswer;
}
