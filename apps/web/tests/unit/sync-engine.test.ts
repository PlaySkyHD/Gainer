import "fake-indexeddb/auto";
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import Dexie from "dexie";
import { changeWorkingCopy, createLocalAggregate, createServerAggregate } from "../../src/lib/offline/aggregate-envelope.ts";
import { AccountDatabase, type OutboxRecord } from "../../src/lib/offline/database.ts";
import {
  oldestReadyMutationPerAggregate,
  preparePendingMutations,
  runSync,
  SyncHttpError,
  type ClientRegistration,
  type PullResponse,
  type PushResponse,
  type SyncTransport,
} from "../../src/lib/offline/sync-engine.ts";
import { withSyncLease } from "../../src/lib/offline/sync-scheduler.ts";
import { createNutritionEntry, saveLocalNutritionDay } from "../../src/lib/offline/nutrition-tracking.ts";
import { saveNutritionTargetVersion, saveReusableMeal } from "../../src/lib/offline/smart-nutrition.ts";
import {
  acceptConflictServerState,
  retryConflictOnCurrentServerVersion,
} from "../../src/lib/offline/sync-conflicts.ts";

const databases: AccountDatabase[] = [];

afterEach(async () => {
  const current = databases.splice(0);
  current.forEach((database) => database.close());
  await Promise.all(current.map((database) => Dexie.delete(database.name)));
});

test("assigns durable monotone client sequences and chains same-aggregate dependencies", async () => {
  const database = await createDatabase();
  await database.outbox.bulkAdd([
    mutation("a1", "daily-check-in:a", 1, "2026-08-18T10:00:00Z"),
    mutation("b1", "daily-check-in:b", 1, "2026-08-18T10:01:00Z"),
    mutation("a2", "daily-check-in:a", 2, "2026-08-18T10:02:00Z"),
  ]);

  await preparePendingMutations(database);
  await preparePendingMutations(database);
  const records = await database.outbox.orderBy("clientSequence").toArray();
  assert.deepEqual(records.map((item) => item.clientSequence), [1, 2, 3]);
  assert.equal(records[2]?.dependsOnMutationId, "a1");
  assert.deepEqual((await oldestReadyMutationPerAggregate(database)).map((item) => item.mutationId), ["a1", "b1"]);
});

test("retryable failure backs off while an independent aggregate still uploads", async () => {
  const database = await createDatabase();
  await database.outbox.bulkAdd([
    mutation("fails", `daily-check-in:${crypto.randomUUID()}`, 1, "2026-08-18T10:00:00Z"),
    mutation("works", `daily-check-in:${crypto.randomUUID()}`, 1, "2026-08-18T10:01:00Z"),
  ]);
  const transport = new FakeTransport();
  transport.pushErrors.set("fails", new SyncHttpError(503, "http_503", "temporary"));

  const result = await runSync(database, transport, { now: new Date("2026-08-18T11:00:00Z") });
  assert.equal(result.pushed, 1);
  assert.equal((await database.outbox.get("fails"))?.status, "pending");
  assert.equal((await database.outbox.get("fails"))?.attemptCount, 1);
  assert.equal((await database.outbox.get("works"))?.status, "clean");
  assert.deepEqual(transport.pushed, ["fails", "works"]);
});

test("429 retries later while permanent validation and conflicts remain inspectable", async () => {
  const database = await createDatabase();
  await database.outbox.bulkAdd([
    mutation("rate", `daily-check-in:${crypto.randomUUID()}`, 1, "2026-08-18T10:00:00Z"),
    mutation("invalid", `daily-check-in:${crypto.randomUUID()}`, 1, "2026-08-18T10:01:00Z"),
    mutation("stale", `daily-check-in:${crypto.randomUUID()}`, 1, "2026-08-18T10:02:00Z"),
  ]);
  const transport = new FakeTransport();
  transport.pushErrors.set("rate", new SyncHttpError(429, "rate_limited", "later"));
  transport.pushErrors.set("invalid", new SyncHttpError(422, "validation_failed", "invalid"));
  transport.pushErrors.set("stale", new SyncHttpError(409, "stale_base_version", "changed"));

  await runSync(database, transport, { now: new Date("2026-08-18T11:00:00Z") });
  assert.equal((await database.outbox.get("rate"))?.status, "pending");
  assert.equal((await database.outbox.get("invalid"))?.status, "failed");
  assert.equal((await database.outbox.get("stale"))?.status, "conflict");
  assert.notEqual(await database.conflicts.get("stale"), undefined);
});

test("401 preserves every mutation and blocks further transport work", async () => {
  const database = await createDatabase();
  await database.outbox.bulkAdd([
    mutation("first", `daily-check-in:${crypto.randomUUID()}`, 1, "2026-08-18T10:00:00Z"),
    mutation("second", `daily-check-in:${crypto.randomUUID()}`, 1, "2026-08-18T10:01:00Z"),
  ]);
  const transport = new FakeTransport();
  transport.pushErrors.set("first", new SyncHttpError(401, "http_401", "signed out"));

  const result = await runSync(database, transport);
  assert.equal(result.state, "auth-blocked");
  assert.deepEqual((await database.outbox.toArray()).map((item) => item.status), ["auth-blocked", "auth-blocked"]);
  assert.deepEqual(transport.pushed, ["first"]);
});

test("pull applies a whole batch with its cursor atomically and identical retry is harmless", async () => {
  const database = await createDatabase();
  const resourceId = crypto.randomUUID();
  await database.checkIns.put({
    id: resourceId,
    envelope: createLocalAggregate(resourceId, {
      localDate: "2026-08-18", weightKg: 80, caloriesKcal: null, proteinGrams: null,
      carbohydrateGrams: null, fatGrams: null, steps: null, sleepMinutes: null,
      createdAtUtc: "2026-08-18T10:00:00Z", updatedAtUtc: "2026-08-18T10:00:00Z",
    }),
  });
  await database.outbox.add(mutation("origin", `daily-check-in:${resourceId}`, 1, "2026-08-18T10:00:00Z"));
  const batch = {
    batchId: crypto.randomUUID(), revision: 1, originMutationId: "origin",
    changes: [{
      resourceType: "DailyCheckIn", resourceId, version: 1, isTombstone: false,
      snapshot: {
        checkInId: resourceId, localDate: "2026-08-18",
        values: { weightKg: 80, caloriesKcal: null, proteinGrams: null, carbohydrateGrams: null, fatGrams: null, steps: null, sleepMinutes: null },
        createdAtUtc: "2026-08-18T10:00:00Z", updatedAtUtc: "2026-08-18T10:00:00Z", version: 1,
      },
    }],
  };
  const transport = new FakeTransport();
  transport.pullResponses = [
    { protocolVersion: 2, nextCursor: 1, hasMore: false, batches: [batch] },
    { protocolVersion: 2, nextCursor: 1, hasMore: false, batches: [batch] },
  ];

  await runSync(database, transport);
  assert.equal(await database.outbox.get("origin"), undefined);
  assert.equal((await database.syncMeta.get("pull-cursor"))?.value, 1);
  assert.equal((await database.checkIns.get(resourceId))?.envelope.serverVersion, 1);
  await database.syncMeta.put({ key: "pull-cursor", value: 0 });
  await runSync(database, transport);
  assert.equal((await database.checkIns.get(resourceId))?.envelope.serverVersion, 1);
  assert.equal(await database.conflicts.count(), 0);
});

test("older clients ignore an unknown resource type while still advancing the batch cursor", async () => {
  const database = await createDatabase();
  const transport = new FakeTransport();
  transport.pullResponses = [{
    protocolVersion: 2,
    nextCursor: 7,
    hasMore: false,
    batches: [{
      batchId: crypto.randomUUID(),
      revision: 7,
      originMutationId: null,
      changes: [{
        resourceType: "FutureResource",
        resourceId: crypto.randomUUID(),
        version: 1,
        isTombstone: false,
        snapshot: { value: "unknown to this client" },
      }],
    }],
  }];

  const result = await runSync(database, transport);

  assert.equal(result.pulledBatches, 1);
  assert.equal((await database.syncMeta.get("pull-cursor"))?.value, 7);
});

test("nutrition days map to full snapshot mutations and pull atomically", async () => {
  const database = await createDatabase();
  const entry = createNutritionEntry({
    meal: "Breakfast",
    position: 0,
    productName: "Oats",
    amountGrams: 150,
    per100Grams: { kilocalories: 370, proteinGrams: 13, carbohydrateGrams: 60, fatGrams: 7 },
  });
  const dayId = await saveLocalNutritionDay(database, "2026-08-19", [entry]);
  const transport = new FakeTransport();
  transport.pullResponses = [{
    protocolVersion: 2,
    nextCursor: 1,
    hasMore: false,
    batches: [{
      batchId: crypto.randomUUID(), revision: 1, originMutationId: (await database.outbox.toArray())[0]!.mutationId,
      changes: [{
        resourceType: "NutritionDay", resourceId: dayId, version: 1, isTombstone: false,
        snapshot: {
          nutritionDayId: dayId,
          localDate: "2026-08-19",
          entries: [entry],
          totals: entry.totals,
          createdAtUtc: "2026-08-19T10:00:00.000Z",
          updatedAtUtc: "2026-08-19T10:00:00.000Z",
          version: 1,
        },
      }],
    }],
  }];

  await runSync(database, transport);

  const request = transport.pushRequests[0] as {
    operation: string;
    resources: { resourceType: string }[];
    payload: { entries: { kilocaloriesPer100Grams: number }[] };
  };
  assert.equal(request.operation, "saveNutritionDay");
  assert.equal(request.resources[0]?.resourceType, "NutritionDay");
  assert.equal(request.payload.entries[0]?.kilocaloriesPer100Grams, 370);
  assert.equal((await database.nutritionDays.get(dayId))?.envelope.serverVersion, 1);
  assert.equal(await database.outbox.count(), 0);
});

test("reusable meals and target schedules map to additive typed sync operations", async () => {
  const database = await createDatabase();
  await saveReusableMeal(database, {
    name: "Rice bowl", description: null, standardPortion: 1,
    components: [{
      componentId: crypto.randomUUID(), position: 0, name: "Rice", brand: null, amountGrams: 200,
      totals: { kilocalories: 260, proteinGrams: 6, carbohydrateGrams: 56, fatGrams: 0.6 },
      per100Grams: { kilocalories: 130, proteinGrams: 3, carbohydrateGrams: 28, fatGrams: 0.3 }, source: null,
    }],
  });
  await saveNutritionTargetVersion(database, {
    targetVersionId: crypto.randomUUID(), name: "Cut", category: "Cut",
    effectiveFrom: "2026-09-01", effectiveUntil: null, inputMode: "Grams", kilocalories: 2500,
    proteinGrams: 180, carbohydrateGrams: 300, fatGrams: 70,
    proteinPercent: null, carbohydratePercent: null, fatPercent: null,
    origin: "Manual", algorithmVersion: null, reason: null,
  });
  const transport = new FakeTransport();

  await runSync(database, transport);

  const requests = transport.pushRequests as Array<{
    operation: string; resources: Array<{ resourceType: string }>;
    payload: Record<string, unknown>;
  }>;
  const meal = requests.find((item) => item.operation === "saveReusableMeal")!;
  const targets = requests.find((item) => item.operation === "saveNutritionTargetSchedule")!;
  assert.equal(meal.resources[0]?.resourceType, "ReusableMeal");
  assert.equal((meal.payload.components as Array<{ kilocaloriesPer100Grams: number }>)[0]?.kilocaloriesPer100Grams, 130);
  assert.equal(targets.resources[0]?.resourceType, "NutritionTargetSchedule");
  assert.equal((targets.payload.versions as Array<Record<string, unknown>>)[0]?.name, "Cut");
  assert.equal((targets.payload.versions as Array<Record<string, unknown>>)[0]?.inputMode, "Grams");
  assert.equal((targets.payload.versions as Array<{ kilocalories: number }>)[0]?.kilocalories, 2500);
});

test("pull storage failure rolls back every resource change and its cursor", async () => {
  const database = await createDatabase();
  const resourceId = crypto.randomUUID();
  await database.checkIns.put({ id: resourceId, envelope: createLocalAggregate(resourceId, { weightKg: 80 }) });
  await database.outbox.add(mutation("origin-failure", `daily-check-in:${resourceId}`, 1, "2026-08-18T10:00:00Z"));
  const transport = new FakeTransport();
  transport.pullResponses = [{
    protocolVersion: 2, nextCursor: 1, hasMore: false,
    batches: [{
      batchId: crypto.randomUUID(), revision: 1, originMutationId: "origin-failure",
      changes: [{
        resourceType: "DailyCheckIn", resourceId, version: 1, isTombstone: false,
        snapshot: {
          checkInId: resourceId, localDate: "2026-08-18", values: { weightKg: 80 },
          createdAtUtc: "2026-08-18T10:00:00Z", updatedAtUtc: "2026-08-18T10:00:00Z",
        },
      }],
    }],
  }];
  const rejectCursor = (_key: unknown, value: { key?: string }) => {
    if (value.key === "pull-cursor") throw new Error("simulated cursor commit failure");
  };
  database.syncMeta.hook("creating", rejectCursor);
  await assert.rejects(runSync(database, transport), /cursor commit failure/);
  database.syncMeta.hook("creating").unsubscribe(rejectCursor);

  assert.equal((await database.checkIns.get(resourceId))?.envelope.serverVersion, null);
  assert.notEqual(await database.outbox.get("origin-failure"), undefined);
  assert.equal(await database.syncMeta.get("pull-cursor"), undefined);
});

test("an IndexedDB lease prevents simultaneous sync work across tabs and expires safely", async () => {
  const database = await createDatabase();
  let release!: () => void;
  let announce!: () => void;
  const started = new Promise<void>((resolve) => { announce = resolve; });
  const hold = new Promise<void>((resolve) => { release = resolve; });
  const first = withSyncLease(database, "tab-a", async () => { announce(); await hold; return "done"; });
  await started;
  assert.equal(await withSyncLease(database, "tab-b", async () => "must-not-run"), undefined);
  release();
  assert.equal(await first, "done");
  assert.equal(await withSyncLease(database, "tab-b", async () => "now-runs"), "now-runs");
});

test("conflicts support explicit server acceptance or rebased retry but never tombstone resurrection", async () => {
  const database = await createDatabase();
  const id = crypto.randomUUID();
  const envelope = changeWorkingCopy(createServerAggregate(id, { weightKg: 80 }, 3), (draft) => {
    draft.weightKg = 81;
  });
  await database.checkIns.put({ id, envelope });
  await database.outbox.add({
    ...mutation("conflicted", `daily-check-in:${id}`, 1, "2026-08-18T10:00:00Z"),
    status: "conflict",
  });
  await database.conflicts.put({
    conflictId: "conflicted", aggregateKey: `daily-check-in:${id}`,
    createdAtUtc: "2026-08-18T10:01:00Z", detail: { code: "stale_base_version" },
  });
  const replacement = await retryConflictOnCurrentServerVersion(database, "conflicted");
  assert.notEqual(replacement, "conflicted");
  assert.equal(((await database.outbox.get(replacement))?.payload as { baseVersion: number }).baseVersion, 3);

  await database.outbox.update(replacement, { status: "conflict" });
  await database.conflicts.put({
    conflictId: replacement, aggregateKey: `daily-check-in:${id}`,
    createdAtUtc: "2026-08-18T10:02:00Z", detail: {},
  });
  await acceptConflictServerState(database, replacement);
  assert.deepEqual((await database.checkIns.get(id))?.envelope.workingCopy, { weightKg: 80 });
  assert.equal(await database.outbox.where("aggregateKey").equals(`daily-check-in:${id}`).count(), 0);

  await database.conflicts.put({
    conflictId: "deleted", aggregateKey: `daily-check-in:${id}`,
    createdAtUtc: "2026-08-18T10:03:00Z", detail: {},
  });
  await database.tombstones.put({
    resourceKey: `daily-check-in:${id}`, resourceType: "DailyCheckIn", resourceId: id, revision: 4,
  });
  await assert.rejects(retryConflictOnCurrentServerVersion(database, "deleted"), /gelöschte Ressource/);
});

function mutation(id: string, aggregateKey: string, sequence: number, createdAtUtc: string): OutboxRecord {
  return {
    mutationId: id,
    aggregateKey,
    sequence,
    status: "pending",
    createdAtUtc,
    payload: {
      operation: "create", baseVersion: null,
      body: { localDate: "2026-08-18", weightKg: 80 },
    },
  };
}

async function createDatabase(): Promise<AccountDatabase> {
  const database = new AccountDatabase(crypto.randomUUID());
  databases.push(database);
  await database.open();
  return database;
}

class FakeTransport implements SyncTransport {
  pushed: string[] = [];
  pushRequests: unknown[] = [];
  pushErrors = new Map<string, Error>();
  pullResponses: PullResponse[] = [];

  register(clientId: string): Promise<ClientRegistration> {
    return Promise.resolve({ clientId, isActiveWriter: true });
  }

  push(mutationId: string, request: unknown): Promise<PushResponse> {
    this.pushed.push(mutationId);
    this.pushRequests.push(request);
    const error = this.pushErrors.get(mutationId);
    return error
      ? Promise.reject(error)
      : Promise.resolve({ mutationId, replayed: false, revision: 1, resources: [] });
  }

  pull(after: number): Promise<PullResponse> {
    return Promise.resolve(this.pullResponses.shift() ?? {
      protocolVersion: 2, nextCursor: after, hasMore: false, batches: [],
    });
  }
}
