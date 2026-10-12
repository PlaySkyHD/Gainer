import { expect, test, type Page } from "@playwright/test";

type MockSession = {
  userId: string;
  email: string;
  isAccountOperator: boolean;
};

async function mockAccessApi(page: Page, operator: boolean) {
  let authenticated = false;
  let sessionRequests = 0;
  let sessionUnavailable = false;
  let identity = {
    userId: "796b2ab3-ff9c-4339-9455-b423f4722e8c",
    email: "member@example.test",
  };

  await page.route("**/api/v1/auth/**", async (route) => {
    const url = new URL(route.request().url());
    if (url.pathname.endsWith("/antiforgery")) {
      await route.fulfill({ json: { requestToken: "test-antiforgery-token", authenticatedUserId: authenticated ? identity.userId : null } });
      return;
    }

    if (url.pathname.endsWith("/login")) {
      authenticated = true;
      await route.fulfill({ status: 204, headers: { "cache-control": "no-store" } });
      return;
    }

    if (url.pathname.endsWith("/logout")) {
      authenticated = false;
      await route.fulfill({ status: 204, headers: { "cache-control": "no-store" } });
      return;
    }

    if (url.pathname.endsWith("/session")) {
      sessionRequests += 1;
      if (sessionUnavailable) {
        await route.abort("failed");
        return;
      }
      if (!authenticated) {
        await route.fulfill({ status: 401, headers: { "cache-control": "no-store" } });
        return;
      }

      const session: MockSession = {
        ...identity,
        isAccountOperator: operator,
      };
      await route.fulfill({
        json: session,
        headers: { "cache-control": "no-store" },
      });
      return;
    }

    await route.fallback();
  });

  return {
    getSessionRequests: () => sessionRequests,
    setIdentity: (userId: string, email: string) => { identity = { userId, email }; },
    setSessionUnavailable: (unavailable: boolean) => { sessionUnavailable = unavailable; },
  };
}

test("logout removes protected content and a reload cannot restore it from cache", async ({ page }) => {
  const api = await mockAccessApi(page, false);
  await page.goto("/");

  await page.getByLabel("E-Mail-Adresse").fill("member@example.test");
  await page.getByLabel("Passwort").fill("correct-password");
  await page.getByRole("button", { name: "Anmelden" }).click();
  await expect(page.getByRole("heading", { name: "Dein Bereich" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Kontoverwaltung" })).toHaveCount(0);
  await expect.poll(() => page.evaluate(async () => {
    const databases = await indexedDB.databases();
    return databases.map((database) => database.name);
  })).toContain("gainer-account-796b2ab3-ff9c-4339-9455-b423f4722e8c");
  const stores = await page.evaluate(async () => {
    const request = indexedDB.open("gainer-account-796b2ab3-ff9c-4339-9455-b423f4722e8c");
    const database = await new Promise<IDBDatabase>((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    const names = Array.from(database.objectStoreNames);
    database.close();
    return names;
  });
  expect(stores).toEqual(expect.arrayContaining([
    "syncMeta", "outbox", "conflicts", "tombstones", "goals", "checkIns",
    "customExercises", "templates", "rotation", "workouts", "exerciseCatalog", "analyticsCache",
  ]));
  await page.evaluate(async () => {
    const request = indexedDB.open("gainer-account-796b2ab3-ff9c-4339-9455-b423f4722e8c");
    const database = await new Promise<IDBDatabase>((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    const transaction = database.transaction("outbox", "readwrite");
    transaction.objectStore("outbox").add({
      mutationId: "pending-browser-mutation",
      aggregateKey: "goal:one",
      sequence: 1,
      status: "pending",
      createdAtUtc: "2026-08-18T12:00:00.000Z",
      payload: {},
    });
    await new Promise<void>((resolve, reject) => {
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
    });
    database.close();
  });
  const deletionWarnings: string[] = [];
  page.on("dialog", async (dialog) => {
    deletionWarnings.push(dialog.message());
    await dialog.accept();
  });
  await page.getByRole("button", { name: "Lokale Daten löschen" }).click();
  await expect(page.getByText("Die lokalen Kontodaten wurden gelöscht.")).toBeVisible();
  expect(deletionWarnings).toHaveLength(2);
  expect(deletionWarnings[1]).toContain("noch nicht synchronisiert");

  await page.getByRole("button", { name: "Abmelden" }).click();
  await expect(page.getByRole("heading", { name: "Anmelden" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Dein Bereich" })).toHaveCount(0);

  const beforeReload = api.getSessionRequests();
  await page.reload();
  await expect(page.getByRole("heading", { name: "Anmelden" })).toBeVisible();
  await expect.poll(api.getSessionRequests).toBeGreaterThan(beforeReload);
  await expect(page.getByRole("heading", { name: "Dein Bereich" })).toHaveCount(0);
});

test("operator view is separate and creates a manually shareable invitation link", async ({ page }) => {
  await mockAccessApi(page, true);
  await page.route("**/api/v1/account-operator/invitations", async (route) => {
    await route.fulfill({
      status: 201,
      json: {
        activationPath: "/accept-invitation?token=manual-token",
        expiresAt: "2026-08-21T12:00:00Z",
      },
      headers: { "cache-control": "no-store" },
    });
  });
  await page.goto("/");
  await page.getByLabel("E-Mail-Adresse").fill("operator@example.test");
  await page.getByLabel("Passwort").fill("operator-password");
  await page.getByRole("button", { name: "Anmelden" }).click();

  await expect(page.getByRole("heading", { name: "Kontoverwaltung" })).toBeVisible();
  await page.getByLabel("Kollegen einladen").fill("colleague@example.test");
  await page.getByRole("button", { name: "Einladung erstellen" }).click();
  await expect(page.getByLabel("Einladungslink")).toHaveValue(
    "http://127.0.0.1:3100/accept-invitation?token=manual-token",
  );
});

test("source handover retries a lost Begin response with the same request and revision", async ({ page }) => {
  await mockAccessApi(page, false);
  const beginBodies: Array<{ requestId: string; sourceClientId: string; expectedRevision: number }> = [];
  let beginAttempt = 0;
  await page.route("**/api/v1/sync/clients/**", async (route) => {
    const body = route.request().postDataJSON() as { clientId: string };
    await route.fulfill({ json: { clientId: body.clientId, isActiveWriter: true, protocolVersion: 2 } });
  });
  await page.route("**/api/v1/sync/changes?**", async (route) => {
    const after = Number(new URL(route.request().url()).searchParams.get("after") ?? 0);
    await route.fulfill({ json: { protocolVersion: 2, nextCursor: after, hasMore: false, batches: [] } });
  });
  await page.route("**/api/v1/sync/handovers", async (route) => {
    beginBodies.push(route.request().postDataJSON() as typeof beginBodies[number]);
    beginAttempt++;
    if (beginAttempt === 1) {
      await route.abort("failed");
      return;
    }
    await route.fulfill({ status: 201, json: {
      handoverId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      oneTimeCode: "single-use-test-code",
      frozenRevision: beginBodies[1].expectedRevision,
      expiresAtUtc: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
    } });
  });
  await page.goto("/");
  await page.getByLabel("E-Mail-Adresse").fill("member@example.test");
  await page.getByLabel("Passwort").fill("correct-password");
  await page.getByRole("button", { name: "Anmelden" }).click();
  await expect(page.getByRole("heading", { name: "Dein Bereich" })).toBeVisible();

  const handover = page.getByRole("region", { name: "Geräteübergabe" });
  await handover.getByRole("button", { name: "Dieses PWA-Gerät sicher übergeben" }).click();
  await expect(handover.getByRole("alert").getByText("Failed to fetch")).toBeVisible();
  expect(beginBodies).toHaveLength(1);
  await handover.getByRole("button", { name: "Übergabe fortsetzen" }).click();
  await expect(handover.getByRole("button", { name: "Übergabepaket kopieren" })).toBeVisible();
  await expect(handover.getByText(beginBodies[1].sourceClientId)).toBeVisible();
  expect(beginBodies).toHaveLength(2);
  expect(beginBodies[1]).toEqual(beginBodies[0]);
  await page.context().grantPermissions(["clipboard-read", "clipboard-write"], { origin: "http://127.0.0.1:3100" });
  await handover.getByRole("button", { name: "Übergabepaket kopieren" }).click();
  const bundle = await page.evaluate(async () => JSON.parse(await navigator.clipboard.readText()));
  expect(bundle).toMatchObject({
    kind: "gainer-sync-handover",
    version: 1,
    accountId: "796b2ab3-ff9c-4339-9455-b423f4722e8c",
    sourceClientId: beginBodies[1].sourceClientId,
    handoverId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    oneTimeCode: "single-use-test-code",
    frozenRevision: beginBodies[1].expectedRevision,
  });
});

test("account switch keeps A data out of B online and during an offline restart", async ({ page }) => {
  const api = await mockAccessApi(page, false);
  const firstId = "11111111-1111-4111-8111-111111111111";
  const secondId = "22222222-2222-4222-8222-222222222222";
  api.setIdentity(firstId, "first@example.test");
  await page.goto("/");
  await page.getByLabel("E-Mail-Adresse").fill("first@example.test");
  await page.getByLabel("Passwort").fill("first-password");
  await page.getByRole("button", { name: "Anmelden" }).click();
  await expect(page.getByText("first@example.test")).toBeVisible();
  await expect.poll(() => page.evaluate(async (name) =>
    (await indexedDB.databases()).some((entry) => entry.name === name), `gainer-account-${firstId}`)).toBe(true);
  await addGoalMarker(page, `gainer-account-${firstId}`, "first-user-private-goal");

  await page.getByRole("button", { name: "Abmelden" }).click();
  api.setIdentity(secondId, "second@example.test");
  await page.getByLabel("E-Mail-Adresse").fill("second@example.test");
  await page.getByLabel("Passwort").fill("second-password");
  await page.getByRole("button", { name: "Anmelden" }).click();
  await expect(page.getByText("second@example.test")).toBeVisible();
  await expect.poll(() => page.evaluate(async (name) =>
    (await indexedDB.databases()).some((entry) => entry.name === name), `gainer-account-${secondId}`)).toBe(true);
  expect(await countStore(page, `gainer-account-${secondId}`, "goals")).toBe(0);
  expect(await countStore(page, `gainer-account-${firstId}`, "goals")).toBe(1);

  api.setSessionUnavailable(true);
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "onLine", { configurable: true, get: () => false });
  });
  await page.reload();
  await expect(page.getByText("second@example.test · Offline")).toBeVisible();
  await expect(page.getByText("first@example.test")).toHaveCount(0);
  expect(await countStore(page, `gainer-account-${secondId}`, "goals")).toBe(0);
});

test("invitation acceptance uses the token from the static route query", async ({ page }) => {
  let acceptedToken: string | undefined;
  await page.route("**/api/v1/auth/antiforgery", async (route) => {
    await route.fulfill({ json: { requestToken: "test-antiforgery-token" } });
  });
  await page.route("**/api/v1/auth/invitations/accept", async (route) => {
    const payload = route.request().postDataJSON() as { token: string };
    acceptedToken = payload.token;
    await route.fulfill({ status: 204, headers: { "cache-control": "no-store" } });
  });

  await page.goto("/accept-invitation?token=invited-token");
  await page.getByLabel("Neues Passwort").fill("new-password-42!");
  await page.getByRole("button", { name: "Konto aktivieren" }).click();

  await expect(page.getByText("Dein Konto ist aktiviert.")).toBeVisible();
  expect(acceptedToken).toBe("invited-token");
});

async function addGoalMarker(page: Page, databaseName: string, marker: string) {
  await page.evaluate(async ({ databaseName, marker }) => {
    const request = indexedDB.open(databaseName);
    const database = await new Promise<IDBDatabase>((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    const transaction = database.transaction("goals", "readwrite");
    transaction.objectStore("goals").add({
      id: marker,
      envelope: {
        aggregateId: marker,
        serverSnapshot: null,
        workingCopy: { marker },
        serverVersion: null,
        optimisticVersion: 1,
        syncState: "pending",
      },
    });
    await new Promise<void>((resolve, reject) => {
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
    });
    database.close();
  }, { databaseName, marker });
}

async function countStore(page: Page, databaseName: string, storeName: string) {
  return page.evaluate(async ({ databaseName, storeName }) => {
    const request = indexedDB.open(databaseName);
    const database = await new Promise<IDBDatabase>((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    const countRequest = database.transaction(storeName, "readonly").objectStore(storeName).count();
    const count = await new Promise<number>((resolve, reject) => {
      countRequest.onsuccess = () => resolve(countRequest.result);
      countRequest.onerror = () => reject(countRequest.error);
    });
    database.close();
    return count;
  }, { databaseName, storeName });
}
