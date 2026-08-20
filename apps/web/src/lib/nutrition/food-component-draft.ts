import type { FoodCatalogProduct, MealEstimate } from "../api/client.ts";
import {
  createNutritionEntry,
  type LocalNutritionEntry,
  type LocalNutritionSource,
  type LocalNutritionTotals,
  type MealType,
} from "../offline/nutrition-tracking.ts";
import type { LocalReusableMealComponent } from "../offline/smart-nutrition.ts";

export interface FoodComponentDraft {
  draftId: string;
  name: string;
  brand: string | null;
  amountGrams: number;
  per100Grams: LocalNutritionTotals;
  source: LocalNutritionSource | null;
}

export function createFoodComponentDraft(input: Omit<FoodComponentDraft, "draftId"> & { draftId?: string }): FoodComponentDraft {
  const validated = createNutritionEntry({
    meal: "Breakfast",
    position: 0,
    productName: input.name,
    brand: input.brand,
    amountGrams: input.amountGrams,
    per100Grams: input.per100Grams,
    source: input.source,
  });
  return nutritionEntryToFoodDraft(validated, input.draftId);
}

export function nutritionEntryToFoodDraft(entry: LocalNutritionEntry, draftId = crypto.randomUUID()): FoodComponentDraft {
  return {
    draftId,
    name: entry.productName,
    brand: entry.brand,
    amountGrams: entry.amountGrams,
    per100Grams: structuredClone(entry.per100Grams),
    source: entry.source ? structuredClone(entry.source) : null,
  };
}

export function foodCatalogProductToDraft(product: FoodCatalogProduct): FoodComponentDraft {
  return createFoodComponentDraft({
    name: product.productName,
    brand: product.brand,
    amountGrams: 100,
    per100Grams: {
      kilocalories: Number(product.kilocaloriesPer100Grams),
      proteinGrams: nullableApiNumber(product.proteinGramsPer100Grams),
      carbohydrateGrams: nullableApiNumber(product.carbohydrateGramsPer100Grams),
      fatGrams: nullableApiNumber(product.fatGramsPer100Grams),
    },
    source: {
      provider: product.source,
      barcode: product.barcode,
      retrievedAtUtc: product.retrievedAtUtc,
      basisGrams: Number(product.basisGrams),
    },
  });
}

export function mealEstimateToFoodDrafts(estimate: MealEstimate): FoodComponentDraft[] {
  return estimate.components.map((component) => {
    const amount = Number(component.amountGrams);
    const per100 = (value: number | string | null) => value === null ? null : Number(value) * 100 / amount;
    return createFoodComponentDraft({
      name: component.name,
      brand: null,
      amountGrams: amount,
      per100Grams: {
        kilocalories: Number(component.kilocalories) * 100 / amount,
        proteinGrams: per100(component.proteinGrams),
        carbohydrateGrams: per100(component.carbohydrateGrams),
        fatGrams: per100(component.fatGrams),
      },
      source: {
        provider: "ai-estimate-confirmed",
        barcode: null,
        retrievedAtUtc: new Date().toISOString(),
        basisGrams: 100,
      },
    });
  });
}

export function foodDraftToNutritionEntry(
  draft: FoodComponentDraft,
  meal: MealType,
  position: number,
  entryId?: string,
): LocalNutritionEntry {
  return createNutritionEntry({
    entryId,
    meal,
    position,
    productName: draft.name,
    brand: draft.brand,
    amountGrams: draft.amountGrams,
    per100Grams: structuredClone(draft.per100Grams),
    source: draft.source ? structuredClone(draft.source) : null,
  });
}

export function foodDraftToReusableMealComponent(
  draft: FoodComponentDraft,
  position: number,
  componentId = crypto.randomUUID(),
): LocalReusableMealComponent {
  const validated = foodDraftToNutritionEntry(draft, "Breakfast", position);
  return {
    componentId,
    position,
    name: validated.productName,
    brand: validated.brand,
    amountGrams: validated.amountGrams,
    totals: structuredClone(validated.totals),
    per100Grams: structuredClone(validated.per100Grams),
    source: validated.source ? structuredClone(validated.source) : null,
  };
}

function nullableApiNumber(value: number | string | null) {
  return value === null ? null : Number(value);
}
