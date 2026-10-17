import { expect, test, type Page } from "@playwright/test";

const userId = "99999999-9999-4999-8999-999999999998";

async function mockApi(page: Page) {
  let authenticated = false;
  await page.route("**/api/v1/auth/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith("/antiforgery")) await route.fulfill({ json: { requestToken: "training-token", authenticatedUserId: authenticated ? userId : null } });
    else if (path.endsWith("/login")) { authenticated = true; await route.fulfill({ status: 204 }); }
    else if (path.endsWith("/session") && authenticated) await route.fulfill({ json: {
      userId, email: "training@example.test", isAccountOperator: false,
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
  await page.route("**/api/v1/insights/dashboard**", async (route) => route.fulfill({ status: 503, json: {} }));
}

async function login(page: Page) {
  await page.goto("/");
  await page.getByLabel("E-Mail-Adresse").fill("training@example.test");
  await page.getByLabel("Passwort").fill("correct-password");
  await page.getByRole("button", { name: "Anmelden" }).click();
  await expect(page.getByRole("note")).toHaveText("Training ist in der iPhone-App verfügbar.");
}

test("web app hides training navigation and points to the iPhone app", async ({ page }) => {
  await mockApi(page);
  await login(page);

  await expect(page.getByRole("navigation", { name: "Hauptnavigation" }).getByRole("button")).toHaveText([
    "Heute", "Check-in", "Essen", "Coach",
  ]);
  await expect(page.getByRole("button", { name: "Training", exact: true })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Pläne", exact: true })).toHaveCount(0);

  await page.setViewportSize({ width: 390, height: 844 });
  await expect(page.getByRole("navigation", { name: "Mobile Hauptnavigation" }).getByRole("button")).toHaveText([
    "Heute", "Check-in", "Essen", "Coach",
  ]);
});

test("legacy local training changes are discarded on start and reported", async ({ page }) => {
  await mockApi(page);
  await login(page);
  // The first page's start-up retirement runs before its first sync; wait for that sync so the seed is not swept up.
  await expect(page.getByText("Letzter erfolgreicher Abgleich")).toBeVisible();
  await page.evaluate(async (accountId) => {
    const request = indexedDB.open(`gainer-account-${accountId}`);
    const database = await new Promise<IDBDatabase>((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    const transaction = database.transaction("outbox", "readwrite");
    transaction.objectStore("outbox").add({
      mutationId: "legacy-workout-mutation",
      aggregateKey: "workout:0159d8e1-ec7a-527a-9887-5cb4f70b1c83",
      sequence: 1,
      status: "pending",
      createdAtUtc: "2026-08-18T12:00:00.000Z",
      payload: { operation: "edit", baseVersion: 1, body: {} },
    });
    await new Promise((resolve, reject) => {
      transaction.oncomplete = resolve;
      transaction.onerror = () => reject(transaction.error);
    });
    database.close();
  }, userId);

  await page.reload();
  await expect(page.getByRole("status").filter({ hasText: "wurden verworfen" })).toHaveText(
    "1 nicht synchronisierte Trainingsänderung(en) wurden verworfen. Training wird in der iPhone-App geführt.",
  );
});
