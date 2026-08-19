import { expect, test, type Page } from "@playwright/test";

const accountId = "99999999-9999-4999-8999-999999999999";

test("meal diary supports manual entry, editing, day navigation and reload", async ({ page }) => {
  const api = await mockNutritionApi(page);
  await login(page);
  await openNutrition(page);

  await page.getByRole("region", { name: "Frühstück" }).getByRole("button", { name: "Hinzufügen" }).click();
  await page.getByRole("tab", { name: "Manuell" }).click();
  await page.getByRole("dialog").getByRole("textbox", { name: "Lebensmittel", exact: true }).fill("Haferflocken");
  await page.getByLabel("Menge (g)").fill("80");
  await page.getByLabel("kcal pro 100 g").fill("370");
  await page.getByLabel("Protein pro 100 g").fill("13");
  await page.getByRole("button", { name: "Eintrag speichern" }).click();
  const oats = page.getByRole("button", { name: /Haferflocken.*80 g.*296 kcal/ });
  await expect(oats).toBeVisible();

  await oats.click();
  await expect(page.getByRole("heading", { name: "Eintrag bearbeiten" })).toBeVisible();
  await page.getByLabel("Mahlzeit").selectOption("Lunch");
  await page.getByLabel("Menge (g)").fill("100");
  await page.getByRole("button", { name: "Eintrag speichern" }).click();
  await expect(page.getByRole("region", { name: "Mittagessen" }).getByText("Haferflocken")).toBeVisible();

  await page.reload();
  await openNutrition(page);
  await expect(page.getByText("Haferflocken")).toBeVisible();
  await page.getByRole("button", { name: "Nächster Tag" }).click();
  await expect(page.getByText("Haferflocken")).toHaveCount(0);
  await page.getByRole("button", { name: "Vorheriger Tag" }).click();
  await expect(page.getByText("Haferflocken")).toBeVisible();

  api.setSessionUnavailable(true);
  await page.addInitScript(() => Object.defineProperty(navigator, "onLine", { configurable: true, get: () => false }));
  await page.reload();
  await openNutrition(page);
  await expect(page.getByText("Haferflocken")).toBeVisible();
  await expect(page.getByText(/Offline/).first()).toBeVisible();
});

test("explicit food search, barcode fallback and provider errors keep manual entry available", async ({ page }) => {
  const api = await mockNutritionApi(page);
  await login(page);
  await openNutrition(page);
  await page.getByRole("region", { name: "Snacks" }).getByRole("button", { name: "Hinzufügen" }).click();

  await page.getByRole("tab", { name: "Suchen" }).click();
  await page.getByLabel("Produkt oder Marke").fill("Skyr");
  expect(api.searchCalls()).toBe(0);
  await page.getByRole("button", { name: "Suche absenden" }).click();
  await expect(page.getByRole("button", { name: /Skyr Natur/ })).toBeVisible();
  expect(api.searchCalls()).toBe(1);
  await page.getByRole("button", { name: /Skyr Natur/ }).click();
  await page.getByLabel("Menge (g)").fill("250");
  await page.getByRole("button", { name: "Eintrag speichern" }).click();
  await expect(page.getByText("Skyr Natur")).toBeVisible();

  await page.getByRole("region", { name: "Snacks" }).getByRole("button", { name: "Hinzufügen" }).click();
  await page.getByRole("tab", { name: "Barcode" }).click();
  await page.getByRole("button", { name: /Barcode mit Kamera scannen/ }).click();
  await expect(page.getByText(/Kamerascan.*nicht unterstützt/)).toBeVisible();
  await page.getByLabel("Barcode manuell eingeben").fill("4001234567890");
  await page.getByRole("button", { name: "Nachschlagen" }).click();
  await expect(page.getByRole("dialog").getByRole("textbox", { name: "Lebensmittel", exact: true })).toHaveValue("Proteinriegel");
  await page.getByRole("button", { name: "Schließen" }).click();

  api.setProviderUnavailable(true);
  await page.getByRole("region", { name: "Snacks" }).getByRole("button", { name: "Hinzufügen" }).click();
  await page.getByRole("tab", { name: "Suchen" }).click();
  await page.getByLabel("Produkt oder Marke").fill("Fehlerprodukt");
  await page.getByRole("button", { name: "Suche absenden" }).click();
  await expect(page.getByText(/vorübergehend nicht erreichbar/)).toBeVisible();
  await page.getByRole("tab", { name: "Manuell" }).click();
  await expect(page.getByRole("dialog").getByRole("textbox", { name: "Lebensmittel", exact: true })).toBeVisible();
});

async function openNutrition(page: Page) {
  await page.getByRole("navigation", { name: "Hauptnavigation", exact: true }).getByRole("button", { name: "Essen" }).click();
  await expect(page.getByLabel("Ernährungstag auswählen")).toBeVisible();
}

async function login(page: Page) {
  await page.goto("/");
  await page.getByLabel("E-Mail-Adresse").fill("nutrition@example.test");
  await page.getByLabel("Passwort").fill("correct-password");
  await page.getByRole("button", { name: "Anmelden" }).click();
  await expect(page.getByText("nutrition@example.test")).toBeVisible();
}

async function mockNutritionApi(page: Page) {
  let authenticated = false;
  let sessionUnavailable = false;
  let providerUnavailable = false;
  let searches = 0;
  await page.route("**/api/v1/auth/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith("/antiforgery")) await route.fulfill({ json: { requestToken: "nutrition-token" } });
    else if (path.endsWith("/login")) { authenticated = true; await route.fulfill({ status: 204 }); }
    else if (path.endsWith("/session") && sessionUnavailable) await route.abort("failed");
    else if (path.endsWith("/session") && authenticated) await route.fulfill({ json: {
      userId: accountId, email: "nutrition@example.test", isAccountOperator: false,
    } });
    else await route.fulfill({ status: 401 });
  });
  await page.route("**/api/v1/foods/**", async (route) => {
    const url = new URL(route.request().url());
    if (providerUnavailable) {
      await route.fulfill({ status: 503, json: { title: "Unavailable", code: "provider_unavailable" } });
      return;
    }
    const product = {
      barcode: url.pathname.includes("barcode") ? "4001234567890" : "11111111",
      productName: url.pathname.includes("barcode") ? "Proteinriegel" : "Skyr Natur",
      brand: "Testmarke", basisGrams: 100, kilocaloriesPer100Grams: 63,
      proteinGramsPer100Grams: 11, carbohydrateGramsPer100Grams: 4,
      fatGramsPer100Grams: 0.2, qualityIndicators: [],
      retrievedAtUtc: "2026-08-19T12:00:00Z", isStale: false, source: "OpenFoodFacts",
    };
    if (url.pathname.endsWith("/search")) { searches++; await route.fulfill({ json: { products: [product], page: 1, hasMore: false } }); }
    else await route.fulfill({ json: product });
  });
  return {
    searchCalls: () => searches,
    setProviderUnavailable: (value: boolean) => { providerUnavailable = value; },
    setSessionUnavailable: (value: boolean) => { sessionUnavailable = value; },
  };
}
