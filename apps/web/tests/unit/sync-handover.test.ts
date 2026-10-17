import "fake-indexeddb/auto";
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import Dexie from "dexie";
import { AccountDatabase, listLocalProfiles, openAccountDatabase } from "../../src/lib/offline/database.ts";
import { changeWorkingCopy, createServerAggregate } from "../../src/lib/offline/aggregate-envelope.ts";
import { withLocalEditLock } from "../../src/lib/offline/handover-locks.ts";
import { pullReadOnlyToRevision, SyncHttpError, type PullResponse, type SyncTransport } from "../../src/lib/offline/sync-engine.ts";
import { type SyncHandoverTransport } from "../../src/lib/api/sync-handover-transport.ts";
import { saveLocalCheckIn } from "../../src/lib/offline/body-tracking.ts";
import { cancelPwaHandover, finishPwaHandoverTarget, type HandoverRecoveryTransports } from "../../src/lib/offline/sync-handover.ts";
import { createNutritionEntry, saveLocalNutritionDay } from "../../src/lib/offline/nutrition-tracking.ts";
import { acceptConflictServerState, retryConflictOnCurrentServerVersion } from "../../src/lib/offline/sync-conflicts.ts";

const databases: AccountDatabase[] = [];
afterEach(async () => {
  const opened = databases.splice(0);
  const names = [...new Set(opened.map((database) => database.name))];
  for (const database of opened) database.close();
  await Promise.all(names.map((name) => Dexie.delete(name)));
});

test("local writes serialize across tabs and stop after the handover freeze", async () => {
  const accountId = crypto.randomUUID();
  const first = await openDatabase(accountId);
  const second = await openDatabase(accountId);
  let active = 0;
  let maximumActive = 0;
  const write = (database: AccountDatabase) => withLocalEditLock(database, async () => {
    active++;
    maximumActive = Math.max(maximumActive, active);
    await new Promise((resolve) => setTimeout(resolve, 15));
    active--;
  });
  await Promise.all([write(first), write(second)]);
  assert.equal(maximumActive, 1);

  await first.syncMeta.put({ key: "handover-write-freeze", value: true });
  await assert.rejects(write(second), /eingefroren/i);
});

test("real body and nutrition writers reject edits after the source freeze", async () => {
  const database = await openDatabase(crypto.randomUUID());
  const beforeOutbox = await database.outbox.count();
  await database.syncMeta.put({ key: "handover-write-freeze", value: true });

  await assert.rejects(saveLocalCheckIn(database, {
    localDate: "2026-10-12", weightKg: 70, caloriesKcal: null, proteinGrams: null,
    carbohydrateGrams: null, fatGrams: null, steps: null, sleepMinutes: null,
  }), /eingefroren/i);
  await assert.rejects(saveLocalNutritionDay(database, "2026-10-12", [createNutritionEntry({
    meal: "Lunch", position: 0, productName: "Haferflocken", amountGrams: 100,
    per100Grams: { kilocalories: 370, proteinGrams: 13, carbohydrateGrams: 58, fatGrams: 7 },
  })]), /eingefroren/i);

  assert.equal(await database.checkIns.count(), 0);
  assert.equal(await database.nutritionDays.count(), 0);
  assert.equal(await database.outbox.count(), beforeOutbox);
});

test("conflict resolution cannot mutate the source after the handover freeze", async () => {
  const database = await openDatabase(crypto.randomUUID());
  const id = crypto.randomUUID();
  const envelope = changeWorkingCopy(createServerAggregate(id, { weightKg: 80 }, 3), (draft: { weightKg: number }) => {
    draft.weightKg = 81;
  });
  await database.checkIns.put({ id, envelope });
  await database.outbox.add({
    mutationId: "frozen-conflict", aggregateKey: `daily-check-in:${id}`, sequence: 1,
    status: "conflict", createdAtUtc: "2026-10-12T10:00:00Z",
    payload: { operation: "update", baseVersion: 2, body: { weightKg: 81 } },
  });
  await database.conflicts.put({
    conflictId: "frozen-conflict", aggregateKey: `daily-check-in:${id}`,
    createdAtUtc: "2026-10-12T10:01:00Z", detail: { code: "stale_base_version" },
  });
  await database.syncMeta.put({ key: "handover-write-freeze", value: true });

  await assert.rejects(acceptConflictServerState(database, "frozen-conflict"), /eingefroren/i);
  await assert.rejects(retryConflictOnCurrentServerVersion(database, "frozen-conflict"), /eingefroren/i);
  assert.equal(await database.outbox.get("frozen-conflict").then((value) => value?.status), "conflict");
  assert.ok(await database.conflicts.get("frozen-conflict"));
  assert.deepEqual((await database.checkIns.get(id))?.envelope.workingCopy, { weightKg: 81 });
});

test("read-only initial pull reaches the frozen revision without writer registration", async () => {
  const database = await openDatabase(crypto.randomUUID(), `gainer-stage-${crypto.randomUUID()}`);
  const response: PullResponse = {
    protocolVersion: 2,
    nextCursor: 1,
    hasMore: false,
    batches: [{
      batchId: crypto.randomUUID(),
      revision: 1,
      originMutationId: null,
      changes: [{
        resourceType: "DailyCheckIn",
        resourceId: crypto.randomUUID(),
        version: 1,
        isTombstone: false,
        snapshot: {
          localDate: "2026-10-12",
          values: { weightKg: 74.5 },
          createdAtUtc: "2026-10-12T08:00:00.000Z",
          updatedAtUtc: "2026-10-12T08:00:00.000Z",
        },
      }],
    }],
  };
  const pulledCursors: number[] = [];
  await pullReadOnlyToRevision(database, {
    async pull(after) {
      pulledCursors.push(after);
      return response;
    },
  }, 1);

  assert.deepEqual(pulledCursors, [0]);
  assert.equal(await database.syncMeta.get("pull-cursor").then((value) => value?.value), 1);
  const checkIn = await database.checkIns.toCollection().first();
  const workingCopy = checkIn?.envelope.workingCopy as { localDate: string; weightKg: number } | undefined;
  assert.equal(workingCopy?.localDate, "2026-10-12");
  assert.equal(workingCopy?.weightKg, 74.5);
  const secondStage = await openDatabase(crypto.randomUUID(), `gainer-stage-${crypto.randomUUID()}`);
  await assert.rejects(pullReadOnlyToRevision(secondStage, {
    pull: async () => ({ ...response, nextCursor: 2 }),
  }, 1), /änderte sich während/i);
});

test("cancel only releases a frozen source after the server confirms it is still writer", async () => {
  const database = await openDatabase(crypto.randomUUID());
  await database.syncMeta.put({ key: "handover-write-freeze", value: true });
  await database.syncMeta.put({
    key: "handover-recovery",
    value: {
      kind: "source", phase: "preparing", requestId: crypto.randomUUID(), oneTimeCode: "",
      frozenRevision: 4, targetClientId: crypto.randomUUID(),
    },
  });
  let beginAttempts = 0;
  const transports = recoveryTransports({
    async begin() {
      beginAttempts++;
      throw new SyncHttpError(409, "stale_revision", "revision changed");
    },
  }, { isActiveWriter: true });

  await cancelPwaHandover(database, transports);
  assert.equal(beginAttempts, 1);
  assert.equal(await database.syncMeta.get("handover-write-freeze"), undefined);
  assert.equal(await database.syncMeta.get("handover-recovery"), undefined);
});

test("cancel keeps source frozen when a lost Begin may have completed elsewhere", async () => {
  const database = await openDatabase(crypto.randomUUID());
  await database.syncMeta.put({ key: "handover-write-freeze", value: true });
  await database.syncMeta.put({
    key: "handover-recovery",
    value: {
      kind: "source", phase: "preparing", requestId: crypto.randomUUID(), oneTimeCode: "",
      frozenRevision: 4, targetClientId: crypto.randomUUID(),
    },
  });
  const transports = recoveryTransports({
    async begin() { throw new SyncHttpError(409, "handover_not_pending", "expired or consumed"); },
  }, { isActiveWriter: false });

  await assert.rejects(cancelPwaHandover(database, transports), /eingefroren/i);
  assert.equal((await database.syncMeta.get("handover-write-freeze"))?.value, true);
  assert.ok(await database.syncMeta.get("handover-recovery"));
});

test("completed replay for an inactive target never activates the staging profile", async () => {
  const accountId = crypto.randomUUID();
  const oldDatabase = await openDatabase(accountId);
  const profile = await openAccountDatabase(accountId, "member@example.test");
  const oldName = profile.name;
  profile.close();
  const stageName = `gainer-handover-stage-${accountId}-${crypto.randomUUID()}`;
  const handoverId = crypto.randomUUID();
  await oldDatabase.syncMeta.put({ key: "handover-write-freeze", value: true });
  await oldDatabase.syncMeta.put({
    key: "handover-recovery",
    value: {
      kind: "target", phase: "completing", handoverId, oneTimeCode: "recovery-code",
      frozenRevision: 0, targetClientId: crypto.randomUUID(), stageDatabaseName: stageName,
    },
  });
  const transports = recoveryTransports({
    async complete() {
      return {
        handoverId, targetClientId: crypto.randomUUID(), frozenRevision: 0,
        isActiveWriter: false, completedAtUtc: new Date().toISOString(),
      };
    },
  }, { isActiveWriter: false });

  await assert.rejects(finishPwaHandoverTarget(oldDatabase, transports), /kein aktiver Writer/i);
  assert.equal((await listLocalProfiles()).find((item) => item.accountId === accountId)?.databaseName, oldName);
  assert.equal((await oldDatabase.syncMeta.get("handover-write-freeze"))?.value, true);
  const stage = await openDatabase(accountId, stageName);
  assert.ok(stage.isOpen());
});

function recoveryTransports(
  handoverOverrides: Partial<SyncHandoverTransport>,
  registration: { isActiveWriter: boolean },
): HandoverRecoveryTransports {
  const sync = {
    async register() { return registration as never; },
    async pull() { throw new Error("unexpected pull"); },
    async push() { throw new Error("unexpected push"); },
  } as SyncTransport;
  const handover = {
    async begin() { throw new Error("unexpected begin"); },
    async complete() { throw new Error("unexpected complete"); },
    async cancel() { throw new Error("unexpected cancel"); },
    ...handoverOverrides,
  } as SyncHandoverTransport;
  return { sync, handover };
}

async function openDatabase(accountId: string, name?: string): Promise<AccountDatabase> {
  const database = new AccountDatabase(accountId, name);
  databases.push(database);
  await database.open();
  return database;
}
