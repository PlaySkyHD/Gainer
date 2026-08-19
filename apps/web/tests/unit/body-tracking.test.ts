import "fake-indexeddb/auto";
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import Dexie from "dexie";
import { AccountDatabase } from "../../src/lib/offline/database.ts";
import {
  activateLocalGoal,
  BodyTrackingInputError,
  readLocalBodyTracking,
  saveLocalCheckIn,
} from "../../src/lib/offline/body-tracking.ts";

const databases: AccountDatabase[] = [];

afterEach(async () => {
  const current = databases.splice(0);
  current.forEach((database) => database.close());
  await Promise.all(current.map((database) => Dexie.delete(database.name)));
});

test("goal replacement and same-day correction preserve history with ordered outbox entries", async () => {
  const database = await createDatabase();
  await activateLocalGoal(database, {
    kind: "Bulk",
    startWeightKg: 80,
    targetWeightKg: 85,
    startDate: "2026-08-01",
    targetDate: "2026-12-31",
  });
  await activateLocalGoal(database, {
    kind: "Maintain",
    startWeightKg: 84,
    targetWeightKg: 84,
    startDate: "2026-09-01",
    targetDate: null,
  });
  await saveLocalCheckIn(database, checkIn(82.5));
  await saveLocalCheckIn(database, checkIn(82.2, 2_450));

  const view = await readLocalBodyTracking(database);
  assert.equal(view.activeGoal?.kind, "Maintain");
  assert.equal(view.goalHistory[0]?.kind, "Bulk");
  assert.equal(view.checkIns.length, 1);
  assert.equal(view.checkIns[0]?.weightKg, 82.2);
  assert.equal(view.checkIns[0]?.caloriesKcal, 2_450);
  assert.equal(await database.outbox.count(), 4);
  const checkInMutations = await database.outbox
    .filter((item) => item.aggregateKey.startsWith("daily-check-in:"))
    .sortBy("sequence");
  assert.deepEqual(checkInMutations.map((item) => item.sequence), [1, 2]);
});

test("invalid goal and check-in never leave partial aggregate or outbox data", async () => {
  const database = await createDatabase();
  await assert.rejects(activateLocalGoal(database, {
    kind: "Cut",
    startWeightKg: 0,
    targetWeightKg: -1,
    startDate: "2026-08-18",
    targetDate: "2026-08-17",
  }), BodyTrackingInputError);
  await assert.rejects(saveLocalCheckIn(database, checkIn(-1)), BodyTrackingInputError);

  assert.equal(await database.goals.count(), 0);
  assert.equal(await database.checkIns.count(), 0);
  assert.equal(await database.outbox.count(), 0);
});

function checkIn(weightKg: number, caloriesKcal: number | null = null) {
  return {
    localDate: "2026-08-18",
    weightKg,
    caloriesKcal,
    proteinGrams: null,
    carbohydrateGrams: null,
    fatGrams: null,
    steps: null,
    sleepMinutes: null,
  };
}

async function createDatabase() {
  const database = new AccountDatabase(crypto.randomUUID());
  databases.push(database);
  await database.open();
  return database;
}
