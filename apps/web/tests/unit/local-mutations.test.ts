import "fake-indexeddb/auto";
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import Dexie from "dexie";
import { changeWorkingCopy, createLocalAggregate } from "../../src/lib/offline/aggregate-envelope.ts";
import { AccountDatabase, type LocalResourceRecord } from "../../src/lib/offline/database.ts";
import {
  commitLocalMutation,
  pendingMutationsForAggregate,
  prepareLocalMutation,
} from "../../src/lib/offline/local-mutations.ts";

const databaseNames: string[] = [];
const databases: AccountDatabase[] = [];

afterEach(async () => {
  databases.splice(0).forEach((database) => database.close());
  await Promise.all(databaseNames.splice(0).map((name) => Dexie.delete(name)));
});

test("commits the working copy and immutable outbox entries in one transaction", async () => {
  const database = await createDatabase();
  const firstResource = goal("goal-1", 2_500);
  const sourcePayload = { calories: 2_500 };
  const firstMutation = prepareLocalMutation({
    aggregateType: "goal",
    aggregateId: firstResource.id,
    operation: "create",
    baseVersion: null,
    payload: sourcePayload,
  });
  sourcePayload.calories = 9_999;

  const firstOutbox = await commitLocalMutation(database, "goals", firstResource, firstMutation);
  const secondResource: LocalResourceRecord<{ calories: number }> = {
    id: firstResource.id,
    envelope: changeWorkingCopy(firstResource.envelope, (draft) => {
      draft.calories = 2_600;
    }),
  };
  const secondMutation = prepareLocalMutation({
    aggregateType: "goal",
    aggregateId: firstResource.id,
    operation: "update",
    baseVersion: null,
    payload: { calories: 2_600 },
  });
  await commitLocalMutation(database, "goals", secondResource, secondMutation);

  const pending = await pendingMutationsForAggregate(database, "goal:goal-1");
  assert.deepEqual(pending.map((entry) => entry.sequence), [1, 2]);
  assert.equal(firstOutbox.mutationId, firstMutation.mutationId);
  assert.deepEqual((pending[0].payload as { body: unknown }).body, { calories: 2_500 });
  assert.deepEqual((await database.goals.get("goal-1"))?.envelope.workingCopy, { calories: 2_600 });
});

test("an outbox quota error rolls back the aggregate write", async () => {
  const database = await createDatabase();
  database.outbox.hook("creating", () => {
    throw new DOMException("Simulated quota limit", "QuotaExceededError");
  });
  const resource = goal("goal-quota", 2_500);
  const mutation = prepareLocalMutation({
    aggregateType: "goal",
    aggregateId: resource.id,
    operation: "create",
    baseVersion: null,
    payload: resource.envelope.workingCopy,
  });

  await assert.rejects(commitLocalMutation(database, "goals", resource, mutation), {
    name: "QuotaExceededError",
  });
  assert.equal(await database.goals.get(resource.id), undefined);
  assert.equal(await database.outbox.count(), 0);
});

test("an aggregate-store error leaves no orphaned outbox record", async () => {
  const database = await createDatabase();
  database.goals.hook("creating", () => {
    throw new Error("Simulated aggregate write failure");
  });
  const resource = goal("goal-write-error", 2_500);
  const mutation = prepareLocalMutation({
    aggregateType: "goal",
    aggregateId: resource.id,
    operation: "create",
    baseVersion: null,
    payload: resource.envelope.workingCopy,
  });

  await assert.rejects(commitLocalMutation(database, "goals", resource, mutation));
  assert.equal(await database.goals.get(resource.id), undefined);
  assert.equal(await database.outbox.count(), 0);
});

function goal(id: string, calories: number): LocalResourceRecord<{ calories: number }> {
  return { id, envelope: createLocalAggregate(id, { calories }) };
}

async function createDatabase(): Promise<AccountDatabase> {
  const database = new AccountDatabase(crypto.randomUUID());
  databases.push(database);
  databaseNames.push(database.name);
  await database.open();
  return database;
}
