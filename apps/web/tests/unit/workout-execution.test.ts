import "fake-indexeddb/auto";
import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import Dexie from "dexie";
import { AccountDatabase } from "../../src/lib/offline/database.ts";
import { readTrainingPlanning, saveLocalRotation, saveLocalTemplate, type LocalTemplateItem } from "../../src/lib/offline/training-planning.ts";
import {
  addLocalWorkoutExercise,
  addLocalWorkoutSet,
  completeLocalWorkout,
  discardLocalWorkout,
  extendLocalRestTimer,
  moveLocalWorkoutExercise,
  mutateLocalWorkout,
  readLocalPreviousPerformance,
  readLocalWorkoutHistory,
  readLocalWorkoutHistoryDetail,
  restartLocalRestTimer,
  restTimerRemainingSeconds,
  readRunningWorkout,
  removeLocalWorkoutExercise,
  saveLocalWorkoutSet,
  skipLocalRestTimer,
  startLocalWorkout,
  WorkoutExecutionError,
  WorkoutInputError,
} from "../../src/lib/offline/workout-execution.ts";

const databases: AccountDatabase[] = [];
afterEach(async () => {
  const current = databases.splice(0);
  current.forEach((database) => database.close());
  await Promise.all(current.map((database) => Dexie.delete(database.name)));
});

test("offline start creates a complete immutable-origin snapshot that survives reload", async () => {
  const database = await createDatabase();
  const exercise = (await readTrainingPlanning(database)).exercises[0];
  assert.ok(exercise);
  const templateId = await saveLocalTemplate(database, {
    name: "Upper A",
    items: [item(exercise.id, 3, 6, 8, 2, 180, "controlled")],
  });
  const workoutId = await startLocalWorkout(database, templateId);

  database.close();
  await database.open();
  const workout = await readRunningWorkout(database);
  assert.equal(workout?.id, workoutId);
  assert.equal(workout?.templateNameSnapshot, "Upper A");
  assert.equal(workout?.exercises[0]?.exerciseNameSnapshot, exercise.name);
  assert.equal(workout?.exercises[0]?.sets.length, 3);
  assert.equal(workout?.exercises[0]?.restSeconds, 180);
  assert.equal(await database.outbox.filter((entry) => entry.aggregateKey === `workout:${workoutId}`).count(), 1);
});

test("missing and foreign-account templates cannot create a partial workout", async () => {
  const first = await createDatabase();
  const second = await createDatabase();
  const exercise = (await readTrainingPlanning(first)).exercises[0];
  assert.ok(exercise);
  const templateId = await saveLocalTemplate(first, { name: "Private", items: [item(exercise.id)] });

  await assert.rejects(startLocalWorkout(second, templateId), WorkoutExecutionError);
  await assert.rejects(startLocalWorkout(first, crypto.randomUUID()), WorkoutExecutionError);
  assert.equal(await second.workouts.count(), 0);
  assert.equal(await first.workouts.count(), 0);
  assert.equal(await second.outbox.filter((entry) => entry.aggregateKey.startsWith("workout:")).count(), 0);
});

test("incomplete local exercise resolution rejects start atomically", async () => {
  const database = await createDatabase();
  const exercise = (await readTrainingPlanning(database)).exercises[0];
  assert.ok(exercise);
  const templateId = await saveLocalTemplate(database, { name: "Plan", items: [item(exercise.id)] });
  await database.exerciseCatalog.delete(exercise.id);
  await assert.rejects(startLocalWorkout(database, templateId), WorkoutExecutionError);
  assert.equal(await database.workouts.count(), 0);
});

test("running workout edits sets and exercise order without changing its source template", async () => {
  const database = await createDatabase();
  const exercises = (await readTrainingPlanning(database)).exercises;
  const templateId = await saveLocalTemplate(database, { name: "Plan", items: [item(exercises[0]!.id)] });
  const workoutId = await startLocalWorkout(database, templateId);
  await addLocalWorkoutExercise(database, workoutId, exercises[1]!.id);
  let workout = await readRunningWorkout(database);
  assert.equal(workout?.exercises.length, 2);
  await moveLocalWorkoutExercise(database, workoutId, workout!.exercises[1]!.id, 0);
  workout = await readRunningWorkout(database);
  const firstExercise = workout!.exercises[0]!;
  await addLocalWorkoutSet(database, workoutId, firstExercise.id);
  const addedSet = (await readRunningWorkout(database))!.exercises[0]!.sets[1]!;
  await saveLocalWorkoutSet(database, workoutId, firstExercise.id, addedSet.id, {
    weightKg: 102.5, repetitions: 8, rir: 2, notes: "good",
  }, true);
  await removeLocalWorkoutExercise(database, workoutId, workout!.exercises[1]!.id);

  const changed = await readRunningWorkout(database);
  assert.equal(changed?.exercises.length, 1);
  assert.equal(changed?.exercises[0]?.sets[1]?.weightKg, 102.5);
  const source = (await readTrainingPlanning(database)).templates.find((entry) => entry.id === templateId);
  assert.equal(source?.items.length, 1);
  assert.equal(source?.items[0]?.plannedSets, 3);
});

test("invalid completed set leaves the last valid workout and outbox unchanged", async () => {
  const database = await createDatabase();
  const exercise = (await readTrainingPlanning(database)).exercises[0]!;
  const templateId = await saveLocalTemplate(database, { name: "Plan", items: [item(exercise.id)] });
  const workoutId = await startLocalWorkout(database, templateId);
  const workout = await readRunningWorkout(database);
  const exerciseSnapshot = workout!.exercises[0]!;
  const set = exerciseSnapshot.sets[0]!;
  const before = await database.outbox.count();
  await assert.rejects(saveLocalWorkoutSet(database, workoutId, exerciseSnapshot.id, set.id, {
    weightKg: -1, repetitions: 0, rir: 11, notes: null,
  }, true), WorkoutInputError);
  const unchanged = await readRunningWorkout(database);
  assert.equal(unchanged?.exercises[0]?.sets[0]?.isCompleted, false);
  assert.equal(await database.outbox.count(), before);
});

test("previous performance uses only the latest completed workout in the same account", async () => {
  const first = await createDatabase();
  const second = await createDatabase();
  const exercise = (await readTrainingPlanning(first)).exercises[0]!;
  const templateId = await saveLocalTemplate(first, { name: "Plan", items: [item(exercise.id, 1)] });
  const workoutId = await startLocalWorkout(first, templateId);
  const running = await readRunningWorkout(first);
  const exerciseSnapshot = running!.exercises[0]!;
  await saveLocalWorkoutSet(first, workoutId, exerciseSnapshot.id, exerciseSnapshot.sets[0]!.id, {
    weightKg: 100, repetitions: 8, rir: 2, notes: null,
  }, true);
  const completedAt = new Date(Date.now() + 1_000).toISOString();
  await mutateLocalWorkout(first, workoutId, "complete", (workout) => {
    workout.status = "completed";
    workout.completedAtUtc = completedAt;
  });

  const previous = await readLocalPreviousPerformance(first, exercise.id, new Date(Date.now() + 2_000).toISOString());
  assert.equal(previous?.workoutId, workoutId);
  assert.equal(previous?.sets[0]?.weightKg, 100);
  assert.equal(await first.analyticsCache.count(), 1);
  assert.equal(await readLocalPreviousPerformance(second, exercise.id, new Date(Date.now() + 2_000).toISOString()), undefined);
});

test("rest timer uses an absolute target, survives reload, and duplicate completion does not restart it", async () => {
  const database = await createDatabase();
  const exercise = (await readTrainingPlanning(database)).exercises[0]!;
  const templateId = await saveLocalTemplate(database, { name: "Timed", items: [item(exercise.id, 1, 8, 12, null, 180)] });
  const workoutId = await startLocalWorkout(database, templateId);
  let workout = await readRunningWorkout(database);
  const exerciseSnapshot = workout!.exercises[0]!;
  const set = exerciseSnapshot.sets[0]!;
  const start = new Date("2026-08-18T12:00:00.000Z");
  await saveLocalWorkoutSet(database, workoutId, exerciseSnapshot.id, set.id, {
    weightKg: 100, repetitions: 8, rir: null, notes: null,
  }, true, start);
  workout = await readRunningWorkout(database);
  assert.equal(workout?.restTimer?.targetAtUtc, "2026-08-18T12:03:00.000Z");

  await saveLocalWorkoutSet(database, workoutId, exerciseSnapshot.id, set.id, {
    weightKg: 100, repetitions: 8, rir: null, notes: null,
  }, true, new Date("2026-08-18T12:00:30.000Z"));
  database.close(); await database.open();
  workout = await readRunningWorkout(database);
  assert.equal(workout?.restTimer?.targetAtUtc, "2026-08-18T12:03:00.000Z");
  assert.equal(restTimerRemainingSeconds(workout!.restTimer, new Date("2026-08-18T12:02:00.000Z")), 60);

  workout = await extendLocalRestTimer(database, workoutId, 30) as typeof workout;
  assert.equal(workout?.restTimer?.targetAtUtc, "2026-08-18T12:03:30.000Z");
  workout = await restartLocalRestTimer(database, workoutId, new Date("2026-08-18T12:10:00.000Z")) as typeof workout;
  assert.equal(workout?.restTimer?.targetAtUtc, "2026-08-18T12:13:00.000Z");
  await skipLocalRestTimer(database, workoutId);
  assert.equal((await readRunningWorkout(database))?.restTimer, null);
});

test("completing a set without positive planned rest starts no timer", async () => {
  const database = await createDatabase();
  const exercise = (await readTrainingPlanning(database)).exercises[0]!;
  const templateId = await saveLocalTemplate(database, { name: "Untimed", items: [item(exercise.id, 1)] });
  const workoutId = await startLocalWorkout(database, templateId);
  const workout = await readRunningWorkout(database);
  const exerciseSnapshot = workout!.exercises[0]!;
  await saveLocalWorkoutSet(database, workoutId, exerciseSnapshot.id, exerciseSnapshot.sets[0]!.id, {
    weightKg: 0, repetitions: 10, rir: null, notes: null,
  }, true);
  assert.equal((await readRunningWorkout(database))?.restTimer, null);
});

test("completion advances rotation and writes one atomic multi-aggregate outbox entry", async () => {
  const database = await createDatabase();
  const exercises = (await readTrainingPlanning(database)).exercises;
  const firstTemplate = await saveLocalTemplate(database, { name: "First", items: [item(exercises[0]!.id, 1)] });
  const secondTemplate = await saveLocalTemplate(database, { name: "Second", items: [item(exercises[1]!.id, 1)] });
  await saveLocalRotation(database, [firstTemplate, secondTemplate]);
  const workoutId = await startLocalWorkout(database, firstTemplate);
  const workout = await readRunningWorkout(database);
  const exercise = workout!.exercises[0]!;
  const beforeEmpty = await database.outbox.count();
  await assert.rejects(completeLocalWorkout(database, workoutId), WorkoutInputError);
  assert.equal((await readRunningWorkout(database))?.id, workoutId);
  assert.equal(await database.outbox.count(), beforeEmpty);

  await saveLocalWorkoutSet(database, workoutId, exercise.id, exercise.sets[0]!.id, {
    weightKg: 100, repetitions: 8, rir: 2, notes: null,
  }, true);
  const beforeCompletion = await database.outbox.count();
  await completeLocalWorkout(database, workoutId, new Date("2026-08-18T13:00:00.000Z"));
  assert.equal(await database.outbox.count(), beforeCompletion + 1);
  const completion = await database.outbox.orderBy("createdAtUtc").last();
  assert.match(completion!.aggregateKey, /^workout:/);
  const planning = await readTrainingPlanning(database);
  assert.equal(planning.rotation?.lastCompletedTemplateId, firstTemplate);
  assert.equal(planning.nextTemplateId, secondTemplate);
  assert.equal(await readRunningWorkout(database), undefined);
});

test("failed completion outbox write rolls back workout, rotation, and cache together", async () => {
  const database = await createDatabase();
  const exercises = (await readTrainingPlanning(database)).exercises;
  const templateId = await saveLocalTemplate(database, { name: "First", items: [item(exercises[0]!.id, 1)] });
  await saveLocalRotation(database, [templateId]);
  const workoutId = await startLocalWorkout(database, templateId);
  const workout = await readRunningWorkout(database);
  const exercise = workout!.exercises[0]!;
  await saveLocalWorkoutSet(database, workoutId, exercise.id, exercise.sets[0]!.id, {
    weightKg: 100, repetitions: 8, rir: null, notes: null,
  }, true);
  const rejectCompletion = (_key: unknown, record: { aggregateKey: string; payload?: unknown }) => {
    if (record.aggregateKey.startsWith("workout:") && record.payload &&
        (record.payload as { operation?: string }).operation === "complete") throw new Error("simulated quota failure");
  };
  database.outbox.hook("creating", rejectCompletion);
  await assert.rejects(completeLocalWorkout(database, workoutId), /simulated quota failure/);
  database.outbox.hook("creating").unsubscribe(rejectCompletion);

  assert.equal((await readRunningWorkout(database))?.id, workoutId);
  assert.equal((await readTrainingPlanning(database)).rotation?.lastCompletedTemplateId, null);
  assert.equal(await database.analyticsCache.count(), 0);
});

test("history renders only copied snapshot data and rejects later regular edits", async () => {
  const database = await createDatabase();
  const other = await createDatabase();
  const exercise = (await readTrainingPlanning(database)).exercises[0]!;
  const templateItem = item(exercise.id, 1);
  const templateId = await saveLocalTemplate(database, { name: "Original plan", items: [templateItem] });
  const workoutId = await startLocalWorkout(database, templateId);
  const running = await readRunningWorkout(database);
  const exerciseSnapshot = running!.exercises[0]!;
  await saveLocalWorkoutSet(database, workoutId, exerciseSnapshot.id, exerciseSnapshot.sets[0]!.id, {
    weightKg: 80, repetitions: 10, rir: null, notes: null,
  }, true);
  await completeLocalWorkout(database, workoutId);
  await saveLocalTemplate(database, { id: templateId, name: "Renamed plan", items: [templateItem] });

  const history = await readLocalWorkoutHistory(database);
  const detail = await readLocalWorkoutHistoryDetail(database, workoutId);
  assert.equal(history[0]?.templateNameSnapshot, "Original plan");
  assert.equal(detail?.exercises[0]?.exerciseNameSnapshot, exercise.name);
  await assert.rejects(mutateLocalWorkout(database, workoutId, "update", () => undefined), WorkoutExecutionError);
  assert.equal(await readLocalWorkoutHistoryDetail(other, workoutId), undefined);
});

test("explicit discard is excluded from history, previous performance, and rotation progress", async () => {
  const database = await createDatabase();
  const exercise = (await readTrainingPlanning(database)).exercises[0]!;
  const templateId = await saveLocalTemplate(database, { name: "Plan", items: [item(exercise.id, 1)] });
  await saveLocalRotation(database, [templateId]);
  const workoutId = await startLocalWorkout(database, templateId);
  const running = await readRunningWorkout(database);
  const exerciseSnapshot = running!.exercises[0]!;
  await saveLocalWorkoutSet(database, workoutId, exerciseSnapshot.id, exerciseSnapshot.sets[0]!.id, {
    weightKg: 100, repetitions: 8, rir: null, notes: null,
  }, true);
  database.close(); await database.open();
  assert.equal((await readRunningWorkout(database))?.id, workoutId);
  await discardLocalWorkout(database, workoutId, new Date("2026-08-18T14:00:00.000Z"));

  assert.equal(await readRunningWorkout(database), undefined);
  assert.equal((await readLocalWorkoutHistory(database)).length, 0);
  assert.equal(await readLocalPreviousPerformance(database, exercise.id, "2026-08-19T00:00:00.000Z"), undefined);
  assert.equal((await readTrainingPlanning(database)).rotation?.lastCompletedTemplateId, null);
});

function item(
  exerciseId: string,
  plannedSets = 3,
  minimumRepetitions = 8,
  maximumRepetitions = 12,
  targetRir: number | null = null,
  restSeconds: number | null = null,
  notes: string | null = null,
): LocalTemplateItem {
  return { id: crypto.randomUUID(), exerciseId, plannedSets, minimumRepetitions, maximumRepetitions, targetRir, restSeconds, notes };
}

async function createDatabase() {
  const database = new AccountDatabase(crypto.randomUUID());
  databases.push(database);
  await database.open();
  return database;
}
