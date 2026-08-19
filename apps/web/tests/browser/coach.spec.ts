import { expect, test } from "@playwright/test";

test("online-only coach retries provider failure and renders server evidence without blocking offline tracking", async ({ page }) => {
  let authenticated = false;
  let failOnce = true;
  let csrfSeen = false;
  await page.route("**/api/v1/auth/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith("/antiforgery")) await route.fulfill({ json: { requestToken: "coach-token" } });
    else if (path.endsWith("/login")) { authenticated = true; await route.fulfill({ status: 204 }); }
    else if (path.endsWith("/session") && authenticated) await route.fulfill({ json: {
      userId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", email: "coach@example.test", isAccountOperator: false,
    } });
    else await route.fulfill({ status: 401 });
  });
  await page.route("**/api/v1/sync/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.includes("clients")) {
      const body = route.request().postDataJSON() as { clientId: string };
      await route.fulfill({ json: { clientId: body.clientId, isActiveWriter: true } });
    } else await route.fulfill({ json: { protocolVersion: 2, nextCursor: 0, hasMore: false, batches: [] } });
  });
  await page.route("**/api/v1/insights/**", (route) => route.fulfill({ status: 503, json: { title: "offline test" } }));
  await page.route("**/api/v1/coach/responses", async (route) => {
    csrfSeen = route.request().headers()["x-csrf-token"] === "coach-token";
    if (failOnce) { failOnce = false; await route.fulfill({ status: 503, json: { title: "Provider vorübergehend nicht verfügbar" } }); return; }
    await route.fulfill({ json: {
      summary: "Dein Gewicht ist im betrachteten Zeitraum stabil.",
      observations: [{ text: "Das 30-Tage-Mittel beträgt 80 kg.", factIds: ["fact-weight"] }],
      facts: [{ factId: "fact-weight", kind: "weight", label: "Average weight", numericValue: 80, textValue: null, unit: "kg", period: "last 30 days", algorithmVersion: "weight-average-v1" }],
      dataGaps: ["Nur wenige Ernährungstage vorhanden."],
      suggestions: ["Beobachte den Verlauf weiter."],
      asOfRevision: 4,
    } });
  });

  await page.goto("/");
  await page.getByLabel("E-Mail-Adresse").fill("coach@example.test");
  await page.getByLabel("Passwort").fill("correct-password");
  await page.getByRole("button", { name: "Anmelden" }).click();
  await page.getByRole("button", { name: "Coach" }).click();
  await page.getByLabel("Frage an den Coach").fill("Wie läuft mein Fortschritt?");
  await page.getByRole("button", { name: "Fragen" }).click();
  await expect(page.getByRole("alert").filter({ hasText: "Provider" })).toBeVisible();
  await page.getByRole("button", { name: "Erneut versuchen" }).click();
  await expect(page.getByText("Dein Gewicht ist im betrachteten Zeitraum stabil.")).toBeVisible();
  await expect(page.getByText("80 kg", { exact: true })).toBeVisible();
  await expect(page.getByText("weight-average-v1")).toBeVisible();
  expect(csrfSeen).toBe(true);

  await page.evaluate(() => {
    Object.defineProperty(navigator, "onLine", { configurable: true, get: () => false });
    window.dispatchEvent(new Event("offline"));
  });
  await expect(page.getByText("Der Coach ist offline nicht verfügbar.", { exact: false })).toBeVisible();
  await expect(page.getByRole("button", { name: "Fragen" })).toBeDisabled();
  await page.getByRole("button", { name: "Check-in" }).click();
  await expect(page.getByRole("heading", { name: "Daily Check-in" })).toBeVisible();
});
