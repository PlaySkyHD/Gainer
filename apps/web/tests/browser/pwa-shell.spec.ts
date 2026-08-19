import { expect, test } from "@playwright/test";

test("exposes install metadata and dedicated application icons", async ({ page, request }) => {
  await page.goto("/");

  await expect(page.locator('link[rel="manifest"]')).toHaveAttribute("href", "/manifest.webmanifest");
  await expect(page.locator('meta[name="theme-color"][media="(prefers-color-scheme: light)"]')).toHaveAttribute("content", "#f2f2f7");
  await expect(page.locator('meta[name="theme-color"][media="(prefers-color-scheme: dark)"]')).toHaveAttribute("content", "#000000");

  const manifestResponse = await request.get("/manifest.webmanifest");
  expect(manifestResponse.ok()).toBeTruthy();
  const manifest = await manifestResponse.json();
  expect(manifest).toMatchObject({
    name: "Gainer – Training & Fortschritt",
    short_name: "Gainer",
    display: "standalone",
    start_url: "/",
  });
  expect(manifest.icons).toEqual(
    expect.arrayContaining([
      expect.objectContaining({ src: "/icon.svg", purpose: "any" }),
      expect.objectContaining({ src: "/maskable-icon.svg", purpose: "maskable" }),
    ]),
  );
  expect((await request.get("/icon.svg")).ok()).toBeTruthy();
  expect((await request.get("/maskable-icon.svg")).ok()).toBeTruthy();
});

test("creates one stable random installation id without personal data", async ({ page }) => {
  await page.goto("/");

  await expect.poll(() => page.evaluate(async () => {
    const database = (await indexedDB.databases()).find((entry) => entry.name === "gainer-local-profiles");
    return database?.version ?? 0;
  })).toBeGreaterThan(0);

  const readInstallationId = () => page.evaluate(async () => {
    const request = indexedDB.open("gainer-local-profiles");
    const database = await new Promise<IDBDatabase>((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    const get = database.transaction("metadata", "readonly").objectStore("metadata").get("installation-id");
    const value = await new Promise<string>((resolve, reject) => {
      get.onsuccess = () => resolve((get.result as { value: string }).value);
      get.onerror = () => reject(get.error);
    });
    database.close();
    return value;
  });

  await expect.poll(readInstallationId).toMatch(/^[0-9a-f-]{36}$/i);
  const first = await readInstallationId();
  await page.reload();
  await expect.poll(readInstallationId).toBe(first);
});

test("cycles light, dark and system themes and preserves the explicit choice", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Darstellung: System" }).click();
  await expect.poll(() => page.evaluate(() => localStorage.getItem("gainer-theme"))).toBe("light");
  expect(await page.locator("html").evaluate((element) => element.classList.contains("dark"))).toBe(false);

  await page.getByRole("button", { name: "Darstellung: Hell" }).click();
  await expect.poll(() => page.evaluate(() => localStorage.getItem("gainer-theme"))).toBe("dark");
  expect(await page.locator("html").evaluate((element) => element.classList.contains("dark"))).toBe(true);

  await page.reload();
  await expect(page.getByRole("button", { name: "Darstellung: Dunkel" })).toBeVisible();
  expect(await page.locator("html").evaluate((element) => element.classList.contains("dark"))).toBe(true);
});
