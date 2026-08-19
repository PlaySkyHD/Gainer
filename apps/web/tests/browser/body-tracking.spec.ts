import { expect, test, type Page } from "@playwright/test";

test("goal history and one correctable daily check-in survive reload and offline editing", async ({ page }) => {
  const api = await mockAuthenticatedApi(page);
  await page.goto("/");
  await page.getByLabel("E-Mail-Adresse").fill("tracker@example.test");
  await page.getByLabel("Passwort").fill("correct-password");
  await page.getByRole("button", { name: "Anmelden" }).click();
  await page.getByRole("button", { name: "Check-in" }).click();

  await page.getByLabel("Zielart").selectOption("Bulk");
  await page.getByLabel("Startgewicht (kg)").fill("80");
  await page.getByLabel("Zielgewicht (kg)").fill("85");
  await page.getByLabel("Startdatum").fill("2026-08-01");
  await page.getByLabel("Zieldatum (optional)").fill("2026-12-31");
  await page.getByRole("button", { name: "Ziel aktivieren" }).click();
  await expect(page.getByText("Bulk: 80 kg → 85 kg")).toBeVisible();

  await page.getByLabel("Zielart").selectOption("Maintain");
  await page.getByLabel("Startgewicht (kg)").fill("84");
  await page.getByLabel("Zielgewicht (kg)").fill("84");
  await page.getByLabel("Startdatum").fill("2026-09-01");
  await page.getByLabel("Zieldatum (optional)").fill("");
  await page.getByRole("button", { name: "Ziel aktivieren" }).click();
  await expect(page.getByText("Maintain: 84 kg → 84 kg")).toBeVisible();
  await expect(page.getByRole("listitem").filter({ hasText: "Bulk: 80 kg → 85 kg" })).toBeVisible();

  await page.getByLabel("Kalendertag").fill("2026-08-18");
  await page.getByLabel("Gewicht (kg)", { exact: true }).fill("82.5");
  await page.getByLabel("Kalorien (kcal)").fill("2500");
  await page.getByLabel("Protein (g)").fill("180");
  await page.getByRole("button", { name: "Check-in speichern" }).click();
  await expect(page.getByText("Check-in gespeichert.")).toBeVisible();
  await expect(page.getByText("82.5 kg")).toBeVisible();

  await page.reload();
  await page.getByRole("button", { name: "Check-in" }).click();
  await expect(page.getByText("82.5 kg")).toBeVisible();
  const weight = page.getByLabel("Gewicht (kg)", { exact: true });
  await weight.evaluate((element) => element.removeAttribute("min"));
  await weight.fill("-1");
  await page.getByLabel("Kalendertag").fill("2026-08-18");
  await page.getByRole("button", { name: "Check-in speichern" }).click();
  await expect(page.getByRole("alert").filter({ hasText: "Gewicht muss positiv" })).toBeVisible();
  await expect(page.getByText("82.5 kg")).toBeVisible();

  api.setUnavailable(true);
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "onLine", { configurable: true, get: () => false });
  });
  await page.reload();
  await page.getByRole("button", { name: "Check-in" }).click();
  await expect(page.getByText("tracker@example.test · Offline")).toBeVisible();
  await page.getByLabel("Kalendertag").fill("2026-08-18");
  await page.getByLabel("Gewicht (kg)", { exact: true }).fill("82.2");
  await page.getByRole("button", { name: "Check-in speichern" }).click();
  await expect(page.getByText("82.2 kg")).toBeVisible();
  await expect(page.getByText("2026-08-18")).toHaveCount(1);
});

async function mockAuthenticatedApi(page: Page) {
  let authenticated = false;
  let unavailable = false;
  await page.route("**/api/v1/auth/**", async (route) => {
    const pathname = new URL(route.request().url()).pathname;
    if (pathname.endsWith("/antiforgery")) {
      await route.fulfill({ json: { requestToken: "body-test-token" } });
    } else if (pathname.endsWith("/login")) {
      authenticated = true;
      await route.fulfill({ status: 204 });
    } else if (pathname.endsWith("/session") && unavailable) {
      await route.abort("failed");
    } else if (pathname.endsWith("/session") && authenticated) {
      await route.fulfill({
        json: {
          userId: "44444444-4444-4444-8444-444444444444",
          email: "tracker@example.test",
          isAccountOperator: false,
        },
      });
    } else {
      await route.fulfill({ status: 401 });
    }
  });
  return { setUnavailable: (value: boolean) => { unavailable = value; } };
}
