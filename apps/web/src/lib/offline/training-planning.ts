import type { AccountDatabase, CatalogRecord, LocalResourceRecord, OutboxRecord } from "./database";
import { changeWorkingCopy, createLocalAggregate } from "./aggregate-envelope.ts";
import { prepareLocalMutation, type MutationOperation, type PreparedLocalMutation } from "./local-mutations.ts";

export interface ExerciseValues {
  name: string;
  description: string | null;
  targetMuscle: string | null;
  muscleGroup: string | null;
  equipment: string | null;
}

export interface LocalCustomExercise extends ExerciseValues {
  isArchived: boolean;
  createdAtUtc: string;
  updatedAtUtc: string;
}

export interface LocalCatalogExercise extends ExerciseValues {
  id: string;
  catalogVersion: number;
}

export interface LocalTemplateItem {
  id: string;
  exerciseId: string;
  plannedSets: number;
  minimumRepetitions: number;
  maximumRepetitions: number;
  targetRir: number | null;
  restSeconds: number | null;
  notes: string | null;
}

export interface LocalWorkoutTemplate {
  name: string;
  items: LocalTemplateItem[];
  isArchived: boolean;
  createdAtUtc: string;
  updatedAtUtc: string;
}

export interface LocalWorkoutRotation {
  entries: { id: string; templateId: string }[];
  lastCompletedTemplateId: string | null;
  updatedAtUtc: string;
}

export class TrainingPlanningInputError extends Error {
  readonly fields: Readonly<Record<string, string>>;

  constructor(fields: Readonly<Record<string, string>>) {
    super("Die Trainingsplanung ist ungültig.");
    this.name = "TrainingPlanningInputError";
    this.fields = fields;
  }
}

const baseCatalog: LocalCatalogExercise[] = [
  catalog("0159d8e1-ec7a-527a-9887-5cb4f70b1c83", "Barbell Bench Press", "Pectoralis major", "Chest", "Barbell"),
  catalog("07859f08-0fa6-5da4-882f-f5db0a7c310d", "Back Squat", "Quadriceps", "Legs", "Barbell"),
  catalog("173d2d47-c8a1-5967-8f5b-88de90a30659", "Romanian Deadlift", "Hamstrings", "Legs", "Barbell"),
  catalog("28d6db67-f2d0-5e15-a63b-759fc96e01cb", "Lat Pulldown", "Latissimus dorsi", "Back", "Cable"),
  catalog("42ce4803-05e3-5f07-92b6-326c9aa95658", "Pull-Up", "Latissimus dorsi", "Back", "Bodyweight"),
  catalog("4ec1e1c8-e2c9-56ac-bec1-4ba0936f6a97", "Seated Cable Row", "Rhomboids", "Back", "Cable"),
  catalog("66f8d486-cedf-54ee-8154-6b295371d2f7", "Dumbbell Lateral Raise", "Lateral deltoid", "Shoulders", "Dumbbell"),
  catalog("71f9157f-2cec-5517-a910-a3a8c6d82f07", "Standing Overhead Press", "Anterior deltoid", "Shoulders", "Barbell"),
  catalog("85c4145d-e045-5153-a18a-1934d16ad4de", "Leg Curl", "Hamstrings", "Legs", "Machine"),
  catalog("9a23aa0d-a43b-5d10-a25e-b22db398578e", "Leg Extension", "Quadriceps", "Legs", "Machine"),
  catalog("b33d40e4-e84e-5317-83e2-9df3ddb6bc4d", "Dumbbell Biceps Curl", "Biceps brachii", "Arms", "Dumbbell"),
  catalog("c6fb4053-2f69-597f-890e-e7bd58444a3e", "Cable Triceps Pushdown", "Triceps brachii", "Arms", "Cable"),
];

export async function initializeExerciseCatalog(database: AccountDatabase): Promise<void> {
  const [total, current] = await Promise.all([
    database.exerciseCatalog.count(),
    database.exerciseCatalog.where("catalogVersion").equals(1).count(),
  ]);
  if (total === baseCatalog.length && current === baseCatalog.length) return;
  await database.transaction("rw", database.exerciseCatalog, async () => {
    await database.exerciseCatalog.clear();
    await database.exerciseCatalog.bulkPut(baseCatalog.map((item): CatalogRecord => ({
      id: item.id,
      catalogVersion: item.catalogVersion,
      value: item,
    })));
  });
}

export async function readTrainingPlanning(database: AccountDatabase) {
  await initializeExerciseCatalog(database);
  const [catalogRecords, customRecords, templateRecords, rotationRecord] = await Promise.all([
    database.exerciseCatalog.toArray(),
    database.customExercises.toArray() as Promise<LocalResourceRecord<LocalCustomExercise>[]>,
    database.templates.toArray() as Promise<LocalResourceRecord<LocalWorkoutTemplate>[]>,
    database.rotation.toCollection().first() as Promise<LocalResourceRecord<LocalWorkoutRotation> | undefined>,
  ]);
  const catalog = catalogRecords.map((record) => record.value as LocalCatalogExercise);
  const customExercises = customRecords.map((record) => ({ id: record.id, ...record.envelope.workingCopy }));
  const templates = templateRecords.map((record) => ({ id: record.id, ...record.envelope.workingCopy }));
  const rotation = rotationRecord ? { id: rotationRecord.id, ...rotationRecord.envelope.workingCopy } : undefined;
  const activeTemplates = templates.filter((item) => !item.isArchived);
  return {
    exercises: [
      ...catalog.map((item) => ({ ...item, isCustom: false as const, isArchived: false })),
      ...customExercises.map((item) => ({ ...item, catalogVersion: null, isCustom: true as const })),
    ],
    templates,
    rotation,
    nextTemplateId: findNextTemplate(rotation, activeTemplates.map((item) => item.id)),
  };
}

export async function createLocalCustomExercise(database: AccountDatabase, values: ExerciseValues): Promise<string> {
  const normalized = validateExercise(values);
  const id = crypto.randomUUID();
  const now = new Date().toISOString();
  const value: LocalCustomExercise = { ...normalized, isArchived: false, createdAtUtc: now, updatedAtUtc: now };
  await writeAggregate(database, database.customExercises, "custom-exercise", id, "create", value);
  return id;
}

export async function updateLocalCustomExercise(
  database: AccountDatabase,
  exerciseId: string,
  values: ExerciseValues,
): Promise<void> {
  const normalized = validateExercise(values);
  await database.transaction("rw", database.customExercises, database.outbox, async () => {
    const record = await database.customExercises.get(exerciseId) as LocalResourceRecord<LocalCustomExercise> | undefined;
    if (!record || record.envelope.workingCopy.isArchived) throw new Error("Die eigene Übung ist nicht verfügbar.");
    const changed = { ...record, envelope: changeWorkingCopy(record.envelope, (draft) => {
      Object.assign(draft, normalized, { updatedAtUtc: new Date().toISOString() });
    }) };
    await database.customExercises.put(changed);
    await database.outbox.add(await outboxRecord(database, mutationFor("custom-exercise", exerciseId, "update", record, changed.envelope.workingCopy)));
  });
}

export async function archiveLocalCustomExercise(database: AccountDatabase, exerciseId: string): Promise<void> {
  await database.transaction("rw", database.customExercises, database.outbox, async () => {
    const record = await database.customExercises.get(exerciseId) as LocalResourceRecord<LocalCustomExercise> | undefined;
    if (!record || record.envelope.workingCopy.isArchived) throw new Error("Die eigene Übung ist nicht verfügbar.");
    const changed = { ...record, envelope: changeWorkingCopy(record.envelope, (draft) => {
      draft.isArchived = true;
      draft.updatedAtUtc = new Date().toISOString();
    }) };
    await database.customExercises.put(changed);
    await database.outbox.add(await outboxRecord(database, mutationFor("custom-exercise", exerciseId, "update", record, changed.envelope.workingCopy)));
  });
}

export async function saveLocalTemplate(
  database: AccountDatabase,
  input: { id?: string; name: string; items: LocalTemplateItem[] },
): Promise<string> {
  const normalized = await validateTemplate(database, input);
  const id = input.id ?? crypto.randomUUID();
  const now = new Date().toISOString();
  await database.transaction("rw", database.templates, database.outbox, async () => {
    const existing = await database.templates.get(id) as LocalResourceRecord<LocalWorkoutTemplate> | undefined;
    if (existing?.envelope.workingCopy.isArchived) throw new Error("Das archivierte Template kann nicht geändert werden.");
    const value: LocalWorkoutTemplate = {
      name: normalized.name,
      items: normalized.items,
      isArchived: false,
      createdAtUtc: existing?.envelope.workingCopy.createdAtUtc ?? now,
      updatedAtUtc: now,
    };
    const record = existing
      ? { ...existing, envelope: changeWorkingCopy(existing.envelope, (draft) => Object.assign(draft, value)) }
      : { id, envelope: createLocalAggregate(id, value) };
    await database.templates.put(record);
    const mutation = prepareLocalMutation({
      aggregateType: "workout-template", aggregateId: id,
      operation: existing ? "update" : "create",
      baseVersion: existing?.envelope.serverVersion ?? null,
      payload: value,
    });
    await database.outbox.add(await outboxRecord(database, mutation));
  });
  return id;
}

export async function archiveLocalTemplate(database: AccountDatabase, templateId: string): Promise<void> {
  await database.transaction("rw", database.templates, database.outbox, async () => {
    const record = await database.templates.get(templateId) as LocalResourceRecord<LocalWorkoutTemplate> | undefined;
    if (!record || record.envelope.workingCopy.isArchived) throw new Error("Das Template ist nicht verfügbar.");
    const changed = { ...record, envelope: changeWorkingCopy(record.envelope, (draft) => {
      draft.isArchived = true;
      draft.updatedAtUtc = new Date().toISOString();
    }) };
    await database.templates.put(changed);
    await database.outbox.add(await outboxRecord(database, mutationFor("workout-template", templateId, "update", record, changed.envelope.workingCopy)));
  });
}

export async function saveLocalRotation(
  database: AccountDatabase,
  templateIds: string[],
): Promise<string> {
  if (new Set(templateIds).size !== templateIds.length) {
    throw new TrainingPlanningInputError({ rotation: "Jedes Template darf nur einmal in der Rotation stehen." });
  }
  const templates = await database.templates.bulkGet(templateIds) as (LocalResourceRecord<LocalWorkoutTemplate> | undefined)[];
  if (templates.some((record) => !record || record.envelope.workingCopy.isArchived)) {
    throw new TrainingPlanningInputError({ rotation: "Die Rotation enthält ein nicht verfügbares Template." });
  }
  const existing = await database.rotation.toCollection().first() as LocalResourceRecord<LocalWorkoutRotation> | undefined;
  const id = existing?.id ?? crypto.randomUUID();
  const value: LocalWorkoutRotation = {
    entries: templateIds.map((templateId) => ({ id: crypto.randomUUID(), templateId })),
    lastCompletedTemplateId: existing?.envelope.workingCopy.lastCompletedTemplateId && templateIds.includes(existing.envelope.workingCopy.lastCompletedTemplateId)
      ? existing.envelope.workingCopy.lastCompletedTemplateId : null,
    updatedAtUtc: new Date().toISOString(),
  };
  await database.transaction("rw", database.rotation, database.outbox, async () => {
    const record = existing
      ? { ...existing, envelope: changeWorkingCopy(existing.envelope, (draft) => Object.assign(draft, value)) }
      : { id, envelope: createLocalAggregate(id, value) };
    await database.rotation.put(record);
    const mutation = prepareLocalMutation({
      aggregateType: "workout-rotation", aggregateId: id,
      operation: existing ? "update" : "create",
      baseVersion: existing?.envelope.serverVersion ?? null,
      payload: value,
    });
    await database.outbox.add(await outboxRecord(database, mutation));
  });
  return id;
}

function validateExercise(values: ExerciseValues): ExerciseValues {
  const normalized = { ...values, name: values.name.trim(), description: clean(values.description), targetMuscle: clean(values.targetMuscle), muscleGroup: clean(values.muscleGroup), equipment: clean(values.equipment) };
  const fields: Record<string, string> = {};
  if (normalized.name.length < 1 || normalized.name.length > 160) fields.name = "Der Name muss 1 bis 160 Zeichen lang sein.";
  if ((normalized.description?.length ?? 0) > 2_000) fields.description = "Die Beschreibung ist zu lang.";
  for (const field of ["targetMuscle", "muscleGroup", "equipment"] as const) {
    if ((normalized[field]?.length ?? 0) > 100) fields[field] = "Der Wert ist zu lang.";
  }
  if (Object.keys(fields).length) throw new TrainingPlanningInputError(fields);
  return normalized;
}

async function validateTemplate(
  database: AccountDatabase,
  input: { id?: string; name: string; items: LocalTemplateItem[] },
) {
  const fields: Record<string, string> = {};
  const name = input.name.trim();
  if (name.length < 1 || name.length > 160) fields.name = "Der Name muss 1 bis 160 Zeichen lang sein.";
  if (input.items.length < 1 || input.items.length > 100) fields.items = "Mindestens eine Übung ist erforderlich.";
  if (new Set(input.items.map((item) => item.id)).size !== input.items.length || input.items.some((item) => !item.id)) fields.itemIds = "Eintrags-IDs müssen eindeutig sein.";
  input.items.forEach((item, index) => {
    if (!Number.isInteger(item.plannedSets) || item.plannedSets < 1 || item.plannedSets > 100) fields[`items.${index}.sets`] = "Sätze müssen zwischen 1 und 100 liegen.";
    if (!Number.isInteger(item.minimumRepetitions) || item.minimumRepetitions < 1 || !Number.isInteger(item.maximumRepetitions) || item.maximumRepetitions < item.minimumRepetitions) fields[`items.${index}.repetitions`] = "Der Wiederholungsbereich ist ungültig.";
    if (item.targetRir !== null && (!Number.isFinite(item.targetRir) || item.targetRir < 0 || item.targetRir > 10)) fields[`items.${index}.rir`] = "RIR muss zwischen 0 und 10 liegen.";
    if (item.restSeconds !== null && (!Number.isInteger(item.restSeconds) || item.restSeconds < 0 || item.restSeconds > 86_400)) fields[`items.${index}.rest`] = "Die Pause ist ungültig.";
    if ((item.notes?.trim().length ?? 0) > 2_000) fields[`items.${index}.notes`] = "Die Notiz ist zu lang.";
  });
  const [catalog, custom, existing] = await Promise.all([
    database.exerciseCatalog.bulkGet(input.items.map((item) => item.exerciseId)),
    database.customExercises.bulkGet(input.items.map((item) => item.exerciseId)) as Promise<(LocalResourceRecord<LocalCustomExercise> | undefined)[]>,
    input.id ? database.templates.get(input.id) as Promise<LocalResourceRecord<LocalWorkoutTemplate> | undefined> : undefined,
  ]);
  const existingIds = new Set(existing?.envelope.workingCopy.items.map((item) => item.exerciseId));
  input.items.forEach((item, index) => {
    const base = catalog[index];
    const own = custom[index];
    if (!base && (!own || (own.envelope.workingCopy.isArchived && !existingIds.has(item.exerciseId)))) {
      fields[`items.${index}.exerciseId`] = "Die Übung ist nicht verfügbar.";
    }
  });
  if (Object.keys(fields).length) throw new TrainingPlanningInputError(fields);
  return { name, items: input.items.map((item) => ({ ...item, notes: clean(item.notes) })) };
}

function findNextTemplate(
  rotation: ({ entries: { templateId: string }[]; lastCompletedTemplateId: string | null } | undefined),
  activeTemplateIds: string[],
): string | null {
  if (!rotation || activeTemplateIds.length === 0) return null;
  const active = new Set(activeTemplateIds);
  const lastIndex = rotation.lastCompletedTemplateId
    ? rotation.entries.findIndex((entry) => entry.templateId === rotation.lastCompletedTemplateId) : -1;
  for (let offset = 1; offset <= rotation.entries.length; offset++) {
    const entry = rotation.entries[(lastIndex + offset + rotation.entries.length) % rotation.entries.length];
    if (entry && active.has(entry.templateId)) return entry.templateId;
  }
  return null;
}

async function writeAggregate<T>(
  database: AccountDatabase,
  table: AccountDatabase["customExercises"],
  aggregateType: string,
  id: string,
  operation: "create",
  value: T,
) {
  const mutation = prepareLocalMutation({ aggregateType, aggregateId: id, operation, baseVersion: null, payload: value });
  await database.transaction("rw", table, database.outbox, async () => {
    await table.add({ id, envelope: createLocalAggregate(id, value) });
    await database.outbox.add(await outboxRecord(database, mutation));
  });
}

function mutationFor<T>(
  type: string,
  id: string,
  operation: MutationOperation,
  original: LocalResourceRecord<T>,
  payload: T,
) {
  return prepareLocalMutation({ aggregateType: type, aggregateId: id, operation, baseVersion: original.envelope.serverVersion, payload });
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

function catalog(id: string, name: string, targetMuscle: string, muscleGroup: string, equipment: string): LocalCatalogExercise {
  return { id, name, targetMuscle, muscleGroup, equipment, description: null, catalogVersion: 1 };
}

function clean(value: string | null): string | null {
  return value?.trim() ? value.trim() : null;
}
