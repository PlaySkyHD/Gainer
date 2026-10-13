import "fake-indexeddb/auto";
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import Dexie from "dexie";
import { createLocalAggregate } from "../../src/lib/offline/aggregate-envelope.ts";
import { preparePendingMutations } from "../../src/lib/offline/sync-engine.ts";
import {
  AccountDatabase,
  accountDatabaseName,
  accountStoresV1,
  accountStoresV2,
  accountStoresV3,
  accountStoresV4,
  accountStoresV5,
  activateStagedAccountDatabase,
  deleteLocalAccountData,
  listLocalProfiles,
  openAccountDatabase,
  PendingLocalMutationsError,
} from "../../src/lib/offline/database.ts";

const openDatabases: Dexie[] = [];
const databaseNames: string[] = [];

afterEach(async () => {
  openDatabases.splice(0).forEach((database) => database.close());
  await Promise.all(databaseNames.splice(0).map((name) => Dexie.delete(name)));
});

test("version two upgrade preserves aggregate and pending outbox data", async () => {
  const accountId = crypto.randomUUID();
  const name = accountDatabaseName(accountId);
  databaseNames.push(name);
  const legacy = track(new LegacyAccountDatabase(name));
  await legacy.open();
  await legacy.table("goals").add({
    id: "goal-before-upgrade",
    envelope: createLocalAggregate("goal-before-upgrade", { calories: 2_500 }),
  });
  await legacy.table("outbox").add({
    mutationId: "mutation-before-upgrade",
    aggregateKey: "goal:goal-before-upgrade",
    sequence: 1,
    status: "pending",
    createdAtUtc: "2026-08-18T12:00:00.000Z",
    payload: { calories: 2_500 },
  });
  legacy.close();

  const upgraded = track(new AccountDatabase(accountId));
  await upgraded.open();

  assert.deepEqual((await upgraded.goals.get("goal-before-upgrade"))?.envelope.workingCopy, {
    calories: 2_500,
  });
  assert.equal((await upgraded.outbox.get("mutation-before-upgrade"))?.status, "pending");
  assert.equal(upgraded.verno, 5);
  assert.equal(await upgraded.nutritionDays.count(), 0);
  assert.equal(await upgraded.reusableMeals.count(), 0);
  assert.equal(await upgraded.nutritionTargetSchedules.count(), 0);
});

test("handover recovery upgrades v1 v2 v3 and v5 databases without dropping outbox tombstones or conflicts", async () => {
  for (const version of [1, 2, 3, 5] as const) {
    const accountId = crypto.randomUUID();
    const name = accountDatabaseName(accountId);
    databaseNames.push(name);
    const legacy = track(new LegacySchemaDatabase(name, version));
    await legacy.open();
    await legacy.table("outbox").add({
      mutationId: `syncing-v${version}`,
      aggregateKey: "daily-check-in:lost-response",
      sequence: 1,
      status: "syncing",
      createdAtUtc: "2026-10-12T10:00:00.000Z",
      payload: { operation: "create", body: { weightKg: 72 } },
    });
    await legacy.table("tombstones").put({
      resourceKey: "daily-check-in:deleted-on-server",
      resourceType: "DailyCheckIn",
      resourceId: "deleted-on-server",
      revision: 8,
    });
    await legacy.table("conflicts").put({
      conflictId: `conflict-v${version}`,
      aggregateKey: "daily-check-in:conflict",
      createdAtUtc: "2026-10-12T10:00:00.000Z",
      detail: { code: "stale_base_version" },
    });
    legacy.close();

    const upgraded = track(new AccountDatabase(accountId));
    await upgraded.open();
    assert.equal(upgraded.verno, 5);
    assert.equal((await upgraded.outbox.get(`syncing-v${version}`))?.status, "syncing");
    assert.equal((await upgraded.tombstones.get("daily-check-in:deleted-on-server"))?.revision, 8);
    assert.equal(await upgraded.conflicts.count(), 1);
    await preparePendingMutations(upgraded);
    const recovered = await upgraded.outbox.get(`syncing-v${version}`);
    assert.equal(recovered?.status, "syncing");
    assert.equal(recovered?.clientSequence, 1);
    assert.equal(recovered?.mutationId, `syncing-v${version}`);
    upgraded.close();
  }
});

test("a failed upgrade leaves the previous schema and outbox usable", async () => {
  const accountId = crypto.randomUUID();
  const name = accountDatabaseName(accountId);
  databaseNames.push(name);
  const current = track(new AccountDatabase(accountId));
  await current.open();
  await current.outbox.add({
    mutationId: "pending-before-failure",
    aggregateKey: "goal:one",
    sequence: 1,
    status: "pending",
    createdAtUtc: "2026-08-18T12:00:00.000Z",
    payload: {},
  });
  current.close();

  const failing = track(new FailingUpgradeDatabase(name));
  await assert.rejects(failing.open(), /simulated upgrade failure/i);
  failing.close();

  const reopened = track(new AccountDatabase(accountId));
  await reopened.open();
  assert.equal(reopened.verno, 5);
  assert.equal((await reopened.outbox.get("pending-before-failure"))?.status, "pending");
});

test("successful target cutover switches the active profile and retains the old outbox as recovery", async () => {
  const accountId = crypto.randomUUID();
  const original = track(await openAccountDatabase(accountId, "member@example.test"));
  const originalName = original.name;
  await original.outbox.add({
    mutationId: "preserve-in-old-recovery",
    aggregateKey: "daily-check-in:offline-only",
    sequence: 1,
    status: "pending",
    createdAtUtc: "2026-10-12T10:00:00.000Z",
    payload: { operation: "create", body: { weightKg: 70 } },
  });
  original.close();

  const stageName = `gainer-handover-stage-${accountId}-${crypto.randomUUID()}`;
  databaseNames.push(originalName, stageName);
  const stage = track(new AccountDatabase(accountId, stageName));
  await stage.open();
  await stage.syncMeta.put({ key: "pull-cursor", value: 12 });
  stage.close();

  await activateStagedAccountDatabase(accountId, "member@example.test", stageName);
  const active = track(await openAccountDatabase(accountId));
  assert.equal(active.name, stageName);
  assert.equal((await active.syncMeta.get("pull-cursor"))?.value, 12);
  active.close();
  const profile = (await listLocalProfiles()).find((item) => item.accountId === accountId);
  assert.deepEqual(profile?.recoveryDatabaseNames, [originalName]);

  const originalRecovery = track(new AccountDatabase(accountId, originalName));
  await originalRecovery.open();
  assert.equal((await originalRecovery.outbox.get("preserve-in-old-recovery"))?.status, "pending");
  originalRecovery.close();
  await assert.rejects(deleteLocalAccountData(accountId), (error) =>
    error instanceof PendingLocalMutationsError && error.pendingCount === 1);
  await deleteLocalAccountData(accountId, true);
  assert.equal((await indexedDB.databases()).some((entry) => entry.name === originalName), false);
  assert.equal((await indexedDB.databases()).some((entry) => entry.name === stageName), false);
});

test("local deletion requires explicit permission when mutations are pending", async () => {
  const accountId = crypto.randomUUID();
  const name = accountDatabaseName(accountId);
  databaseNames.push(name);
  const database = track(await openAccountDatabase(accountId));
  await database.outbox.add({
    mutationId: "must-not-disappear-silently",
    aggregateKey: "goal:one",
    sequence: 1,
    status: "pending",
    createdAtUtc: "2026-08-18T12:00:00.000Z",
    payload: {},
  });
  database.close();

  await assert.rejects(deleteLocalAccountData(accountId), (error) =>
    error instanceof PendingLocalMutationsError && error.pendingCount === 1);
  assert.equal((await listLocalProfiles()).some((profile) => profile.accountId === accountId), true);

  await deleteLocalAccountData(accountId, true);
  assert.equal((await indexedDB.databases()).some((entry) => entry.name === name), false);
  assert.equal((await listLocalProfiles()).some((profile) => profile.accountId === accountId), false);
});

class LegacyAccountDatabase extends Dexie {
  constructor(name: string) {
    super(name);
    this.version(1).stores(accountStoresV1);
  }
}

class LegacySchemaDatabase extends Dexie {
  constructor(name: string, version: 1 | 2 | 3 | 5) {
    super(name);
    this.version(1).stores(accountStoresV1);
    if (version >= 2) this.version(2).stores(accountStoresV2);
    if (version >= 3) this.version(3).stores(accountStoresV3);
    if (version >= 5) this.version(5).stores(accountStoresV5);
  }
}

class FailingUpgradeDatabase extends Dexie {
  constructor(name: string) {
    super(name);
    this.version(1).stores(accountStoresV1);
    this.version(2).stores(accountStoresV2);
    this.version(3).stores(accountStoresV3);
    this.version(4).stores(accountStoresV4);
    this.version(5).stores(accountStoresV5);
    this.version(6).stores(accountStoresV5).upgrade(() => {
      throw new Error("Simulated upgrade failure");
    });
  }
}

function track<T extends Dexie>(database: T): T {
  openDatabases.push(database);
  return database;
}
