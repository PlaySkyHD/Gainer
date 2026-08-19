import "fake-indexeddb/auto";
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import Dexie from "dexie";
import { createServerAggregate } from "../../src/lib/offline/aggregate-envelope.ts";
import { AccountDatabase } from "../../src/lib/offline/database.ts";
import {
  calculateNutrition,
  createNutritionEntry,
  deleteLocalNutritionDay,
  NutritionInputError,
  readLocalNutritionDay,
  recentLocalNutritionEntries,
  saveLocalNutritionDay,
  type LocalNutritionDay,
} from "../../src/lib/offline/nutrition-tracking.ts";

const databases: AccountDatabase[] = [];

afterEach(async () => {
  const current = databases.splice(0);
  current.forEach((database) => database.close());
  await Promise.all(current.map((database) => Dexie.delete(database.name)));
});

test("nutrition calculation preserves missing macros and rounds deterministically", () => {
  assert.deepEqual(calculateNutrition(33.33, {
    kilocalories: 250.55,
    proteinGrams: 20.25,
    carbohydrateGrams: null,
    fatGrams: 3.05,
  }), {
    kilocalories: 83.51,
    proteinGrams: 6.75,
    carbohydrateGrams: null,
    fatGrams: 1.02,
  });
});

test("create update move and delete are atomic with ordered outbox mutations", async () => {
  const database = await createDatabase();
  const breakfast = entry("Oats", "Breakfast", 0, 150);
  const dayId = await saveLocalNutritionDay(database, "2026-08-19", [breakfast]);
  const lunch = entry("Rice", "Lunch", 0, 200);
  await saveLocalNutritionDay(database, "2026-08-19", [
    { ...breakfast, meal: "Snacks", position: 0 },
    lunch,
  ]);

  const day = await readLocalNutritionDay(database, "2026-08-19");
  assert.equal(day?.id, dayId);
  assert.deepEqual(day?.entries.map((item) => item.meal), ["Lunch", "Snacks"]);
  assert.equal(day?.totals.kilocalories, 815);
  assert.deepEqual((await database.outbox.where("aggregateKey").equals(`nutrition-day:${dayId}`).sortBy("sequence"))
    .map((item) => item.sequence), [1, 2]);

  await deleteLocalNutritionDay(database, "2026-08-19");
  assert.equal(await database.nutritionDays.count(), 0);
  assert.equal(await database.outbox.count(), 0, "a never-synced day needs no server tombstone");
});

test("deleting a server day queues a tombstone and recent foods remain account-local", async () => {
  const first = await createDatabase();
  const second = await createDatabase();
  const id = crypto.randomUUID();
  const value = day("2026-08-19", [entry("Private oats", "Breakfast", 0, 100)]);
  await first.nutritionDays.put({ id, envelope: createServerAggregate(id, value, 3) });
  await second.nutritionDays.put({
    id: crypto.randomUUID(),
    envelope: createServerAggregate(crypto.randomUUID(), day("2026-08-19", [entry("Other food", "Breakfast", 0, 100)]), 1),
  });

  assert.deepEqual((await recentLocalNutritionEntries(first)).map((item) => item.productName), ["Private oats"]);
  await deleteLocalNutritionDay(first, "2026-08-19");

  const records = await first.outbox.toArray();
  assert.equal(records.length, 1);
  assert.equal(records[0]?.aggregateKey, `nutrition-day:${id}`);
  assert.equal((records[0]?.payload as { operation: string }).operation, "delete");
});

test("invalid input leaves neither working copy nor outbox data", async () => {
  const database = await createDatabase();
  assert.throws(() => entry("", "Breakfast", 0, -1), NutritionInputError);
  await assert.rejects(
    saveLocalNutritionDay(database, "invalid-date", []),
    NutritionInputError,
  );
  assert.equal(await database.nutritionDays.count(), 0);
  assert.equal(await database.outbox.count(), 0);
});

function entry(name: string, meal: "Breakfast" | "Lunch" | "Dinner" | "Snacks", position: number, amount: number) {
  return createNutritionEntry({
    meal,
    position,
    productName: name,
    amountGrams: amount,
    per100Grams: {
      kilocalories: name === "Rice" ? 130 : 370,
      proteinGrams: 10,
      carbohydrateGrams: null,
      fatGrams: 5,
    },
  });
}

function day(localDate: string, entries: ReturnType<typeof entry>[]): LocalNutritionDay {
  return {
    localDate,
    entries,
    totals: entries.reduce((totals, item) => ({
      kilocalories: totals.kilocalories + item.totals.kilocalories,
      proteinGrams: null,
      carbohydrateGrams: null,
      fatGrams: null,
    }), { kilocalories: 0, proteinGrams: null, carbohydrateGrams: null, fatGrams: null }),
    createdAtUtc: "2026-08-19T10:00:00.000Z",
    updatedAtUtc: "2026-08-19T10:00:00.000Z",
  };
}

async function createDatabase() {
  const database = new AccountDatabase(crypto.randomUUID());
  databases.push(database);
  await database.open();
  return database;
}
