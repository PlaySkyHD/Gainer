import { expect, test, type Page } from "@playwright/test";

test("complete offline workout restores, times rest, records history and excludes an abort", async ({ page }) => {
  const api = await mockAuthenticatedApi(page);
  await page.goto("/");
  await page.getByLabel("E-Mail-Adresse").fill("lifter@example.test");
  await page.getByLabel("Passwort").fill("correct-password");
  await page.getByRole("button", { name: "Anmelden" }).click();
  await page.getByRole("button", { name: "Pläne" }).click();
  await expect(page.getByRole("heading", { name: "Trainings-Templates" })).toBeVisible();

  await page.getByLabel("Template-Name").fill("Browser Plan");
  await page.getByLabel("Übung hinzufügen").selectOption({ label: "Barbell Bench Press" });
  await page.getByRole("button", { name: "Template speichern" }).click();
  const rotation = page.getByLabel("Template zur Rotation hinzufügen");
  await rotation.selectOption({ label: "Browser Plan" });
  await page.getByRole("button", { name: "Rotation speichern" }).click();

  api.setUnavailable(true);
  await page.addInitScript(() => Object.defineProperty(navigator, "onLine", { configurable: true, get: () => false }));
  await page.reload();
  await page.getByRole("button", { name: "Training" }).click();
  await page.getByRole("button", { name: "Browser Plan starten" }).click();
  await expect(page.getByText("Laufendes Workout")).toBeVisible();
  await page.getByLabel("Barbell Bench Press Satz 1 Gewicht (kg)").fill("100");
  await page.getByLabel("Barbell Bench Press Satz 1 Wiederholungen").fill("8");
  await page.getByRole("button", { name: "Satz fertig" }).first().click();
  await expect(page.getByText(/Pause: 1:/)).toBeVisible();

  await page.reload();
  await page.getByRole("button", { name: "Training" }).click();
  await expect(page.getByText("Laufendes Workout")).toBeVisible();
  await expect(page.getByLabel("Barbell Bench Press Satz 1 Gewicht (kg)")).toHaveValue("100");
  await page.getByRole("button", { name: "+30 Sekunden" }).click();
  await page.getByRole("button", { name: "Neustart" }).click();
  await page.getByRole("button", { name: "Überspringen" }).click();
  await expect(page.getByText(/Pause:/)).toHaveCount(0);
  await page.getByRole("button", { name: "Workout abschließen" }).click();
  await expect(page.getByText("Workout abgeschlossen.")).toBeVisible();
  const history = page.locator("#history");
  await expect(history.getByText("Browser Plan", { exact: true })).toBeVisible();
  await history.getByRole("button", { name: "Details" }).click();
  await expect(history.getByText("100 kg × 8")).toBeVisible();

  await page.getByRole("button", { name: "Browser Plan starten" }).click();
  await expect(page.getByText("Zuvor 100 kg × 8")).toBeVisible();
  page.once("dialog", (dialog) => dialog.accept());
  await page.getByRole("button", { name: "Abbrechen" }).click();
  await expect(history.getByRole("button", { name: "Details" })).toHaveCount(1);
});

async function mockAuthenticatedApi(page: Page) {
  let authenticated = false;
  let unavailable = false;
  await page.route("**/api/v1/auth/**", async (route) => {
    const pathname = new URL(route.request().url()).pathname;
    if (pathname.endsWith("/antiforgery")) await route.fulfill({ json: { requestToken: "workout-token" } });
    else if (pathname.endsWith("/login")) { authenticated = true; await route.fulfill({ status: 204 }); }
    else if (pathname.endsWith("/session") && unavailable) await route.abort("failed");
    else if (pathname.endsWith("/session") && authenticated) await route.fulfill({ json: {
      userId: "66666666-6666-4666-8666-666666666666",
      email: "lifter@example.test",
      isAccountOperator: false,
    } });
    else await route.fulfill({ status: 401 });
  });
  return { setUnavailable: (value: boolean) => { unavailable = value; } };
}
