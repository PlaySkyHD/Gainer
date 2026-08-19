import { expect, test, type Page } from "@playwright/test";

test("offline exercise, templates and rotation survive reload and skip archived entries", async ({ page }) => {
  const api = await mockAuthenticatedApi(page);
  await page.goto("/");
  await page.getByLabel("E-Mail-Adresse").fill("planner@example.test");
  await page.getByLabel("Passwort").fill("correct-password");
  await page.getByRole("button", { name: "Anmelden" }).click();
  await page.getByRole("button", { name: "Pläne" }).click();
  await expect(page.getByRole("heading", { name: "Übungsbibliothek" })).toBeVisible();

  api.setUnavailable(true);
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "onLine", { configurable: true, get: () => false });
  });
  await page.reload();
  await page.getByRole("button", { name: "Pläne" }).click();
  await expect(page.getByText("planner@example.test · Offline")).toBeVisible();

  await page.getByLabel("Name der eigenen Übung").fill("Offline Cable Press");
  await page.getByLabel("Muskelgruppe", { exact: true }).last().fill("Chest");
  await page.getByLabel("Equipment", { exact: true }).last().fill("Cable");
  await page.getByRole("button", { name: "Eigene Übung anlegen" }).click();
  await expect(page.getByRole("paragraph").filter({ hasText: /^Offline Cable Press$/ })).toBeVisible();

  await createTemplate(page, "Offline Push", "Offline Cable Press");
  await createTemplate(page, "Base Push", "Barbell Bench Press");

  const rotation = page.getByLabel("Template zur Rotation hinzufügen");
  await rotation.selectOption({ label: "Offline Push" });
  await rotation.selectOption({ label: "Base Push" });
  await page.getByRole("button", { name: "Rotation speichern" }).click();
  await expect(page.getByText("Nächstes Template:").locator("strong")).toHaveText("Offline Push");

  await page.reload();
  await page.getByRole("button", { name: "Pläne" }).click();
  await expect(page.getByText("Nächstes Template:").locator("strong")).toHaveText("Offline Push");
  await expect(page.getByText("Offline Push", { exact: true }).first()).toBeVisible();

  page.once("dialog", (dialog) => dialog.accept());
  await page.getByRole("listitem").filter({ hasText: "Offline Cable Press" })
    .getByRole("button", { name: "Archivieren" }).click();
  await expect(page.getByText("Übung archiviert.")).toBeVisible();
  await expect(page.getByRole("listitem").filter({ hasText: "Offline Cable Press" })).toHaveCount(0);
  const offlineTemplate = page.getByRole("listitem").filter({ hasText: "Offline Push" }).filter({ hasText: "1 Übungen" });
  await expect(offlineTemplate).toBeVisible();

  page.once("dialog", (dialog) => dialog.accept());
  await offlineTemplate.getByRole("button", { name: "Archivieren" }).click();
  await expect(page.getByText("Nächstes Template:").locator("strong")).toHaveText("Base Push");
});

async function createTemplate(page: Page, name: string, exercise: string) {
  await page.getByLabel("Template-Name").fill(name);
  await page.getByLabel("Übung hinzufügen").selectOption({ label: exercise });
  await page.getByRole("button", { name: "Template speichern" }).click();
  await expect(page.getByText("Template lokal gespeichert.")).toBeVisible();
  await expect(page.getByRole("listitem").filter({ hasText: name })).toBeVisible();
}

async function mockAuthenticatedApi(page: Page) {
  let authenticated = false;
  let unavailable = false;
  await page.route("**/api/v1/auth/**", async (route) => {
    const pathname = new URL(route.request().url()).pathname;
    if (pathname.endsWith("/antiforgery")) {
      await route.fulfill({ json: { requestToken: "planning-test-token" } });
    } else if (pathname.endsWith("/login")) {
      authenticated = true;
      await route.fulfill({ status: 204 });
    } else if (pathname.endsWith("/session") && unavailable) {
      await route.abort("failed");
    } else if (pathname.endsWith("/session") && authenticated) {
      await route.fulfill({
        json: {
          userId: "55555555-5555-4555-8555-555555555555",
          email: "planner@example.test",
          isAccountOperator: false,
        },
      });
    } else {
      await route.fulfill({ status: 401 });
    }
  });
  return { setUnavailable: (value: boolean) => { unavailable = value; } };
}
