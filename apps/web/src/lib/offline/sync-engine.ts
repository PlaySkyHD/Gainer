import type { EntityTable } from "dexie";
import { createServerAggregate, type LocalAggregateEnvelope } from "./aggregate-envelope.ts";
import {
  getOrCreateInstallationId,
  type AccountDatabase,
  type LocalResourceRecord,
  type OutboxRecord,
} from "./database.ts";

export const syncProtocolVersion = 2;

export interface SyncResource {
  resourceType: string;
  resourceId: string;
  version: number;
  isTombstone: boolean;
  snapshot: unknown | null;
}

export interface SyncBatch {
  batchId: string;
  revision: number;
  originMutationId: string | null;
  changes: SyncResource[];
}

export interface PullResponse {
  protocolVersion: number;
  nextCursor: number;
  hasMore: boolean;
  batches: SyncBatch[];
}

export interface PushResponse {
  mutationId: string;
  replayed: boolean;
  revision: number;
  resources: SyncResource[];
}

export interface ClientRegistration {
  clientId: string;
  isActiveWriter: boolean;
}

export interface SyncTransport {
  register(clientId: string, takeOverWriting: boolean): Promise<ClientRegistration>;
  push(mutationId: string, request: unknown): Promise<PushResponse>;
  pull(after: number): Promise<PullResponse>;
}

export class SyncHttpError extends Error {
  readonly status: number;
  readonly code: string;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = "SyncHttpError";
    this.status = status;
    this.code = code;
  }
}

export interface SyncRunResult {
  state: "idle" | "synced" | "auth-blocked" | "inactive-client" | "upgrade-required";
  pushed: number;
  pulledBatches: number;
}

export async function runSync(
  database: AccountDatabase,
  transport: SyncTransport,
  options: { takeOverWriting?: boolean; now?: Date } = {},
): Promise<SyncRunResult> {
  const now = options.now ?? new Date();
  const clientId = await getOrCreateInstallationId();
  let registration: ClientRegistration;
  try {
    registration = await transport.register(clientId, options.takeOverWriting ?? false);
  } catch (error) {
    if (error instanceof SyncHttpError && error.code === "upgrade_required") {
      await markAll(database, "upgrade-required", error.code);
      return { state: "upgrade-required", pushed: 0, pulledBatches: 0 };
    }
    if (error instanceof SyncHttpError && error.status === 401) {
      await markAll(database, "auth-blocked", "authentication_required");
      return { state: "auth-blocked", pushed: 0, pulledBatches: 0 };
    }
    throw error;
  }
  if (!registration.isActiveWriter) {
    await markAll(database, "inactive-client", "inactive_client");
    return { state: "inactive-client", pushed: 0, pulledBatches: 0 };
  }

  const inactive = await database.outbox.where("status").equals("inactive-client").toArray();
  await database.outbox.bulkPut(inactive.map((item) => ({ ...item, status: "pending", lastErrorCode: null })));

  await preparePendingMutations(database);
  const candidates = await oldestReadyMutationPerAggregate(database, now);
  let pushed = 0;
  for (const mutation of candidates) {
    await database.outbox.update(mutation.mutationId, { status: "syncing", lastErrorCode: null });
    try {
      await transport.push(mutation.mutationId, pushRequest(mutation, clientId));
      await database.outbox.update(mutation.mutationId, {
        status: "clean", nextAttemptAtUtc: null, lastErrorCode: null,
      });
      pushed++;
    } catch (error) {
      const outcome = await handlePushFailure(database, mutation, error, now);
      if (outcome === "stop-auth") return { state: "auth-blocked", pushed, pulledBatches: 0 };
      if (outcome === "stop-inactive") return { state: "inactive-client", pushed, pulledBatches: 0 };
      if (outcome === "stop-upgrade") return { state: "upgrade-required", pushed, pulledBatches: 0 };
    }
  }

  let pulledBatches = 0;
  let hasMore = true;
  while (hasMore) {
    const cursor = Number((await database.syncMeta.get("pull-cursor"))?.value ?? 0);
    let response: PullResponse;
    try {
      response = await transport.pull(cursor);
    } catch (error) {
      if (error instanceof SyncHttpError && error.status === 401) {
        await markAll(database, "auth-blocked", "authentication_required");
        return { state: "auth-blocked", pushed, pulledBatches };
      }
      throw error;
    }
    for (const batch of response.batches) {
      await applyChangeBatch(database, batch);
      pulledBatches++;
    }
    if (response.batches.length === 0 && response.nextCursor !== cursor) {
      await database.syncMeta.put({ key: "pull-cursor", value: response.nextCursor });
    }
    hasMore = response.hasMore;
    if (response.batches.length === 0) break;
  }
  await database.syncMeta.put({ key: "last-sync-success-at", value: now.toISOString() });
  return { state: pushed || pulledBatches ? "synced" : "idle", pushed, pulledBatches };
}

export async function resumeAfterAuthentication(database: AccountDatabase): Promise<void> {
  const blocked = await database.outbox.where("status").equals("auth-blocked").toArray();
  await database.outbox.bulkPut(blocked.map((item) => ({ ...item, status: "pending", lastErrorCode: null })));
}

export async function preparePendingMutations(database: AccountDatabase): Promise<void> {
  await database.transaction("rw", database.outbox, database.syncMeta, async () => {
    const records = (await database.outbox.toArray()).sort(compareOutbox);
    let nextSequence = Number((await database.syncMeta.get("next-client-sequence"))?.value ?? 0);
    const lastByAggregate = new Map<string, string>();
    for (const record of records) {
      const remembered = await database.syncMeta.get(`last-mutation:${record.aggregateKey}`);
      const dependency = record.dependsOnMutationId ?? lastByAggregate.get(record.aggregateKey) ?? (String(remembered?.value ?? "") || null);
      if (record.clientSequence === undefined) {
        nextSequence++;
        await database.outbox.update(record.mutationId, {
          clientSequence: nextSequence,
          dependsOnMutationId: dependency,
          attemptCount: record.attemptCount ?? 0,
          nextAttemptAtUtc: record.nextAttemptAtUtc ?? null,
          lastErrorCode: record.lastErrorCode ?? null,
        });
      }
      lastByAggregate.set(record.aggregateKey, record.mutationId);
      await database.syncMeta.put({ key: `last-mutation:${record.aggregateKey}`, value: record.mutationId });
    }
    await database.syncMeta.put({ key: "next-client-sequence", value: nextSequence });
  });
}

export async function oldestReadyMutationPerAggregate(
  database: AccountDatabase,
  now: Date = new Date(),
): Promise<OutboxRecord[]> {
  const records = (await database.outbox.toArray()).sort(compareOutbox);
  const seen = new Set<string>();
  return records.filter((record) => {
    if (seen.has(record.aggregateKey)) return false;
    seen.add(record.aggregateKey);
    return record.status === "pending" && (!record.nextAttemptAtUtc || record.nextAttemptAtUtc <= now.toISOString());
  });
}

async function applyChangeBatch(database: AccountDatabase, batch: SyncBatch): Promise<void> {
  const tables = [
    database.syncMeta, database.outbox, database.conflicts, database.tombstones,
    database.goals, database.checkIns, database.customExercises, database.templates,
    database.rotation, database.workouts, database.nutritionDays,
  ] as const;
  await database.transaction("rw", tables, async () => {
    for (const change of batch.changes) await applyChange(database, batch, change);
    if (batch.originMutationId) await database.outbox.delete(batch.originMutationId);
    await database.syncMeta.put({ key: "pull-cursor", value: batch.revision });
  });
}

async function applyChange(database: AccountDatabase, batch: SyncBatch, change: SyncResource): Promise<void> {
  const mapping = resourceMapping(database, change.resourceType);
  if (!mapping) return;
  const aggregateKey = `${mapping.aggregateType}:${change.resourceId}`;
  if (change.isTombstone) {
    await mapping.table.delete(change.resourceId);
    await database.tombstones.put({
      resourceKey: aggregateKey,
      resourceType: change.resourceType,
      resourceId: change.resourceId,
      revision: batch.revision,
    });
    return;
  }
  const snapshot = normalizeSnapshot(change.resourceType, change.snapshot);
  const existing = await mapping.table.get(change.resourceId) as LocalResourceRecord | undefined;
  const otherPending = (await database.outbox.where("aggregateKey").equals(aggregateKey).toArray())
    .some((item) => item.mutationId !== batch.originMutationId && item.status !== "clean");
  if (existing && isImmutableHistory(change.resourceType, existing.envelope.workingCopy) &&
      !same(existing.envelope.workingCopy, snapshot)) {
    await database.conflicts.put({
      conflictId: `history:${change.resourceId}:${batch.revision}`,
      aggregateKey,
      createdAtUtc: new Date().toISOString(),
      detail: { code: "immutable_history", serverSnapshot: snapshot, serverVersion: change.version },
    });
    return;
  }
  const envelope: LocalAggregateEnvelope<unknown> = existing && otherPending
    ? {
        ...existing.envelope,
        serverSnapshot: structuredClone(snapshot),
        serverVersion: change.version,
        syncState: "pending",
      }
    : createServerAggregate(change.resourceId, snapshot, change.version);
  await mapping.table.put({ id: change.resourceId, envelope });
  if (batch.originMutationId) {
    const next = (await database.outbox.where("aggregateKey").equals(aggregateKey).toArray())
      .filter((item) => item.mutationId !== batch.originMutationId && item.status !== "clean")
      .sort(compareOutbox)[0];
    if (next) {
      const payload = next.payload as { operation: string; baseVersion: number | null; body: Record<string, unknown> };
      await database.outbox.update(next.mutationId, {
        payload: { ...payload, baseVersion: change.version },
      });
    }
  }
  await database.tombstones.delete(aggregateKey);
}

async function handlePushFailure(
  database: AccountDatabase,
  mutation: OutboxRecord,
  error: unknown,
  now: Date,
): Promise<"continue" | "stop-auth" | "stop-inactive" | "stop-upgrade"> {
  const http = error instanceof SyncHttpError ? error : null;
  if (http?.status === 401) {
    await markAll(database, "auth-blocked", "authentication_required");
    return "stop-auth";
  }
  if (http?.code === "inactive_client") {
    await markAll(database, "inactive-client", http.code);
    return "stop-inactive";
  }
  if (http?.code === "upgrade_required") {
    await markAll(database, "upgrade-required", http.code);
    return "stop-upgrade";
  }
  if (http?.status === 409) {
    await database.transaction("rw", database.outbox, database.conflicts, async () => {
      await database.outbox.update(mutation.mutationId, { status: "conflict", lastErrorCode: http.code });
      await database.conflicts.put({
        conflictId: mutation.mutationId,
        aggregateKey: mutation.aggregateKey,
        createdAtUtc: now.toISOString(),
        detail: { code: http.code, message: http.message, mutationId: mutation.mutationId },
      });
    });
    return "continue";
  }
  if (http?.status === 422) {
    await database.outbox.update(mutation.mutationId, { status: "failed", lastErrorCode: http.code });
    return "continue";
  }
  const attempts = (mutation.attemptCount ?? 0) + 1;
  const delay = Math.min(60_000, 1_000 * 2 ** Math.min(attempts - 1, 6));
  await database.outbox.update(mutation.mutationId, {
    status: "pending",
    attemptCount: attempts,
    nextAttemptAtUtc: new Date(now.getTime() + delay).toISOString(),
    lastErrorCode: http?.code ?? "transport_error",
  });
  return "continue";
}

async function markAll(
  database: AccountDatabase,
  status: OutboxRecord["status"],
  code: string,
): Promise<void> {
  await database.outbox.filter((item) =>
    ["pending", "syncing", "auth-blocked", "inactive-client", "upgrade-required"].includes(item.status))
    .modify({ status, lastErrorCode: code });
}

function pushRequest(record: OutboxRecord, clientId: string) {
  const { aggregateType, aggregateId } = splitAggregate(record.aggregateKey);
  const payload = record.payload as { operation: string; baseVersion: number | null; body: Record<string, unknown> };
  const baseVersion = payload.baseVersion ?? 0;
  const resourceType = serverResourceType(aggregateType);
  const resources = [{ resourceType, resourceId: aggregateId, baseVersion }];
  if (aggregateType === "body-goal" && payload.body.expectedActiveGoalId && payload.body.expectedActiveGoalVersion) {
    resources.push({
      resourceType: "BodyGoal",
      resourceId: String(payload.body.expectedActiveGoalId),
      baseVersion: Number(payload.body.expectedActiveGoalVersion),
    });
  }
  if (aggregateType === "workout" && payload.operation === "complete") {
    const rotation = payload.body.rotation as { id?: unknown; serverVersion?: unknown } | null;
    if (rotation?.id && rotation.serverVersion) {
      resources.push({ resourceType: "WorkoutRotation", resourceId: String(rotation.id), baseVersion: Number(rotation.serverVersion) });
    }
  }
  return {
    protocolVersion: syncProtocolVersion,
    clientId,
    clientSequence: record.clientSequence,
    operation: serverOperation(aggregateType, payload.operation, payload.body),
    resources,
    dependsOnMutationId: record.dependsOnMutationId ?? null,
    payload: serverPayload(aggregateType, aggregateId, payload.operation, baseVersion, payload.body),
  };
}

function serverOperation(type: string, operation: string, body: Record<string, unknown>): string {
  if (type === "body-goal") return "activateBodyGoal";
  if (type === "daily-check-in") return operation === "create" ? "createDailyCheckIn" : "correctDailyCheckIn";
  if (type === "custom-exercise") {
    if (operation === "create") return "createCustomExercise";
    return body.isArchived ? "archiveCustomExercise" : "updateCustomExercise";
  }
  if (type === "workout-template") return operation === "update" && body.isArchived ? "archiveWorkoutTemplate" : "saveWorkoutTemplate";
  if (type === "workout-rotation") return "saveWorkoutRotation";
  if (type === "workout") {
    if (operation === "create") return "startWorkout";
    if (operation === "complete") return "completeWorkout";
    if (operation === "discard") return "discardWorkout";
    return "editWorkout";
  }
  if (type === "nutrition-day") return operation === "delete" ? "deleteNutritionDay" : "saveNutritionDay";
  const suffix = type.split("-").map((part) => part[0]?.toUpperCase() + part.slice(1)).join("");
  return `${operation}${suffix}`;
}

function serverPayload(
  type: string,
  id: string,
  operation: string,
  baseVersion: number,
  body: Record<string, unknown>,
): unknown {
  if (type === "daily-check-in") {
    const values = {
      weightKg: body.weightKg,
      caloriesKcal: body.caloriesKcal,
      proteinGrams: body.proteinGrams,
      carbohydrateGrams: body.carbohydrateGrams,
      fatGrams: body.fatGrams,
      steps: body.steps,
      sleepMinutes: body.sleepMinutes,
    };
    return operation === "create"
      ? { checkInId: id, localDate: body.localDate, values }
      : { checkInId: id, baseVersion, values };
  }
  if (type === "custom-exercise") {
    if (operation !== "create" && body.isArchived) return { exerciseId: id, baseVersion };
    const values = {
      name: body.name,
      description: body.description,
      targetMuscle: body.targetMuscle,
      muscleGroup: body.muscleGroup,
      equipment: body.equipment,
    };
    return operation === "create" ? { exerciseId: id, values } : { exerciseId: id, baseVersion, values };
  }
  if (type === "body-goal") {
    return {
      goalId: id,
      kind: body.kind,
      startWeightKg: body.startWeightKg,
      targetWeightKg: body.targetWeightKg,
      startDate: body.startDate,
      targetDate: body.targetDate,
      expectedActiveGoalId: body.expectedActiveGoalId ?? null,
      expectedActiveGoalVersion: body.expectedActiveGoalVersion ?? null,
    };
  }
  if (type === "workout-template") {
    if (operation === "update" && body.isArchived) return { templateId: id, baseVersion };
    return {
      templateId: id,
      baseVersion,
      name: body.name,
      items: (body.items as Record<string, unknown>[]).map((item) => ({
        itemId: item.id,
        exerciseId: item.exerciseId,
        plannedSets: item.plannedSets,
        minimumRepetitions: item.minimumRepetitions,
        maximumRepetitions: item.maximumRepetitions,
        targetRir: item.targetRir,
        restSeconds: item.restSeconds,
        notes: item.notes,
      })),
    };
  }
  if (type === "workout-rotation") {
    return {
      rotationId: id,
      baseVersion,
      entries: (body.entries as Record<string, unknown>[]).map((entry) => ({
        itemId: entry.id,
        templateId: entry.templateId,
      })),
    };
  }
  if (type === "workout") {
    if (operation === "create") return { workoutId: id, templateId: body.sourceTemplateId };
    if (operation === "complete") {
      const completion = body as { rotation?: Record<string, unknown> | null };
      return {
        workoutId: id,
        baseVersion,
        rotationId: completion.rotation ? completion.rotation.id ?? null : null,
        rotationBaseVersion: completion.rotation ? completion.rotation.serverVersion ?? null : null,
      };
    }
    if (operation === "discard") return { workoutId: id, baseVersion };
    return {
      workoutId: id,
      baseVersion,
      exercises: (body.exercises as Record<string, unknown>[]).map((exercise) => ({
        workoutExerciseId: exercise.id,
        sourceExerciseId: exercise.sourceExerciseId,
        exerciseNameSnapshot: exercise.exerciseNameSnapshot,
        plannedSets: exercise.plannedSets,
        minimumRepetitions: exercise.minimumRepetitions,
        maximumRepetitions: exercise.maximumRepetitions,
        targetRir: exercise.targetRir,
        restSeconds: exercise.restSeconds,
        notes: exercise.notes,
        sets: (exercise.sets as Record<string, unknown>[]).map((set) => ({
          setId: set.id,
          weightKg: set.weightKg,
          repetitions: set.repetitions,
          rir: set.rir,
          notes: set.notes,
          isCompleted: set.isCompleted,
          completedAtUtc: set.completedAtUtc,
        })),
      })),
    };
  }
  if (type === "nutrition-day") {
    if (operation === "delete") return { nutritionDayId: id, baseVersion };
    return {
      nutritionDayId: id,
      localDate: body.localDate,
      baseVersion,
      entries: (body.entries as Record<string, unknown>[]).map((entry) => {
        const per100 = entry.per100Grams as Record<string, unknown>;
        return {
          entryId: entry.entryId,
          meal: entry.meal,
          position: entry.position,
          productName: entry.productName,
          brand: entry.brand,
          amountGrams: entry.amountGrams,
          kilocaloriesPer100Grams: per100.kilocalories,
          proteinGramsPer100Grams: per100.proteinGrams,
          carbohydrateGramsPer100Grams: per100.carbohydrateGrams,
          fatGramsPer100Grams: per100.fatGrams,
          source: entry.source,
        };
      }),
    };
  }
  return body;
}

function resourceMapping(database: AccountDatabase, type: string) {
  const values: Record<string, { table: EntityTable<LocalResourceRecord, "id">; aggregateType: string }> = {
    BodyGoal: { table: database.goals, aggregateType: "body-goal" },
    DailyCheckIn: { table: database.checkIns, aggregateType: "daily-check-in" },
    CustomExercise: { table: database.customExercises, aggregateType: "custom-exercise" },
    WorkoutTemplate: { table: database.templates, aggregateType: "workout-template" },
    WorkoutRotation: { table: database.rotation, aggregateType: "workout-rotation" },
    Workout: { table: database.workouts, aggregateType: "workout" },
    NutritionDay: { table: database.nutritionDays, aggregateType: "nutrition-day" },
  };
  return values[type];
}

function normalizeSnapshot(type: string, value: unknown): unknown {
  const snapshot = structuredClone(value) as Record<string, unknown>;
  if (type === "DailyCheckIn") {
    return {
      ...(snapshot.values as Record<string, unknown>),
      localDate: snapshot.localDate,
      createdAtUtc: snapshot.createdAtUtc,
      updatedAtUtc: snapshot.updatedAtUtc,
    };
  }
  if (type === "CustomExercise") {
    return {
      ...(snapshot.values as Record<string, unknown>),
      isArchived: snapshot.isArchived,
      createdAtUtc: snapshot.createdAtUtc,
      updatedAtUtc: snapshot.updatedAtUtc,
    };
  }
  if (type === "NutritionDay") {
    const copy = { ...snapshot };
    delete copy.version;
    delete copy.nutritionDayId;
    return copy;
  }
  const copy = { ...snapshot };
  delete copy.version;
  delete copy.goalId;
  delete copy.templateId;
  delete copy.rotationId;
  delete copy.workoutId;
  return copy;
}

function isImmutableHistory(type: string, value: unknown): boolean {
  return type === "Workout" && (value as { status?: string })?.status?.toLowerCase() === "completed";
}

function serverResourceType(type: string): string {
  const mapping: Record<string, string> = {
    "body-goal": "BodyGoal",
    "daily-check-in": "DailyCheckIn",
    "custom-exercise": "CustomExercise",
    "workout-template": "WorkoutTemplate",
    "workout-rotation": "WorkoutRotation",
    workout: "Workout",
    "nutrition-day": "NutritionDay",
  };
  const result = mapping[type];
  if (!result) throw new Error(`Der Aggregattyp ${type} kann nicht synchronisiert werden.`);
  return result;
}

function splitAggregate(value: string): { aggregateType: string; aggregateId: string } {
  const separator = value.lastIndexOf(":");
  if (separator < 1) throw new Error("Der Aggregatschlüssel ist ungültig.");
  return { aggregateType: value.slice(0, separator), aggregateId: value.slice(separator + 1) };
}

function compareOutbox(left: OutboxRecord, right: OutboxRecord): number {
  return left.createdAtUtc.localeCompare(right.createdAtUtc) ||
    left.aggregateKey.localeCompare(right.aggregateKey) || left.sequence - right.sequence;
}

function same(left: unknown, right: unknown): boolean {
  return JSON.stringify(left) === JSON.stringify(right);
}
