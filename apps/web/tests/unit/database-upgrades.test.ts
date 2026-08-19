import "fake-indexeddb/auto";
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import Dexie from "dexie";
import { createLocalAggregate } from "../../src/lib/offline/aggregate-envelope.ts";
import {
  AccountDatabase,
  accountDatabaseName,
  accountStoresV1,
  accountStoresV2,
  accountStoresV3,
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
  assert.equal(upgraded.verno, 3);
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
  assert.equal(reopened.verno, 3);
  assert.equal((await reopened.outbox.get("pending-before-failure"))?.status, "pending");
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

class FailingUpgradeDatabase extends Dexie {
  constructor(name: string) {
    super(name);
    this.version(1).stores(accountStoresV1);
    this.version(2).stores(accountStoresV2);
    this.version(3).stores(accountStoresV3);
    this.version(4).stores(accountStoresV3).upgrade(() => {
      throw new Error("Simulated upgrade failure");
    });
  }
}

function track<T extends Dexie>(database: T): T {
  openDatabases.push(database);
  return database;
}
