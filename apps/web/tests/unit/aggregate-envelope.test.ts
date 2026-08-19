import assert from "node:assert/strict";
import { test } from "node:test";
import {
  changeWorkingCopy,
  createLocalAggregate,
  createServerAggregate,
  restoreServerSnapshot,
} from "../../src/lib/offline/aggregate-envelope.ts";

test("multiple offline changes preserve the server snapshot and advance optimistic versions", () => {
  const initial = createServerAggregate("goal-1", { calories: 2_400, tags: ["server"] }, 7);
  const firstChange = changeWorkingCopy(initial, (draft) => {
    draft.calories = 2_500;
    draft.tags.push("first");
  });
  const secondChange = changeWorkingCopy(firstChange, (draft) => {
    draft.calories = 2_600;
    draft.tags.push("second");
  });

  assert.deepEqual(secondChange.serverSnapshot, { calories: 2_400, tags: ["server"] });
  assert.deepEqual(secondChange.workingCopy, {
    calories: 2_600,
    tags: ["server", "first", "second"],
  });
  assert.equal(secondChange.serverVersion, 7);
  assert.equal(secondChange.optimisticVersion, 9);
  assert.equal(secondChange.syncState, "pending");
  assert.notStrictEqual(secondChange.serverSnapshot, secondChange.workingCopy);
});

test("a local aggregate has no invented server version", () => {
  const aggregate = createLocalAggregate("check-in-1", { weightKg: 82.5 });
  assert.equal(aggregate.serverSnapshot, null);
  assert.equal(aggregate.serverVersion, null);
  assert.equal(aggregate.optimisticVersion, 1);
  assert.equal(aggregate.syncState, "pending");
});

test("restoring a server-backed aggregate discards only local working changes", () => {
  const changed = changeWorkingCopy(createServerAggregate("goal-1", { calories: 2_400 }, 3), (draft) => {
    draft.calories = 2_700;
  });
  assert.deepEqual(restoreServerSnapshot(changed), createServerAggregate("goal-1", { calories: 2_400 }, 3));
  assert.throws(() => restoreServerSnapshot(createLocalAggregate("new", { calories: 2_400 })));
});
