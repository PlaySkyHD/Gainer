import "fake-indexeddb/auto";
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import Dexie from "dexie";
import { createServerAggregate } from "../../src/lib/offline/aggregate-envelope.ts";
import { AccountDatabase, type OutboxRecord } from "../../src/lib/offline/database.ts";
import { applyChangeBatch, type SyncBatch } from "../../src/lib/offline/sync-engine.ts";
import { retireLocalTrainingData } from "../../src/lib/offline/training-retirement.ts";

const databases: AccountDatabase[] = [];

afterEach(async () => {
  const opened = databases.splice(0);
  const names = [...new Set(opened.map((database) => database.name))];
  for (const database of opened) database.close();
  await Promise.all(names.map((name) => Dexie.delete(name)));
});

test("retirement discards legacy training outbox entries, conflicts and local aggregates but keeps other areas", async () => {
  const database = await openDatabase(crypto.randomUUID());
  const workoutId = crypto.randomUUID();
  await database.workouts.put({ id: workoutId, envelope: createServerAggregate(workoutId, { status: "running" }, 3) });
  await database.templates.put({ id: "template-1", envelope: createServerAggregate("template-1", { name: "A" }, 1) });
  await database.rotation.put({ id: "rotation-1", envelope: createServerAggregate("rotation-1", { entries: [] }, 1) });
  await database.customExercises.put({ id: "exercise-1", envelope: createServerAggregate("exercise-1", { name: "B" }, 1) });
  await database.checkIns.put({ id: "check-in-1", envelope: createServerAggregate("check-in-1", { weightKg: 80 }, 2) });
  await database.outbox.bulkAdd([
    outbox("workout", workoutId, 1),
    outbox("workout-template", "template-1", 2),
    outbox("workout-rotation", "rotation-1", 3),
    outbox("custom-exercise", "exercise-1", 4),
    outbox("daily-check-in", "check-in-1", 5),
  ]);
  await database.conflicts.bulkAdd([
    { conflictId: "c-workout", aggregateKey: `workout:${workoutId}`, createdAtUtc: "2026-10-01T00:00:00.000Z", detail: {} },
    { conflictId: "c-check-in", aggregateKey: "daily-check-in:check-in-1", createdAtUtc: "2026-10-01T00:00:00.000Z", detail: {} },
  ]);
  await database.tombstones.bulkPut([
    { resourceKey: `workout:${workoutId}`, resourceType: "Workout", resourceId: workoutId, revision: 7 },
    { resourceKey: "daily-check-in:old", resourceType: "DailyCheckIn", resourceId: "old", revision: 8 },
  ]);
  await database.syncMeta.bulkPut([
    { key: `last-mutation:workout:${workoutId}`, value: "m-1" },
    { key: "last-mutation:daily-check-in:check-in-1", value: "m-5" },
  ]);

  assert.equal(await retireLocalTrainingData(database), 4);

  assert.deepEqual((await database.outbox.toArray()).map((item) => item.aggregateKey), ["daily-check-in:check-in-1"]);
  assert.deepEqual((await database.conflicts.toArray()).map((item) => item.conflictId), ["c-check-in"]);
  assert.deepEqual((await database.tombstones.toArray()).map((item) => item.resourceType), ["DailyCheckIn"]);
  assert.deepEqual((await database.syncMeta.toArray()).map((item) => item.key), ["last-mutation:daily-check-in:check-in-1"]);
  assert.equal(await database.workouts.count(), 0);
  assert.equal(await database.templates.count(), 0);
  assert.equal(await database.rotation.count(), 0);
  assert.equal(await database.customExercises.count(), 0);
  assert.equal(await database.checkIns.count(), 1);
});

test("retirement is idempotent on a clean database", async () => {
  const database = await openDatabase(crypto.randomUUID());
  assert.equal(await retireLocalTrainingData(database), 0);
  assert.equal(await retireLocalTrainingData(database), 0);
});

test("pulled training changes are no longer stored locally", async () => {
  const database = await openDatabase(crypto.randomUUID());
  const batch: SyncBatch = {
    batchId: "batch-1",
    revision: 9,
    originMutationId: null,
    changes: [
      { resourceType: "Workout", resourceId: crypto.randomUUID(), version: 1, isTombstone: false, snapshot: { status: "Running" } },
      { resourceType: "CustomExercise", resourceId: crypto.randomUUID(), version: 1, isTombstone: false, snapshot: { values: { name: "X" } } },
    ],
  };

  await applyChangeBatch(database, batch);

  assert.equal(await database.workouts.count(), 0);
  assert.equal(await database.customExercises.count(), 0);
  assert.equal(await database.syncMeta.get("pull-cursor").then((item) => item?.value), 9);
});

async function openDatabase(accountId: string): Promise<AccountDatabase> {
  const database = new AccountDatabase(accountId);
  await database.open();
  databases.push(database);
  return database;
}

function outbox(type: string, id: string, sequence: number): OutboxRecord {
  return {
    mutationId: `${type}-mutation-${sequence}`,
    aggregateKey: `${type}:${id}`,
    sequence,
    status: "pending",
    createdAtUtc: `2026-10-01T00:00:0${sequence}.000Z`,
    payload: { operation: "update", baseVersion: 1, body: {} },
  };
}
