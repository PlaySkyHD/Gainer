import "fake-indexeddb/auto";
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import Dexie from "dexie";
import { createLocalAggregate } from "../../src/lib/offline/aggregate-envelope.ts";
import { AccountDatabase } from "../../src/lib/offline/database.ts";
import { readLocalNutritionDay } from "../../src/lib/offline/nutrition-tracking.ts";
import {
  addReusableMealToDay,
  archiveReusableMeal,
  deriveMacroTargets,
  effectiveTarget,
  readNutritionTargetSchedule,
  readReusableMeals,
  saveNutritionTargetVersion,
  saveReusableMeal,
  type LocalReusableMeal,
} from "../../src/lib/offline/smart-nutrition.ts";
import {
  createFoodComponentDraft,
  foodDraftToNutritionEntry,
  foodDraftToReusableMealComponent,
} from "../../src/lib/nutrition/food-component-draft.ts";

const databases: AccountDatabase[] = [];

afterEach(async () => {
  const current = databases.splice(0);
  current.forEach((database) => database.close());
  await Promise.all(current.map((database) => Dexie.delete(database.name)));
});

test("reusable meal create edit and archive are atomic outbox operations", async () => {
  const database = await createDatabase();
  const id = await saveReusableMeal(database, { ...meal(), id: undefined });
  await saveReusableMeal(database, { ...meal(), id, name: "Meal prep bowl" });
  await archiveReusableMeal(database, id);

  const records = await readReusableMeals(database, true);
  assert.equal(records[0]?.name, "Meal prep bowl");
  assert.equal(records[0]?.status, "Archived");
  assert.deepEqual((await database.outbox.where("aggregateKey").equals(`reusable-meal:${id}`).sortBy("sequence"))
    .map((item) => item.sequence), [1, 2, 3]);
  assert.equal((await readReusableMeals(database)).length, 0);
});

test("meal expansion creates independent deep copied entries with deterministic scaling", async () => {
  const database = await createDatabase();
  const template = { ...meal(), status: "Active" as const, createdAtUtc: now(), updatedAtUtc: now() };
  await addReusableMealToDay(database, template, "2026-08-19", "Lunch", 0.5);
  template.components[0]!.name = "Changed later";
  template.components[0]!.amountGrams = 999;

  const day = await readLocalNutritionDay(database, "2026-08-19");
  assert.equal(day?.entries[0]?.productName, "Rice");
  assert.equal(day?.entries[0]?.amountGrams, 100);
  assert.equal(day?.entries[0]?.totals.kilocalories, 130);
  assert.equal((await database.outbox.toArray()).length, 1);
});

test("failed expansion and invalid templates leave no partial nutrition day", async () => {
  const database = await createDatabase();
  const invalid = { ...meal(), status: "Active" as const, createdAtUtc: now(), updatedAtUtc: now() };
  invalid.components[0]!.per100Grams.kilocalories = -1;
  await assert.rejects(addReusableMealToDay(database, invalid, "2026-08-19", "Lunch", 1));
  assert.equal(await database.nutritionDays.count(), 0);
  assert.equal(await database.outbox.count(), 0);
});

test("neutral food drafts create independent day and reusable-meal snapshots without persistence", async () => {
  const database = await createDatabase();
  const draft = createFoodComponentDraft({
    name: "Skyr",
    brand: "Test",
    amountGrams: 250,
    per100Grams: { kilocalories: 63, proteinGrams: 11, carbohydrateGrams: 4, fatGrams: 0.2 },
    source: { provider: "OpenFoodFacts", barcode: "4001234567890", retrievedAtUtc: now(), basisGrams: 100 },
  });

  const entry = foodDraftToNutritionEntry(draft, "Breakfast", 0);
  const component = foodDraftToReusableMealComponent(draft, 0);
  draft.name = "Changed draft";
  draft.per100Grams.kilocalories = 999;

  assert.equal(entry.productName, "Skyr");
  assert.equal(component.name, "Skyr");
  assert.notEqual(entry.entryId, component.componentId);
  assert.equal(component.totals.kilocalories, 157.5);
  assert.equal(await database.nutritionDays.count(), 0);
  assert.equal(await database.reusableMeals.count(), 0);
  assert.equal(await database.outbox.count(), 0);
});

test("target phases close an open predecessor atomically and resolve inclusive ranges", async () => {
  const database = await createDatabase();
  await saveNutritionTargetVersion(database, target("2026-09-01", 2_400));
  await assert.rejects(saveNutritionTargetVersion(database, target("2026-09-15", 2_600)), /muss zuerst beendet/);
  await saveNutritionTargetVersion(database, target("2026-09-15", 2_600), { closeOpenPhase: true });
  const schedule = await readNutritionTargetSchedule(database);

  assert.equal(schedule?.versions[0]?.effectiveUntil, "2026-09-14");
  assert.equal(effectiveTarget(schedule, "2026-09-14")?.kilocalories, 2_400);
  assert.equal(effectiveTarget(schedule, "2026-09-15")?.kilocalories, 2_600);
  await assert.rejects(saveNutritionTargetVersion(database, { ...target("2026-09-10", 2_500), effectiveUntil: "2026-09-20" }), /überschneiden/);
  assert.equal(schedule?.versions.length, 2);
});

test("percentage macro targets use 4/4/9 and require exactly 100 percent", () => {
  assert.deepEqual(deriveMacroTargets(2_000, 30, 40, 30), {
    proteinGrams: 150,
    carbohydrateGrams: 200,
    fatGrams: 66.67,
  });
  assert.throws(() => deriveMacroTargets(2_000, 30, 39, 30), /genau 100/);
});

test("legacy local target versions receive stable manual phase defaults", async () => {
  const database = await createDatabase();
  const id = crypto.randomUUID();
  const legacy = {
    versions: [{
      targetVersionId: crypto.randomUUID(), effectiveFrom: "2026-08-01", kilocalories: 2_400,
      proteinGrams: 180, carbohydrateGrams: 300, fatGrams: 70,
      origin: "Manual", algorithmVersion: null, reason: null,
    }],
    createdAtUtc: now(), updatedAtUtc: now(),
  };
  await database.nutritionTargetSchedules.put({ id, envelope: createLocalAggregate(id, legacy) });

  const version = (await readNutritionTargetSchedule(database))?.versions[0];
  assert.equal(version?.name, "Ziel");
  assert.equal(version?.category, "Custom");
  assert.equal(version?.inputMode, "Grams");
  assert.equal(version?.effectiveUntil, null);
});

function meal(): Omit<LocalReusableMeal, "status" | "createdAtUtc" | "updatedAtUtc"> {
  const per100 = { kilocalories: 130, proteinGrams: 3, carbohydrateGrams: 28, fatGrams: 0.3 };
  return {
    name: "Rice bowl",
    description: null,
    standardPortion: 1,
    components: [{
      componentId: crypto.randomUUID(),
      position: 0,
      name: "Rice",
      brand: null,
      amountGrams: 200,
      totals: { kilocalories: 260, proteinGrams: 6, carbohydrateGrams: 56, fatGrams: 0.6 },
      per100Grams: per100,
      source: null,
    }],
  };
}

function target(effectiveFrom: string, kilocalories: number) {
  return {
    targetVersionId: crypto.randomUUID(), name: "Cut", category: "Cut" as const,
    effectiveFrom, effectiveUntil: null, inputMode: "Grams" as const, kilocalories,
    proteinGrams: 180, carbohydrateGrams: 300, fatGrams: 70,
    proteinPercent: null, carbohydratePercent: null, fatPercent: null,
    origin: "Manual" as const, algorithmVersion: null, reason: null,
  };
}

function now() { return "2026-08-19T10:00:00.000Z"; }

async function createDatabase() {
  const database = new AccountDatabase(crypto.randomUUID());
  databases.push(database);
  await database.open();
  return database;
}
