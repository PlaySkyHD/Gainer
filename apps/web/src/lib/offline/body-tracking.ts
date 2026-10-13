import type { AccountDatabase, LocalResourceRecord, OutboxRecord } from "./database";
import { changeWorkingCopy, createLocalAggregate } from "./aggregate-envelope.ts";
import { prepareLocalMutation, type PreparedLocalMutation } from "./local-mutations.ts";
import { withLocalEditLock } from "./handover-locks.ts";

export type GoalKind = "Bulk" | "Maintain" | "Cut";

export interface LocalBodyGoal {
  kind: GoalKind;
  startWeightKg: number;
  targetWeightKg: number;
  startDate: string;
  targetDate: string | null;
  createdAtUtc: string;
  endedAtUtc: string | null;
}

export interface LocalDailyCheckIn {
  localDate: string;
  weightKg: number;
  caloriesKcal: number | null;
  proteinGrams: number | null;
  carbohydrateGrams: number | null;
  fatGrams: number | null;
  steps: number | null;
  sleepMinutes: number | null;
  createdAtUtc: string;
  updatedAtUtc: string;
}

export class BodyTrackingInputError extends Error {
  readonly fields: Readonly<Record<string, string>>;

  constructor(fields: Readonly<Record<string, string>>) {
    super("Die Eingaben sind ungültig.");
    this.name = "BodyTrackingInputError";
    this.fields = fields;
  }
}

export async function readLocalBodyTracking(database: AccountDatabase) {
  const goals = await database.goals.toArray() as LocalResourceRecord<LocalBodyGoal>[];
  const checkIns = await database.checkIns.toArray() as LocalResourceRecord<LocalDailyCheckIn>[];
  const goalValues = goals.map((record) => ({ id: record.id, ...record.envelope.workingCopy }));
  return {
    activeGoal: goalValues.find((goal) => goal.endedAtUtc === null),
    goalHistory: goalValues
      .filter((goal) => goal.endedAtUtc !== null)
      .sort((left, right) => right.startDate.localeCompare(left.startDate)),
    checkIns: checkIns
      .map((record) => ({ id: record.id, ...record.envelope.workingCopy }))
      .sort((left, right) => right.localDate.localeCompare(left.localDate)),
  };
}

export async function activateLocalGoal(
  database: AccountDatabase,
  input: Omit<LocalBodyGoal, "createdAtUtc" | "endedAtUtc">,
): Promise<void> {
  validateGoal(input);
  const goalId = crypto.randomUUID();
  const createdAtUtc = new Date().toISOString();
  await withLocalEditLock(database, () => database.transaction("rw", database.goals, database.outbox, async () => {
    const records = await database.goals.toArray() as LocalResourceRecord<LocalBodyGoal>[];
    const active = records.find((record) => record.envelope.workingCopy.endedAtUtc === null);
    const pendingActive = active
      ? (await database.outbox.where("aggregateKey").equals(`body-goal:${active.id}`).toArray())
        .filter((item) => item.status !== "clean").sort((left, right) => right.sequence - left.sequence)[0]
      : undefined;
    if (active) {
      await database.goals.put({
        ...active,
        envelope: changeWorkingCopy(active.envelope, (draft) => { draft.endedAtUtc = createdAtUtc; }),
      });
    }

    const value: LocalBodyGoal = { ...input, createdAtUtc, endedAtUtc: null };
    const createMutation = prepareLocalMutation({
      aggregateType: "body-goal",
      aggregateId: goalId,
      operation: "create",
      baseVersion: null,
      payload: {
        ...input,
        expectedActiveGoalId: active?.id ?? null,
        expectedActiveGoalVersion: active ? active.envelope.serverVersion ?? 1 : null,
      },
    });
    await database.goals.add({ id: goalId, envelope: createLocalAggregate(goalId, value) });
    const outbox = await outboxRecord(database, createMutation);
    await database.outbox.add({ ...outbox, dependsOnMutationId: pendingActive?.mutationId });
  }));
}

export async function saveLocalCheckIn(
  database: AccountDatabase,
  input: Omit<LocalDailyCheckIn, "createdAtUtc" | "updatedAtUtc">,
): Promise<void> {
  validateCheckIn(input);
  const now = new Date().toISOString();
  await withLocalEditLock(database, () => database.transaction("rw", database.checkIns, database.outbox, async () => {
    const records = await database.checkIns.toArray() as LocalResourceRecord<LocalDailyCheckIn>[];
    const existing = records.find((record) => record.envelope.workingCopy.localDate === input.localDate);
    if (existing) {
      const changed: LocalResourceRecord<LocalDailyCheckIn> = {
        ...existing,
        envelope: changeWorkingCopy(existing.envelope, (draft) => Object.assign(draft, input, { updatedAtUtc: now })),
      };
      const mutation = prepareLocalMutation({
        aggregateType: "daily-check-in",
        aggregateId: existing.id,
        operation: "update",
        baseVersion: existing.envelope.serverVersion,
        payload: changed.envelope.workingCopy,
      });
      await database.checkIns.put(changed);
      await database.outbox.add(await outboxRecord(database, mutation));
      return;
    }

    const id = crypto.randomUUID();
    const value: LocalDailyCheckIn = { ...input, createdAtUtc: now, updatedAtUtc: now };
    const mutation = prepareLocalMutation({
      aggregateType: "daily-check-in",
      aggregateId: id,
      operation: "create",
      baseVersion: null,
      payload: value,
    });
    await database.checkIns.add({ id, envelope: createLocalAggregate(id, value) });
    await database.outbox.add(await outboxRecord(database, mutation));
  }));
}

function validateGoal(input: Omit<LocalBodyGoal, "createdAtUtc" | "endedAtUtc">) {
  const fields: Record<string, string> = {};
  if (!["Bulk", "Maintain", "Cut"].includes(input.kind)) fields.kind = "Ungültige Zielart.";
  if (!positive(input.startWeightKg)) fields.startWeightKg = "Das Startgewicht muss positiv sein.";
  if (!positive(input.targetWeightKg)) fields.targetWeightKg = "Das Zielgewicht muss positiv sein.";
  if (!/^\d{4}-\d{2}-\d{2}$/.test(input.startDate)) fields.startDate = "Ungültiges Startdatum.";
  if (input.targetDate && input.targetDate < input.startDate) fields.targetDate = "Das Zieldatum darf nicht vor dem Startdatum liegen.";
  if (Object.keys(fields).length) throw new BodyTrackingInputError(fields);
}

function validateCheckIn(input: Omit<LocalDailyCheckIn, "createdAtUtc" | "updatedAtUtc">) {
  const fields: Record<string, string> = {};
  if (!/^\d{4}-\d{2}-\d{2}$/.test(input.localDate)) fields.localDate = "Ungültiger Kalendertag.";
  if (!positive(input.weightKg)) fields.weightKg = "Das Gewicht muss positiv sein.";
  for (const field of ["caloriesKcal", "proteinGrams", "carbohydrateGrams", "fatGrams"] as const) {
    const value = input[field];
    if (value !== null && (!Number.isFinite(value) || value < 0)) fields[field] = "Der Wert darf nicht negativ sein.";
  }
  if (input.steps !== null && (!Number.isInteger(input.steps) || input.steps < 0)) fields.steps = "Schritte müssen eine nichtnegative ganze Zahl sein.";
  if (input.sleepMinutes !== null && (!Number.isInteger(input.sleepMinutes) || input.sleepMinutes < 0 || input.sleepMinutes > 1_440)) fields.sleepMinutes = "Schlaf muss zwischen 0 und 1440 Minuten liegen.";
  if (Object.keys(fields).length) throw new BodyTrackingInputError(fields);
}

function positive(value: number) {
  return Number.isFinite(value) && value > 0;
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
