import type { AccountDatabase, LocalResourceRecord, OutboxRecord } from "./database.ts";
import { changeWorkingCopy, createLocalAggregate } from "./aggregate-envelope.ts";
import type { SyncState } from "./aggregate-envelope.ts";
import { commitLocalMutation, prepareLocalMutation } from "./local-mutations.ts";

export type MealType = "Breakfast" | "Lunch" | "Dinner" | "Snacks";

export interface LocalNutritionTotals {
  kilocalories: number;
  proteinGrams: number | null;
  carbohydrateGrams: number | null;
  fatGrams: number | null;
}

export interface LocalNutritionSource {
  provider: string | null;
  barcode: string | null;
  retrievedAtUtc: string | null;
  basisGrams: number;
}

export interface LocalNutritionEntry {
  entryId: string;
  meal: MealType;
  position: number;
  productName: string;
  brand: string | null;
  amountGrams: number;
  totals: LocalNutritionTotals;
  per100Grams: LocalNutritionTotals;
  source: LocalNutritionSource | null;
}

export interface LocalNutritionDay {
  localDate: string;
  entries: LocalNutritionEntry[];
  totals: LocalNutritionTotals;
  createdAtUtc: string;
  updatedAtUtc: string;
}

export interface NutritionEntryInput {
  entryId?: string;
  meal: MealType;
  position: number;
  productName: string;
  brand?: string | null;
  amountGrams: number;
  per100Grams: LocalNutritionTotals;
  source?: LocalNutritionSource | null;
}

export class NutritionInputError extends Error {
  readonly fields: Readonly<Record<string, string>>;

  constructor(fields: Readonly<Record<string, string>>) {
    super("Die Nährwertangaben sind ungültig.");
    this.name = "NutritionInputError";
    this.fields = fields;
  }
}

export function createNutritionEntry(input: NutritionEntryInput): LocalNutritionEntry {
  validateEntry(input);
  return {
    entryId: input.entryId ?? crypto.randomUUID(),
    meal: input.meal,
    position: input.position,
    productName: input.productName.trim(),
    brand: input.brand?.trim() || null,
    amountGrams: round(input.amountGrams),
    totals: calculateNutrition(input.amountGrams, input.per100Grams),
    per100Grams: structuredClone(input.per100Grams),
    source: input.source ? structuredClone(input.source) : null,
  };
}

export function calculateNutrition(amountGrams: number, per100Grams: LocalNutritionTotals): LocalNutritionTotals {
  const fields: Record<string, string> = {};
  if (!positive(amountGrams)) fields.amountGrams = "Die Menge muss positiv sein.";
  if (!positive(per100Grams.kilocalories)) fields.kilocalories = "Kilokalorien müssen positiv sein.";
  for (const field of ["proteinGrams", "carbohydrateGrams", "fatGrams"] as const) {
    const value = per100Grams[field];
    if (value !== null && (!Number.isFinite(value) || value < 0)) fields[field] = "Der Wert darf nicht negativ sein.";
  }
  if (Object.keys(fields).length) throw new NutritionInputError(fields);
  const factor = amountGrams / 100;
  return {
    kilocalories: round(per100Grams.kilocalories * factor),
    proteinGrams: scale(per100Grams.proteinGrams, factor),
    carbohydrateGrams: scale(per100Grams.carbohydrateGrams, factor),
    fatGrams: scale(per100Grams.fatGrams, factor),
  };
}

export function sumNutrition(entries: readonly LocalNutritionEntry[]): LocalNutritionTotals {
  return {
    kilocalories: round(entries.reduce((sum, entry) => sum + entry.totals.kilocalories, 0)),
    proteinGrams: sumOptional(entries.map((entry) => entry.totals.proteinGrams)),
    carbohydrateGrams: sumOptional(entries.map((entry) => entry.totals.carbohydrateGrams)),
    fatGrams: sumOptional(entries.map((entry) => entry.totals.fatGrams)),
  };
}

export async function readLocalNutritionDay(
  database: AccountDatabase,
  localDate: string,
): Promise<(LocalNutritionDay & { id: string; syncState: SyncState }) | null> {
  const records = await database.nutritionDays.toArray() as LocalResourceRecord<LocalNutritionDay>[];
  const found = records.find((record) => record.envelope.workingCopy.localDate === localDate);
  return found ? {
    id: found.id,
    syncState: found.envelope.syncState,
    ...structuredClone(found.envelope.workingCopy),
  } : null;
}

export async function saveLocalNutritionDay(
  database: AccountDatabase,
  localDate: string,
  entries: readonly LocalNutritionEntry[],
): Promise<string> {
  validateDay(localDate, entries);
  const normalized = entries
    .map((entry) => createNutritionEntry({ ...entry, entryId: entry.entryId }))
    .sort(compareEntries);
  const records = await database.nutritionDays.toArray() as LocalResourceRecord<LocalNutritionDay>[];
  const existing = records.find((record) => record.envelope.workingCopy.localDate === localDate);
  const now = new Date().toISOString();
  if (existing) {
    const changed: LocalResourceRecord<LocalNutritionDay> = {
      ...existing,
      envelope: changeWorkingCopy(existing.envelope, (draft) => {
        draft.entries = normalized;
        draft.totals = sumNutrition(normalized);
        draft.updatedAtUtc = now;
      }),
    };
    await commitLocalMutation(database, "nutritionDays", changed, prepareLocalMutation({
      aggregateType: "nutrition-day",
      aggregateId: existing.id,
      operation: "update",
      baseVersion: existing.envelope.serverVersion,
      payload: changed.envelope.workingCopy,
    }));
    return existing.id;
  }

  const id = crypto.randomUUID();
  const value: LocalNutritionDay = {
    localDate,
    entries: normalized,
    totals: sumNutrition(normalized),
    createdAtUtc: now,
    updatedAtUtc: now,
  };
  await commitLocalMutation(database, "nutritionDays", {
    id,
    envelope: createLocalAggregate(id, value),
  }, prepareLocalMutation({
    aggregateType: "nutrition-day",
    aggregateId: id,
    operation: "create",
    baseVersion: null,
    payload: value,
  }));
  return id;
}

export async function deleteLocalNutritionDay(database: AccountDatabase, localDate: string): Promise<void> {
  const records = await database.nutritionDays.toArray() as LocalResourceRecord<LocalNutritionDay>[];
  const existing = records.find((record) => record.envelope.workingCopy.localDate === localDate);
  if (!existing) return;
  const aggregateKey = `nutrition-day:${existing.id}`;
  await database.transaction("rw", database.nutritionDays, database.outbox, async () => {
    await database.nutritionDays.delete(existing.id);
    if (existing.envelope.serverVersion === null) {
      await database.outbox.where("aggregateKey").equals(aggregateKey).delete();
      return;
    }
    const mutation = prepareLocalMutation({
      aggregateType: "nutrition-day",
      aggregateId: existing.id,
      operation: "delete",
      baseVersion: existing.envelope.serverVersion,
      payload: { localDate },
    });
    const prior = await database.outbox.where("aggregateKey").equals(aggregateKey).toArray();
    const outbox: OutboxRecord = {
      mutationId: mutation.mutationId,
      aggregateKey,
      sequence: prior.reduce((highest, item) => Math.max(highest, item.sequence), 0) + 1,
      status: "pending",
      createdAtUtc: mutation.createdAtUtc,
      payload: { operation: mutation.operation, baseVersion: mutation.baseVersion, body: mutation.payload },
    };
    await database.outbox.add(outbox);
  });
}

export async function recentLocalNutritionEntries(
  database: AccountDatabase,
  limit = 20,
): Promise<LocalNutritionEntry[]> {
  if (!Number.isInteger(limit) || limit < 1 || limit > 50) throw new RangeError("Limit must be between 1 and 50.");
  const records = await database.nutritionDays.toArray() as LocalResourceRecord<LocalNutritionDay>[];
  const seen = new Set<string>();
  const result: LocalNutritionEntry[] = [];
  for (const record of records.sort((left, right) =>
    right.envelope.workingCopy.updatedAtUtc.localeCompare(left.envelope.workingCopy.updatedAtUtc))) {
    for (const entry of [...record.envelope.workingCopy.entries].sort((left, right) => right.position - left.position)) {
      const key = `${entry.productName.toLocaleLowerCase()}|${entry.brand?.toLocaleLowerCase() ?? ""}|${entry.source?.barcode ?? ""}`;
      if (seen.has(key)) continue;
      seen.add(key);
      result.push(structuredClone(entry));
      if (result.length === limit) return result;
    }
  }
  return result;
}

export const meals: readonly MealType[] = ["Breakfast", "Lunch", "Dinner", "Snacks"];

function validateDay(localDate: string, entries: readonly LocalNutritionEntry[]) {
  const fields: Record<string, string> = {};
  if (!/^\d{4}-\d{2}-\d{2}$/.test(localDate)) fields.localDate = "Ungültiger Kalendertag.";
  if (entries.length > 200) fields.entries = "Pro Tag sind höchstens 200 Einträge möglich.";
  if (new Set(entries.map((entry) => entry.entryId)).size !== entries.length) fields.entries = "Eintrags-IDs müssen eindeutig sein.";
  for (const meal of meals) {
    const positions = entries.filter((entry) => entry.meal === meal).map((entry) => entry.position);
    if (new Set(positions).size !== positions.length) fields.entries = "Positionen müssen innerhalb einer Mahlzeit eindeutig sein.";
  }
  if (Object.keys(fields).length) throw new NutritionInputError(fields);
}

function validateEntry(input: NutritionEntryInput) {
  const fields: Record<string, string> = {};
  if (input.entryId !== undefined && !/^[0-9a-f-]{36}$/i.test(input.entryId)) fields.entryId = "Ungültige Eintrags-ID.";
  if (!meals.includes(input.meal)) fields.meal = "Ungültige Mahlzeit.";
  if (!Number.isInteger(input.position) || input.position < 0) fields.position = "Die Position muss eine nichtnegative ganze Zahl sein.";
  const name = input.productName.trim();
  if (!name || name.length > 200) fields.productName = "Der Name muss 1 bis 200 Zeichen enthalten.";
  if ((input.brand?.length ?? 0) > 160) fields.brand = "Die Marke ist zu lang.";
  if (input.source && (!positive(input.source.basisGrams) || (input.source.barcode?.length ?? 0) > 64)) fields.source = "Die Quellenangaben sind ungültig.";
  try { calculateNutrition(input.amountGrams, input.per100Grams); }
  catch (error) {
    if (error instanceof NutritionInputError) Object.assign(fields, error.fields);
    else throw error;
  }
  if (Object.keys(fields).length) throw new NutritionInputError(fields);
}

function compareEntries(left: LocalNutritionEntry, right: LocalNutritionEntry) {
  return meals.indexOf(left.meal) - meals.indexOf(right.meal) || left.position - right.position || left.entryId.localeCompare(right.entryId);
}

function sumOptional(values: readonly (number | null)[]): number | null {
  const present = values.filter((value): value is number => value !== null);
  return present.length ? round(present.reduce((sum, value) => sum + value, 0)) : null;
}

function scale(value: number | null, factor: number) {
  return value === null ? null : round(value * factor);
}

function round(value: number) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function positive(value: number) {
  return Number.isFinite(value) && value > 0;
}
