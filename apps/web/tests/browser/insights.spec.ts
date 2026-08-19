import { expect, test } from "@playwright/test";

test("dashboard and exercise progress cache deterministic server insights for offline use without coach dependency", async ({ page }) => {
  let authenticated = false;
  let unavailable = false;
  let coachCalls = 0;
  await page.route("**/api/v1/auth/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith("/antiforgery")) await route.fulfill({ json: { requestToken: "insight-token" } });
    else if (path.endsWith("/login")) { authenticated = true; await route.fulfill({ status: 204 }); }
    else if (path.endsWith("/session") && unavailable) await route.abort("failed");
    else if (path.endsWith("/session") && authenticated) await route.fulfill({ json: {
      userId: "99999999-9999-4999-8999-999999999999", email: "insights@example.test", isAccountOperator: false,
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
  await page.route("**/api/v1/coach/**", async (route) => { coachCalls++; await route.fulfill({ status: 503 }); });
  await page.route("**/api/v1/insights/dashboard**", async (route) => {
    if (unavailable) { await route.abort("failed"); return; }
    await route.fulfill({ json: dashboardResponse() });
  });
  await page.route("**/api/v1/insights/exercises/**", async (route) => {
    if (unavailable) { await route.abort("failed"); return; }
    const exerciseId = new URL(route.request().url()).pathname.split("/").at(-2)!;
    await route.fulfill({ json: {
      asOfRevision: 12, exerciseId, windowDays: 30,
      fromUtc: "2026-07-20T00:00:00Z", throughUtc: "2026-08-18T23:59:59Z",
      points: [{ workoutId: crypto.randomUUID(), completedAtUtc: "2026-08-18T18:00:00Z", volumeKgRepetitions: 2400, bestWeightKg: 100, bestRepetitions: 8, estimatedOneRepMaxKg: 126.67 }],
      bestSet: null,
    } });
  });

  await page.goto("/");
  await page.getByLabel("E-Mail-Adresse").fill("insights@example.test");
  await page.getByLabel("Passwort").fill("correct-password");
  await page.getByRole("button", { name: "Anmelden" }).click();
  await expect(page.getByText("81,2 kg")).toBeVisible();
  await expect(page.getByText("2.500 kcal")).toBeVisible();
  await expect(page.getByLabel("Gewichtsverlauf").locator("svg")).toBeVisible();
  await expect(page.getByText("Revision 12")).toBeVisible();
  expect(coachCalls).toBe(0);

  unavailable = true;
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "onLine", { configurable: true, get: () => false });
  });
  await page.reload();
  await expect(page.getByText("Offline gespeicherter Stand – möglicherweise veraltet.")).toBeVisible();
  await expect(page.getByText("81,2 kg")).toBeVisible();
  expect(coachCalls).toBe(0);
});

function dashboardResponse() {
  return {
    asOfRevision: 12, from: "2026-07-20", through: "2026-08-18",
    activeGoal: { goalId: crypto.randomUUID(), kind: "Bulk", startWeightKg: 78, targetWeightKg: 85, startDate: "2026-07-01", targetDate: null },
    latestWeight: { date: "2026-08-18", weightKg: 81.2 },
    weightSeries: [{ date: "2026-08-17", weightKg: 81 }, { date: "2026-08-18", weightKg: 81.2 }],
    sevenDayWeight: { averageAlgorithmVersion: "weight-average-v1", trendAlgorithmVersion: "weight-trend-ols-v1", unit: "kg", from: "2026-08-12", through: "2026-08-18", expectedDays: 7, observedDays: 2, coverage: 0.2857, averageKg: 81.1, trendKgPerWeek: null },
    weight: { averageAlgorithmVersion: "weight-average-v1", trendAlgorithmVersion: "weight-trend-ols-v1", unit: "kg", from: "2026-07-20", through: "2026-08-18", expectedDays: 30, observedDays: 2, coverage: 0.0667, averageKg: 81.1, trendKgPerWeek: null },
    nutrition: { algorithmVersion: "nutrition-average-v1", expectedDays: 30, observedDays: 2, coverage: 0.0667, caloriesKcal: { value: 2500, observedDays: 2 }, proteinGrams: { value: 180, observedDays: 2 }, carbohydrateGrams: { value: 300, observedDays: 2 }, fatGrams: { value: 70, observedDays: 2 } },
    training: { volumeAlgorithmVersion: "training-volume-v1", estimatedOneRepMaxAlgorithmVersion: "e1rm-epley-v1", volumeUnit: "kg·repetitions", workoutCount: 3, volumeKgRepetitions: 12345, bestSet: null },
    workoutsLast7Days: 2,
  };
}
