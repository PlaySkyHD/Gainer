import { expect, test } from "@playwright/test";

test("static export starts offline and never puts personal API responses in service-worker caches", async ({ page }) => {
  await page.goto("/");
  await page.evaluate(() => navigator.serviceWorker.ready);
  await page.reload();
  await expect.poll(() => page.evaluate(() => Boolean(navigator.serviceWorker.controller))).toBe(true);
  await page.getByLabel("E-Mail-Adresse").fill("private-pwa-user@example.test");
  await page.getByLabel("Passwort").fill("correct-password");
  await page.getByRole("button", { name: "Anmelden" }).click();
  await expect(page.getByText("private-pwa-user@example.test")).toBeVisible();

  const cacheAudit = await page.evaluate(async () => {
    const urls: string[] = [];
    const bodies: string[] = [];
    for (const cacheName of await caches.keys()) {
      const cache = await caches.open(cacheName);
      for (const request of await cache.keys()) {
        urls.push(request.url);
        const response = await cache.match(request);
        if (response) bodies.push(await response.clone().text());
      }
    }
    return { urls, bodies };
  });
  expect(cacheAudit.urls.some((url) => new URL(url).pathname.startsWith("/api/"))).toBe(false);
  expect(cacheAudit.bodies.some((body) => body.includes("private-pwa-user@example.test"))).toBe(false);

  await page.context().setOffline(true);
  await page.reload({ waitUntil: "domcontentloaded" });
  await expect(page.getByText("private-pwa-user@example.test · Offline")).toBeVisible();
  await expect(page.getByRole("status").filter({ hasText: "Offline" })).toBeVisible();
});
