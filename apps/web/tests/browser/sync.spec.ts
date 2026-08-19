import { expect, test, type BrowserContext, type Page } from "@playwright/test";

const accountId = "77777777-7777-4777-8777-777777777777";

test("two tabs preserve an offline mutation through reload, lost acknowledgement, retry and conflict", async ({ context, page }) => {
  let authenticated = false;
  let serverRevision = 0;
  let acknowledged = false;
  let replayConfirmed = false;
  let mutationCalls = 0;
  let resourceId = "";
  let serverMutationId: string | null = null;
  let networkUnavailable = false;
  await mockAuth(context, () => authenticated, () => { authenticated = true; }, () => networkUnavailable);
  await context.route("**/api/v1/sync/**", async (route) => {
    if (networkUnavailable) { await route.abort("failed"); return; }
    const request = route.request();
    const pathname = new URL(request.url()).pathname;
    if (pathname.includes("/clients/")) {
      const body = request.postDataJSON() as { clientId: string };
      await route.fulfill({ json: {
        clientId: body.clientId, displayName: "Browser", protocolVersion: 2,
        isActiveWriter: true, registeredAtUtc: new Date().toISOString(), lastSeenAtUtc: new Date().toISOString(),
      } });
      return;
    }
    if (pathname.includes("/mutations/")) {
      mutationCalls++;
      const mutationId = pathname.split("/").at(-1)!;
      serverMutationId = mutationId;
      const body = request.postDataJSON() as {
        operation: string;
        resources: { resourceId: string }[];
      };
      resourceId = body.resources[0]!.resourceId;
      if (body.operation === "correctDailyCheckIn") {
        await route.fulfill({ status: 409, json: { title: "stale", code: "stale_base_version" } });
      } else if (!acknowledged) {
        acknowledged = true;
        serverRevision = 1;
        await route.abort("failed");
      } else {
        replayConfirmed = true;
        await route.fulfill({ json: { mutationId, replayed: true, revision: 1, resources: [] } });
      }
      return;
    }
    const after = Number(new URL(request.url()).searchParams.get("after") ?? 0);
    await route.fulfill({ json: replayConfirmed && after < serverRevision ? {
      protocolVersion: 2, nextCursor: 1, hasMore: false,
      batches: [{
        batchId: "88888888-8888-4888-8888-888888888888", revision: 1,
        originMutationId: serverMutationId,
        changes: [{
          resourceType: "DailyCheckIn", resourceId, version: 1, isTombstone: false,
          snapshot: {
            checkInId: resourceId, localDate: "2026-08-18",
            values: { weightKg: 80, caloriesKcal: null, proteinGrams: null, carbohydrateGrams: null, fatGrams: null, steps: null, sleepMinutes: null },
            createdAtUtc: "2026-08-18T10:00:00Z", updatedAtUtc: "2026-08-18T10:00:00Z", version: 1,
          },
        }],
      }],
    } : { protocolVersion: 2, nextCursor: after, hasMore: false, batches: [] } });
  });

  await login(page);
  const second = await context.newPage();
  await second.goto("/");
  await expect(second.getByText("sync@example.test")).toBeVisible();

  networkUnavailable = true;
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "onLine", { configurable: true, get: () => false });
  });
  await page.reload();
  await expect(page.getByText(/Offline/).first()).toBeVisible();
  await page.getByRole("button", { name: "Check-in" }).click();
  await page.getByLabel("Kalendertag").fill("2026-08-18");
  await page.getByLabel("Gewicht (kg)", { exact: true }).fill("80");
  await page.getByRole("button", { name: "Check-in speichern" }).click();
  await expect(page.getByText("80 kg")).toBeVisible();
  await page.reload();
  await page.getByRole("button", { name: "Check-in" }).click();
  await expect(page.getByText("80 kg")).toBeVisible();

  networkUnavailable = false;
  await second.evaluate(() => {
    Object.defineProperty(navigator, "onLine", { configurable: true, get: () => true });
    window.dispatchEvent(new Event("online"));
  });
  await expect.poll(() => mutationCalls).toBeGreaterThanOrEqual(1);
  await second.waitForTimeout(1_100);
  await second.getByRole("button", { name: "Erneut synchronisieren" }).click();
  await expect.poll(() => mutationCalls).toBeGreaterThanOrEqual(2);
  await expect.poll(() => outboxCount(second)).toBe(0);
  expect(mutationCalls).toBe(2);

  await second.getByRole("button", { name: "Check-in" }).click();
  await second.getByLabel("Kalendertag").fill("2026-08-18");
  await second.getByLabel("Gewicht (kg)", { exact: true }).fill("81");
  await second.getByRole("button", { name: "Check-in speichern" }).click();
  await second.getByRole("button", { name: "Heute" }).click();
  await expect(second.getByRole("heading", { name: "Konflikte prüfen" })).toBeVisible();
  await second.getByRole("button", { name: "Serverstand übernehmen" }).click();
  await expect.poll(() => storedWeight(second, resourceId)).toBe(80);
});

test("unsupported sync protocol is visible and never removes local data", async ({ context, page }) => {
  let authenticated = false;
  await mockAuth(context, () => authenticated, () => { authenticated = true; });
  await context.route("**/api/v1/sync/clients/**", async (route) => {
    await route.fulfill({ status: 409, json: { title: "upgrade", code: "upgrade_required" } });
  });
  await login(page);
  await expect(page.getByText("Update nötig")).toBeVisible();
});

async function mockAuth(
  context: BrowserContext,
  isAuthenticated: () => boolean,
  authenticate: () => void,
  isUnavailable: () => boolean = () => false,
) {
  await context.route("**/api/v1/auth/**", async (route) => {
    const pathname = new URL(route.request().url()).pathname;
    if (isUnavailable() && pathname.endsWith("/session")) { await route.abort("failed"); return; }
    if (pathname.endsWith("/antiforgery")) await route.fulfill({ json: { requestToken: "sync-token" } });
    else if (pathname.endsWith("/login")) { authenticate(); await route.fulfill({ status: 204 }); }
    else if (pathname.endsWith("/session") && isAuthenticated()) await route.fulfill({ json: {
      userId: accountId, email: "sync@example.test", isAccountOperator: false,
    } });
    else await route.fulfill({ status: 401 });
  });
}

async function login(page: Page) {
  await page.goto("/");
  await page.getByLabel("E-Mail-Adresse").fill("sync@example.test");
  await page.getByLabel("Passwort").fill("correct-password");
  await page.getByRole("button", { name: "Anmelden" }).click();
  await expect(page.getByText("sync@example.test")).toBeVisible();
}

async function outboxCount(page: Page) {
  return page.evaluate(async (name) => new Promise<number>((resolve, reject) => {
    const request = indexedDB.open(name);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const count = request.result.transaction("outbox").objectStore("outbox").count();
      count.onsuccess = () => resolve(count.result);
      count.onerror = () => reject(count.error);
    };
  }), `gainer-account-${accountId}`);
}

async function storedWeight(page: Page, id: string) {
  return page.evaluate(async ({ name, id }) => new Promise<number | undefined>((resolve, reject) => {
    const request = indexedDB.open(name);
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const get = request.result.transaction("checkIns").objectStore("checkIns").get(id);
      get.onsuccess = () => resolve(get.result?.envelope?.workingCopy?.weightKg);
      get.onerror = () => reject(get.error);
    };
  }), { name: `gainer-account-${accountId}`, id });
}
