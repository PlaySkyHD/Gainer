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

test("standalone meal library supports create duplicate archive and deep-copy use", async ({ page }) => {
  await mockNutritionApi(page);
  await login(page);
  await openNutrition(page);
  await page.getByRole("region", { name: /Fr/ }).getByRole("button", { name: /Hinzuf/ }).click();
  await page.getByRole("tab", { name: "Manuell" }).click();
  await page.getByRole("dialog").getByRole("textbox", { name: "Lebensmittel", exact: true }).fill("Meal-Prep Reis");
  await page.getByLabel("Menge (g)").fill("200");
  await page.getByLabel("kcal pro 100 g").fill("130");
  await page.getByRole("button", { name: "Eintrag speichern" }).click();

  await page.getByLabel("Ernährungsbereich").getByRole("tab", { name: "Gerichte" }).click();
  await page.getByRole("button", { name: "Neues Gericht" }).click();
  await page.getByLabel("Name", { exact: true }).fill("Reis Bowl");
  await page.getByRole("button", { name: "Lebensmittel hinzufügen" }).click();
  const mealFoodDialog = page.getByRole("dialog", { name: "Lebensmittel hinzufügen" });
  await expect(mealFoodDialog.getByRole("tab", { name: "Zuletzt" })).toBeVisible();
  await expect(mealFoodDialog.getByRole("tab", { name: "Suchen" })).toBeVisible();
  await expect(mealFoodDialog.getByRole("tab", { name: "Barcode" })).toBeVisible();
  await expect(mealFoodDialog.getByRole("tab", { name: "AI" })).toBeVisible();
  await expect(mealFoodDialog.getByRole("tab", { name: "Manuell" })).toBeVisible();
  await mealFoodDialog.getByRole("button", { name: /Meal-Prep Reis/ }).click();
  await mealFoodDialog.getByRole("button", { name: "Lebensmittel übernehmen" }).click();
  await page.getByRole("button", { name: "Gericht speichern" }).click();
  await expect(page.getByText("Reis Bowl")).toBeVisible();
  await page.getByRole("button", { name: "Duplizieren" }).click();
  const duplicateForm = page.getByRole("button", { name: "Gericht speichern" }).locator("xpath=ancestor::form");
  await duplicateForm.getByRole("textbox", { name: "Name", exact: true }).fill("Reis Bowl Arbeit");
  await duplicateForm.getByRole("button", { name: "Gericht speichern" }).click();
  await expect(page.getByText("Reis Bowl Arbeit")).toBeVisible();

  await page.getByLabel("Ernährungsbereich").getByRole("tab", { name: "Tagebuch" }).click();
  await page.getByRole("region", { name: /Mittagessen/ }).getByRole("button", { name: /Hinzuf/ }).click();
  await page.getByLabel("Erfassungsart").getByRole("tab", { name: "Gerichte" }).click();
  await page.addInitScript(() => Object.defineProperty(navigator, "onLine", { configurable: true, get: () => false }));
  await page.evaluate(() => {
    Object.defineProperty(navigator, "onLine", { configurable: true, get: () => false });
    window.dispatchEvent(new Event("offline"));
  });
  await page.getByRole("button", { name: "Auswählen" }).first().click();
  await page.getByLabel("Portionsfaktor").fill("0.5");
  await expect(page.locator('[aria-label="Resultierende Komponenten"]').getByText("100 g")).toBeVisible();
  await page.getByRole("button", { name: "Komponenten hinzufügen" }).click();
  await page.getByLabel("Ernährungsbereich").getByRole("tab", { name: "Gerichte" }).click();
  const originalMeal = page.getByText("Reis Bowl", { exact: true }).locator("xpath=ancestor::div[contains(@class,'rounded-2xl')][1]");
  await originalMeal.getByRole("button", { name: "Bearbeiten" }).click();
  const editForm = page.getByRole("button", { name: "Gericht speichern" }).locator("xpath=ancestor::form");
  await editForm.getByLabel("Menge (g)").fill("300");
  await editForm.getByRole("button", { name: "Gericht speichern" }).click();
  await page.getByLabel("Ernährungsbereich").getByRole("tab", { name: "Tagebuch" }).click();
  await expect(page.getByRole("region", { name: /Mittagessen/ }).getByRole("button", { name: /Meal-Prep Reis.*100 g.*130 kcal/ })).toBeVisible();
  await page.getByLabel("Ernährungsbereich").getByRole("tab", { name: "Gerichte" }).click();
  page.once("dialog", (dialog) => dialog.accept());
  await originalMeal.getByRole("button", { name: "Archivieren" }).click();
  await expect(page.getByText("Reis Bowl", { exact: true })).toHaveCount(0);
});

test("meal editor reuses search barcode manual and AI acquisition without changing the diary", async ({ page }) => {
  await mockNutritionApi(page);
  await login(page);
  await openNutrition(page);
  await page.getByLabel("Ernährungsbereich").getByRole("tab", { name: "Gerichte" }).click();
  await page.getByRole("button", { name: "Neues Gericht" }).click();
  await page.getByLabel("Name", { exact: true }).fill("Dialog Bowl");

  await page.getByRole("button", { name: "Lebensmittel hinzufügen" }).click();
  let dialog = page.getByRole("dialog", { name: "Lebensmittel hinzufügen" });
  await dialog.getByRole("tab", { name: "Suchen" }).click();
  await dialog.getByLabel("Produkt oder Marke").fill("Skyr");
  await dialog.getByRole("button", { name: "Suche absenden" }).click();
  await dialog.getByRole("button", { name: /Skyr Natur/ }).click();
  await dialog.getByRole("button", { name: "Lebensmittel übernehmen" }).click();

  await page.getByRole("button", { name: "Lebensmittel hinzufügen" }).click();
  dialog = page.getByRole("dialog", { name: "Lebensmittel hinzufügen" });
  await dialog.getByRole("tab", { name: "Barcode" }).click();
  await dialog.getByLabel("Barcode manuell eingeben").fill("4001234567890");
  await dialog.getByRole("button", { name: "Nachschlagen" }).click();
  await dialog.getByRole("button", { name: "Lebensmittel übernehmen" }).click();

  await page.getByRole("button", { name: "Lebensmittel hinzufügen" }).click();
  dialog = page.getByRole("dialog", { name: "Lebensmittel hinzufügen" });
  await dialog.getByRole("tab", { name: "Manuell" }).click();
  await dialog.getByRole("textbox", { name: "Lebensmittel", exact: true }).fill("Banane");
  await dialog.getByLabel("kcal pro 100 g").fill("89");
  await dialog.getByRole("button", { name: "Schließen" }).click();
  await expect(page.getByText("Banane", { exact: true })).toHaveCount(0);

  await page.getByRole("button", { name: "Lebensmittel hinzufügen" }).click();
  dialog = page.getByRole("dialog", { name: "Lebensmittel hinzufügen" });
  await dialog.getByRole("tab", { name: "AI" }).click();
  await dialog.getByLabel("Mahlzeit beschreiben").fill("Skyr mit Beeren");
  await dialog.getByRole("button", { name: "Mit AI schätzen" }).click();
  await dialog.getByRole("button", { name: "Komponente ergänzen" }).click();
  await dialog.getByRole("button", { name: /Komponenten übernehmen/ }).click();

  await expect(page.getByText("Skyr Natur", { exact: true })).toBeVisible();
  await expect(page.getByText("Proteinriegel", { exact: true })).toBeVisible();
  await expect(page.getByText("Skyr mit Beeren", { exact: true })).toBeVisible();
  await expect(page.getByText("Neue Komponente", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Gericht speichern" }).click();
  await expect(page.getByText(/4 Komponenten/)).toBeVisible();

  await page.getByLabel("Ernährungsbereich").getByRole("tab", { name: "Tagebuch" }).click();
  await expect(page.getByText("Skyr Natur", { exact: true })).toHaveCount(0);
  await expect(page.getByText("Proteinriegel", { exact: true })).toHaveCount(0);
});

test("goal phases support categories, grams, percentages and inclusive transitions", async ({ page }) => {
  await mockNutritionApi(page);
  await login(page);
  await openNutrition(page);
  const start = localDate(0);
  const tomorrow = localDate(1);

  await page.getByRole("button", { name: "Verwalten" }).click();
  const targetDialog = page.getByRole("dialog", { name: "Zielphasen" });
  await expect(targetDialog.getByText(/App und der Coach berechnen oder empfehlen keine/)).toBeVisible();
  await targetDialog.getByRole("button", { name: "Neue Zielphase" }).click();
  await targetDialog.getByLabel("Name").fill("Sommer-Cut");
  await targetDialog.getByLabel("Kategorie").selectOption("Maintenance");
  await targetDialog.getByLabel("Kategorie").selectOption("Bulk");
  await targetDialog.getByLabel("Kategorie").selectOption("Custom");
  await targetDialog.getByLabel("Kategorie").selectOption("Cut");
  await targetDialog.getByLabel("Start").fill(start);
  await expect(targetDialog.getByRole("spinbutton", { name: "Kalorien", exact: true })).toBeEmpty();
  await targetDialog.getByRole("spinbutton", { name: "Kalorien", exact: true }).fill("300");
  await targetDialog.getByLabel("Protein (g)").fill("30");
  await targetDialog.getByLabel("Kohlenhydrate (g)").fill("30");
  await targetDialog.getByLabel("Fett (g)").fill("6.67");
  await targetDialog.getByRole("button", { name: "Zielphase speichern" }).click();
  await expect(targetDialog.getByText("Sommer-Cut", { exact: true })).toBeVisible();
  await targetDialog.getByRole("button", { name: "Neue Zielphase" }).click();
  await targetDialog.getByLabel("Name").fill("Aufbau");
  await targetDialog.getByLabel("Kategorie").selectOption("Bulk");
  await targetDialog.getByLabel("Start").fill(tomorrow);
  await targetDialog.getByRole("spinbutton", { name: "Kalorien", exact: true }).fill("500");
  await targetDialog.getByLabel("Eingabe").selectOption("Percent");
  await targetDialog.getByLabel("Protein (%)").fill("30");
  await targetDialog.getByLabel("Kohlenhydrate (%)").fill("40");
  await targetDialog.getByLabel("Fett (%)").fill("30");
  await expect(targetDialog.getByText(/Summe:.*100 %/)).toBeVisible();
  page.once("dialog", (dialog) => dialog.accept());
  await targetDialog.getByRole("button", { name: "Zielphase speichern" }).click();
  await expect(targetDialog.getByText("Aufbau", { exact: true })).toBeVisible();
  await targetDialog.getByRole("button", { name: "Schließen" }).click();
  await expect(page.getByText(/Sommer-Cut.*Cut/)).toBeVisible();
  await expect(page.getByLabel(/Kalorien: 0 von 300 kcal/)).toBeVisible();

  await page.getByRole("button", { name: "Nächster Tag" }).click();
  await expect(page.getByText(/Aufbau.*Aufbau/)).toBeVisible();
  await expect(page.getByLabel(/Kalorien: 0 von 500 kcal/)).toBeVisible();
  await page.getByRole("button", { name: "Vorheriger Tag" }).click();
  await expect(page.getByLabel(/Kalorien: 0 von 300 kcal/)).toBeVisible();
  await page.reload();
  await openNutrition(page);
  await expect(page.getByText(/Sommer-Cut.*Cut/)).toBeVisible();
});

test("AI estimate remains editable and only confirmed components become entries", async ({ page }) => {
  const api = await mockNutritionApi(page);
  await login(page);
  await openNutrition(page);
  await page.getByRole("region", { name: "Snacks" }).getByRole("button", { name: /Hinzuf/ }).click();
  await page.getByRole("tab", { name: "AI" }).click();
  await page.getByLabel("Mahlzeit beschreiben").fill("Skyr mit Beeren");
  await page.getByRole("button", { name: "Mit AI schätzen" }).click();
  await expect(page.getByText(/AI-Werte sind/)).toBeVisible();
  await page.getByLabel("Menge (g)").fill("275");
  await page.getByRole("button", { name: "Komponente ergänzen" }).click();
  await expect(page.getByLabel("Menge (g)")).toHaveCount(2);
  await page.getByRole("button", { name: "Entfernen" }).last().click();
  await page.getByRole("button", { name: "Entwurf verwerfen" }).click();
  await expect(page.getByLabel("Mahlzeit beschreiben")).toBeVisible();
  await page.reload();
  await openNutrition(page);
  await page.getByRole("region", { name: "Snacks" }).getByRole("button", { name: /Hinzuf/ }).click();
  await page.getByRole("tab", { name: "AI" }).click();
  await expect(page.getByText(/AI-Werte sind/)).toHaveCount(0);

  api.setMealEstimateUnavailable(true);
  await page.getByLabel("Mahlzeit beschreiben").fill("Providerfehler");
  await page.getByRole("button", { name: "Mit AI schätzen" }).click();
  await expect(page.getByText(/vorübergehend nicht verfügbar/)).toBeVisible();
  api.setMealEstimateUnavailable(false);
  await page.getByLabel("Foto (optional)").setInputFiles({
    name: "synthetic-meal.png", mimeType: "image/png",
    buffer: Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=", "base64"),
  });
  await page.getByText(/Ich stimme der einmaligen Übertragung/).click();
  await page.getByLabel("Mahlzeit beschreiben").fill("Skyr mit Beeren");
  await page.getByRole("button", { name: "Mit AI schätzen" }).click();
  await expect(page.getByText(/AI-Werte sind/)).toBeVisible();
  await page.getByLabel("Menge (g)").fill("300");
  await page.getByRole("button", { name: /Komponenten übernehmen/ }).click();
  await expect(page.getByRole("region", { name: "Snacks" }).getByText("Skyr mit Beeren")).toBeVisible();
  expect(api.mealEstimateCalls()).toBe(3);
});

async function openNutrition(page: Page) {
  await page.getByRole("navigation", { name: "Hauptnavigation", exact: true }).getByRole("button", { name: "Essen" }).click();
  await expect(page.getByLabel("Ernährungstag auswählen")).toBeVisible();
}

function localDate(days: number) {
  const date = new Date();
  date.setDate(date.getDate() + days);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
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
  let mealEstimateUnavailable = false;
  let mealEstimates = 0;
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
  await page.route("**/api/v1/nutrition/meal-estimates", async (route) => {
    mealEstimates++;
    if (mealEstimateUnavailable) {
      await route.fulfill({ status: 503, json: { title: "Unavailable", code: "provider_unavailable" } });
      return;
    }
    await route.fulfill({ json: {
      components: [{
        name: "Skyr mit Beeren", amountGrams: 250, kilocalories: 220,
        proteinGrams: 28, carbohydrateGrams: 24, fatGrams: 2,
        confidence: "Medium", dataGaps: ["Beerenmenge geschätzt"],
      }],
      provider: "OpenAI", schemaVersion: "meal-estimate-v1", estimatedAtUtc: "2026-08-19T12:00:00Z",
    } });
  });
  return {
    searchCalls: () => searches,
    mealEstimateCalls: () => mealEstimates,
    setProviderUnavailable: (value: boolean) => { providerUnavailable = value; },
    setMealEstimateUnavailable: (value: boolean) => { mealEstimateUnavailable = value; },
    setSessionUnavailable: (value: boolean) => { sessionUnavailable = value; },
  };
}
