import type { AccountDatabase, LocalResourceRecord, OutboxRecord } from "./database";
import { changeWorkingCopy, createLocalAggregate } from "./aggregate-envelope.ts";
import type { LocalCustomExercise, LocalWorkoutRotation, LocalWorkoutTemplate } from "./training-planning.ts";
import { prepareLocalMutation, type PreparedLocalMutation } from "./local-mutations.ts";
import { withLocalEditLock } from "./handover-locks.ts";

export type LocalWorkoutStatus = "running" | "completed" | "discarded";

export interface LocalWorkoutSet {
  id: string;
  position: number;
  weightKg: number | null;
  repetitions: number | null;
  rir: number | null;
  notes: string | null;
  isCompleted: boolean;
  completedAtUtc: string | null;
}

export interface LocalWorkoutExercise {
  id: string;
  sourceExerciseId: string | null;
  exerciseNameSnapshot: string;
  position: number;
  plannedSets: number;
  minimumRepetitions: number;
  maximumRepetitions: number;
  targetRir: number | null;
  restSeconds: number | null;
  notes: string | null;
  sets: LocalWorkoutSet[];
}

export interface LocalWorkout {
  sourceTemplateId: string | null;
  templateNameSnapshot: string;
  status: LocalWorkoutStatus;
  exercises: LocalWorkoutExercise[];
  startedAtUtc: string;
  completedAtUtc: string | null;
  discardedAtUtc: string | null;
  updatedAtUtc: string;
  restTimer: LocalRestTimer | null;
}

export interface LocalRestTimer {
  sourceSetId: string;
  durationSeconds: number;
  targetAtUtc: string;
}

export interface LocalPreviousPerformance {
  sourceExerciseId: string;
  workoutId: string;
  completedAtUtc: string;
  sets: { weightKg: number; repetitions: number; rir: number | null; position: number }[];
}

export class WorkoutExecutionError extends Error {}

export async function startLocalWorkout(database: AccountDatabase, templateId: string): Promise<string> {
  const running = await readRunningWorkout(database);
  if (running) throw new WorkoutExecutionError("Es läuft bereits ein Workout.");
  const templateRecord = await database.templates.get(templateId) as LocalResourceRecord<LocalWorkoutTemplate> | undefined;
  const template = templateRecord?.envelope.workingCopy;
  if (!template || template.isArchived || template.items.length === 0) {
    throw new WorkoutExecutionError("Das vollständige eigene Template ist lokal nicht verfügbar.");
  }

  const sourceIds = template.items.map((item) => item.exerciseId);
  const [catalog, custom] = await Promise.all([
    database.exerciseCatalog.bulkGet(sourceIds),
    database.customExercises.bulkGet(sourceIds) as Promise<(LocalResourceRecord<LocalCustomExercise> | undefined)[]>,
  ]);
  const names = sourceIds.map((_, index) => {
    const base = catalog[index]?.value as { name?: unknown } | undefined;
    const own = custom[index]?.envelope.workingCopy;
    return typeof base?.name === "string" && base.name.trim() ? base.name : own?.name.trim() || null;
  });
  if (names.some((name) => name === null)) {
    throw new WorkoutExecutionError("Mindestens eine Template-Übung ist lokal nicht vollständig verfügbar.");
  }

  const workoutId = crypto.randomUUID();
  const now = new Date().toISOString();
  const workout: LocalWorkout = {
    sourceTemplateId: templateId,
    templateNameSnapshot: template.name,
    status: "running",
    exercises: template.items.map((item, index) => ({
      id: crypto.randomUUID(),
      sourceExerciseId: item.exerciseId,
      exerciseNameSnapshot: names[index] as string,
      position: index,
      plannedSets: item.plannedSets,
      minimumRepetitions: item.minimumRepetitions,
      maximumRepetitions: item.maximumRepetitions,
      targetRir: item.targetRir,
      restSeconds: item.restSeconds,
      notes: item.notes,
      sets: Array.from({ length: item.plannedSets }, (_, position) => emptySet(position)),
    })),
    startedAtUtc: now,
    completedAtUtc: null,
    discardedAtUtc: null,
    updatedAtUtc: now,
    restTimer: null,
  };
  const mutation = prepareLocalMutation({
    aggregateType: "workout", aggregateId: workoutId, operation: "create", baseVersion: null, payload: workout,
  });
  await withLocalEditLock(database, () => database.transaction("rw", database.workouts, database.outbox, async () => {
    await database.workouts.add({ id: workoutId, envelope: createLocalAggregate(workoutId, workout) });
    await database.outbox.add(await outboxRecord(database, mutation));
  }));
  return workoutId;
}

export async function readRunningWorkout(database: AccountDatabase) {
  const records = await database.workouts.toArray() as LocalResourceRecord<LocalWorkout>[];
  const record = records.find((item) => item.envelope.workingCopy.status === "running");
  return record ? { id: record.id, ...record.envelope.workingCopy } : undefined;
}

export async function readWorkout(database: AccountDatabase, workoutId: string) {
  const record = await database.workouts.get(workoutId) as LocalResourceRecord<LocalWorkout> | undefined;
  return record ? { id: record.id, ...record.envelope.workingCopy } : undefined;
}

export async function readLocalWorkoutHistory(database: AccountDatabase) {
  const records = await database.workouts.toArray() as LocalResourceRecord<LocalWorkout>[];
  return records
    .filter((record) => record.envelope.workingCopy.status === "completed")
    .map((record) => ({ id: record.id, ...record.envelope.workingCopy }))
    .sort((left, right) => right.completedAtUtc!.localeCompare(left.completedAtUtc!));
}

export async function readLocalWorkoutHistoryDetail(database: AccountDatabase, workoutId: string) {
  const workout = await readWorkout(database, workoutId);
  return workout?.status === "completed" ? workout : undefined;
}

export async function readLocalPreviousPerformance(
  database: AccountDatabase,
  sourceExerciseId: string,
  beforeUtc: string,
): Promise<LocalPreviousPerformance | undefined> {
  const records = await database.workouts.toArray() as LocalResourceRecord<LocalWorkout>[];
  const candidates = records
    .filter((record) => {
      const workout = record.envelope.workingCopy;
      return workout.status === "completed" && Boolean(workout.completedAtUtc) && workout.completedAtUtc! < beforeUtc &&
        workout.exercises.some((exercise) => exercise.sourceExerciseId === sourceExerciseId);
    })
    .sort((left, right) => right.envelope.workingCopy.completedAtUtc!.localeCompare(left.envelope.workingCopy.completedAtUtc!));
  const record = candidates[0];
  if (!record) return undefined;
  const workout = record.envelope.workingCopy;
  const exercise = workout.exercises.find((item) => item.sourceExerciseId === sourceExerciseId)!;
  const result: LocalPreviousPerformance = {
    sourceExerciseId,
    workoutId: record.id,
    completedAtUtc: workout.completedAtUtc!,
    sets: exercise.sets.filter((set) => set.isCompleted && set.weightKg !== null && set.repetitions !== null)
      .map((set) => ({ weightKg: set.weightKg!, repetitions: set.repetitions!, rir: set.rir, position: set.position })),
  };
  await database.analyticsCache.put({
    key: `previous-performance:${sourceExerciseId}`,
    asOfRevision: record.envelope.optimisticVersion,
    value: result,
  });
  return result;
}

export interface WorkoutSetInput {
  weightKg: number | null;
  repetitions: number | null;
  rir: number | null;
  notes: string | null;
}

export async function addLocalWorkoutExercise(
  database: AccountDatabase,
  workoutId: string,
  exerciseId: string,
): Promise<void> {
  const [catalog, custom] = await Promise.all([
    database.exerciseCatalog.get(exerciseId),
    database.customExercises.get(exerciseId) as Promise<LocalResourceRecord<LocalCustomExercise> | undefined>,
  ]);
  const base = catalog?.value as { name?: unknown } | undefined;
  const customValue = custom?.envelope.workingCopy;
  const name = typeof base?.name === "string" ? base.name : customValue && !customValue.isArchived ? customValue.name : null;
  if (!name) throw new WorkoutExecutionError("Die Übung ist nicht verfügbar.");
  await mutateLocalWorkout(database, workoutId, "update", (workout) => {
    workout.exercises.push({
      id: crypto.randomUUID(), sourceExerciseId: exerciseId, exerciseNameSnapshot: name,
      position: workout.exercises.length, plannedSets: 1,
      minimumRepetitions: 1, maximumRepetitions: 1,
      targetRir: null, restSeconds: null, notes: null, sets: [emptySet(0)],
    });
  });
}

export async function removeLocalWorkoutExercise(database: AccountDatabase, workoutId: string, workoutExerciseId: string) {
  await mutateLocalWorkout(database, workoutId, "update", (workout) => {
    const originalLength = workout.exercises.length;
    workout.exercises = workout.exercises.filter((item) => item.id !== workoutExerciseId);
    if (workout.exercises.length === originalLength) throw new WorkoutExecutionError("Die Workout-Übung ist nicht verfügbar.");
    workout.exercises.forEach((item, position) => { item.position = position; });
  });
}

export async function moveLocalWorkoutExercise(
  database: AccountDatabase, workoutId: string, workoutExerciseId: string, targetPosition: number,
) {
  await mutateLocalWorkout(database, workoutId, "update", (workout) => {
    reorder(workout.exercises, workoutExerciseId, targetPosition);
  });
}

export async function addLocalWorkoutSet(database: AccountDatabase, workoutId: string, workoutExerciseId: string) {
  await mutateLocalWorkout(database, workoutId, "update", (workout) => {
    const exercise = requireExercise(workout, workoutExerciseId);
    exercise.sets.push(emptySet(exercise.sets.length));
  });
}

export async function removeLocalWorkoutSet(
  database: AccountDatabase, workoutId: string, workoutExerciseId: string, setId: string,
) {
  await mutateLocalWorkout(database, workoutId, "update", (workout) => {
    const exercise = requireExercise(workout, workoutExerciseId);
    const originalLength = exercise.sets.length;
    exercise.sets = exercise.sets.filter((item) => item.id !== setId);
    if (exercise.sets.length === originalLength) throw new WorkoutExecutionError("Der Satz ist nicht verfügbar.");
    exercise.sets.forEach((item, position) => { item.position = position; });
  });
}

export async function moveLocalWorkoutSet(
  database: AccountDatabase, workoutId: string, workoutExerciseId: string, setId: string, targetPosition: number,
) {
  await mutateLocalWorkout(database, workoutId, "update", (workout) => {
    reorder(requireExercise(workout, workoutExerciseId).sets, setId, targetPosition);
  });
}

export async function saveLocalWorkoutSet(
  database: AccountDatabase,
  workoutId: string,
  workoutExerciseId: string,
  setId: string,
  input: WorkoutSetInput,
  complete: boolean,
  now: Date = new Date(),
): Promise<LocalWorkout> {
  validateSet(input, complete);
  return mutateLocalWorkout(database, workoutId, "update", (workout) => {
    const set = requireExercise(workout, workoutExerciseId).sets.find((item) => item.id === setId);
    if (!set) throw new WorkoutExecutionError("Der Satz ist nicht verfügbar.");
    const wasCompleted = set.isCompleted;
    Object.assign(set, {
      ...input,
      notes: input.notes?.trim() || null,
      isCompleted: complete,
      completedAtUtc: complete ? set.completedAtUtc ?? now.toISOString() : null,
    });
    const exercise = requireExercise(workout, workoutExerciseId);
    if (complete && !wasCompleted && exercise.restSeconds && exercise.restSeconds > 0) {
      workout.restTimer = {
        sourceSetId: setId,
        durationSeconds: exercise.restSeconds,
        targetAtUtc: new Date(now.getTime() + exercise.restSeconds * 1_000).toISOString(),
      };
    }
  });
}

export function restTimerRemainingSeconds(timer: LocalRestTimer | null, now: Date = new Date()): number | null {
  if (!timer) return null;
  return Math.max(0, Math.ceil((new Date(timer.targetAtUtc).getTime() - now.getTime()) / 1_000));
}

export async function extendLocalRestTimer(database: AccountDatabase, workoutId: string, seconds = 30) {
  if (!Number.isInteger(seconds) || seconds < 1 || seconds > 3_600) throw new WorkoutExecutionError("Die Timer-Verlängerung ist ungültig.");
  return mutateLocalWorkout(database, workoutId, "update", (workout) => {
    if (!workout.restTimer) throw new WorkoutExecutionError("Es läuft kein Pausentimer.");
    workout.restTimer.targetAtUtc = new Date(new Date(workout.restTimer.targetAtUtc).getTime() + seconds * 1_000).toISOString();
  });
}

export async function restartLocalRestTimer(database: AccountDatabase, workoutId: string, now: Date = new Date()) {
  return mutateLocalWorkout(database, workoutId, "update", (workout) => {
    if (!workout.restTimer) throw new WorkoutExecutionError("Es läuft kein Pausentimer.");
    workout.restTimer.targetAtUtc = new Date(now.getTime() + workout.restTimer.durationSeconds * 1_000).toISOString();
  });
}

export async function skipLocalRestTimer(database: AccountDatabase, workoutId: string) {
  return mutateLocalWorkout(database, workoutId, "update", (workout) => { workout.restTimer = null; });
}

export async function completeLocalWorkout(
  database: AccountDatabase,
  workoutId: string,
  now: Date = new Date(),
): Promise<LocalWorkout> {
  let completed: LocalWorkout | undefined;
  await database.transaction(
    "rw",
    database.workouts,
    database.rotation,
    database.analyticsCache,
    database.outbox,
    async () => {
      const record = await database.workouts.get(workoutId) as LocalResourceRecord<LocalWorkout> | undefined;
      if (!record) throw new WorkoutExecutionError("Das Workout ist nicht verfügbar.");
      const current = record.envelope.workingCopy;
      if (current.status !== "running") throw new WorkoutExecutionError("Nur ein laufendes Workout kann abgeschlossen werden.");
      if (!current.exercises.some((exercise) => exercise.sets.some((set) => set.isCompleted))) {
        throw new WorkoutInputError({ workout: "Mindestens ein abgeschlossener Satz ist erforderlich." });
      }
      const changed = { ...record, envelope: changeWorkingCopy(record.envelope, (draft) => {
        draft.status = "completed";
        draft.completedAtUtc = now.toISOString();
        draft.restTimer = null;
        draft.updatedAtUtc = now.toISOString();
      }) };
      await database.workouts.put(changed);

      const rotationRecord = await database.rotation.toCollection().first() as LocalResourceRecord<LocalWorkoutRotation> | undefined;
      let changedRotation: typeof rotationRecord;
      if (rotationRecord && current.sourceTemplateId &&
          rotationRecord.envelope.workingCopy.entries.some((entry) => entry.templateId === current.sourceTemplateId)) {
        changedRotation = { ...rotationRecord, envelope: changeWorkingCopy(rotationRecord.envelope, (draft) => {
          draft.lastCompletedTemplateId = current.sourceTemplateId;
          draft.updatedAtUtc = now.toISOString();
        }) };
        await database.rotation.put(changedRotation);
      }

      for (const exercise of changed.envelope.workingCopy.exercises) {
        if (!exercise.sourceExerciseId) continue;
        const sets = exercise.sets.filter((set) => set.isCompleted && set.weightKg !== null && set.repetitions !== null)
          .map((set) => ({ weightKg: set.weightKg!, repetitions: set.repetitions!, rir: set.rir, position: set.position }));
        if (sets.length > 0) {
          await database.analyticsCache.put({
            key: `previous-performance:${exercise.sourceExerciseId}`,
            asOfRevision: changed.envelope.optimisticVersion,
            value: { sourceExerciseId: exercise.sourceExerciseId, workoutId, completedAtUtc: now.toISOString(), sets },
          });
        }
      }
      const mutation = prepareLocalMutation({
        aggregateType: "workout",
        aggregateId: workoutId,
        operation: "complete",
        baseVersion: record.envelope.serverVersion,
        payload: {
          workout: changed.envelope.workingCopy,
          rotation: changedRotation ? {
            id: changedRotation.id,
            serverVersion: rotationRecord?.envelope.serverVersion ?? null,
            value: changedRotation.envelope.workingCopy,
          } : null,
        },
      });
      await database.outbox.add(await outboxRecord(database, mutation));
      completed = changed.envelope.workingCopy;
    },
  );
  return completed as LocalWorkout;
}

export async function discardLocalWorkout(
  database: AccountDatabase,
  workoutId: string,
  now: Date = new Date(),
): Promise<LocalWorkout> {
  return mutateLocalWorkout(database, workoutId, "discard", (workout) => {
    workout.status = "discarded";
    workout.discardedAtUtc = now.toISOString();
    workout.restTimer = null;
  });
}

function emptySet(position: number): LocalWorkoutSet {
  return {
    id: crypto.randomUUID(), position, weightKg: null, repetitions: null,
    rir: null, notes: null, isCompleted: false, completedAtUtc: null,
  };
}

function validateSet(input: WorkoutSetInput, complete: boolean) {
  const fields: Record<string, string> = {};
  if (input.weightKg !== null && (!Number.isFinite(input.weightKg) || input.weightKg < 0)) fields.weightKg = "Das Gewicht darf nicht negativ sein.";
  if (input.repetitions !== null && (!Number.isInteger(input.repetitions) || input.repetitions < 1)) fields.repetitions = "Wiederholungen müssen positiv und ganzzahlig sein.";
  if (input.rir !== null && (!Number.isFinite(input.rir) || input.rir < 0 || input.rir > 10)) fields.rir = "RIR muss zwischen 0 und 10 liegen.";
  if ((input.notes?.trim().length ?? 0) > 2_000) fields.notes = "Die Notiz ist zu lang.";
  if (complete && input.weightKg === null) fields.weightKg = "Für einen abgeschlossenen Satz ist Gewicht erforderlich.";
  if (complete && input.repetitions === null) fields.repetitions = "Für einen abgeschlossenen Satz sind Wiederholungen erforderlich.";
  if (Object.keys(fields).length) throw new WorkoutInputError(fields);
}

export class WorkoutInputError extends WorkoutExecutionError {
  readonly fields: Readonly<Record<string, string>>;
  constructor(fields: Readonly<Record<string, string>>) {
    super("Der Satz ist ungültig.");
    this.fields = fields;
  }
}

function requireExercise(workout: LocalWorkout, workoutExerciseId: string) {
  const exercise = workout.exercises.find((item) => item.id === workoutExerciseId);
  if (!exercise) throw new WorkoutExecutionError("Die Workout-Übung ist nicht verfügbar.");
  return exercise;
}

function reorder<T extends { id: string; position: number }>(items: T[], id: string, targetPosition: number) {
  const source = items.findIndex((item) => item.id === id);
  if (source < 0 || !Number.isInteger(targetPosition) || targetPosition < 0 || targetPosition >= items.length) {
    throw new WorkoutExecutionError("Die neue Position ist ungültig.");
  }
  const [item] = items.splice(source, 1);
  if (item) items.splice(targetPosition, 0, item);
  items.forEach((entry, position) => { entry.position = position; });
}

async function outboxRecord(database: AccountDatabase, mutation: PreparedLocalMutation): Promise<OutboxRecord> {
  const prior = await database.outbox.where("aggregateKey").equals(mutation.aggregateKey).toArray();
  return {
    mutationId: mutation.mutationId,
    aggregateKey: mutation.aggregateKey,
    sequence: prior.reduce((highest, item) => Math.max(highest, item.sequence), 0) + 1,
    status: "pending",
    createdAtUtc: mutation.createdAtUtc,
    payload: { operation: mutation.operation, baseVersion: mutation.baseVersion, body: mutation.payload },
  };
}

export async function mutateLocalWorkout(
  database: AccountDatabase,
  workoutId: string,
  operation: "update" | "complete" | "discard",
  mutate: (workout: LocalWorkout) => void,
): Promise<LocalWorkout> {
  let result: LocalWorkout | undefined;
  await withLocalEditLock(database, () => database.transaction("rw", database.workouts, database.outbox, async () => {
    const record = await database.workouts.get(workoutId) as LocalResourceRecord<LocalWorkout> | undefined;
    if (!record) throw new WorkoutExecutionError("Das Workout ist nicht verfügbar.");
    if (record.envelope.workingCopy.status !== "running") throw new WorkoutExecutionError("Historische Workouts sind unveränderlich.");
    const changed = { ...record, envelope: changeWorkingCopy(record.envelope, (draft) => {
      mutate(draft);
      draft.updatedAtUtc = new Date().toISOString();
    }) };
    const mutation = prepareLocalMutation({
      aggregateType: "workout", aggregateId: workoutId, operation,
      baseVersion: record.envelope.serverVersion, payload: changed.envelope.workingCopy,
    });
    await database.workouts.put(changed);
    await database.outbox.add(await outboxRecord(database, mutation));
    result = changed.envelope.workingCopy;
  }));
  return result as LocalWorkout;
}
