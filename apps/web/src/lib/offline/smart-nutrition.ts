import type { AccountDatabase, LocalResourceRecord } from "./database.ts";
import { changeWorkingCopy, createLocalAggregate } from "./aggregate-envelope.ts";
import { commitLocalMutation, prepareLocalMutation } from "./local-mutations.ts";
import {
  createNutritionEntry,
  readLocalNutritionDay,
  saveLocalNutritionDay,
  type LocalNutritionEntry,
  type LocalNutritionSource,
  type LocalNutritionTotals,
  type MealType,
} from "./nutrition-tracking.ts";

export interface LocalReusableMealComponent {
  componentId: string;
  position: number;
  name: string;
  brand: string | null;
  amountGrams: number;
  totals: LocalNutritionTotals;
  per100Grams: LocalNutritionTotals;
  source: LocalNutritionSource | null;
}

export interface LocalReusableMeal {
  name: string;
  description: string | null;
  standardPortion: number;
  status: "Active" | "Archived";
  components: LocalReusableMealComponent[];
  createdAtUtc: string;
  updatedAtUtc: string;
}

export type NutritionGoalCategory = "Custom" | "Cut" | "Maintenance" | "Bulk";
export type NutritionTargetInputMode = "Grams" | "Percent";

export interface LocalNutritionTargetVersion {
  targetVersionId: string;
  name: string;
  category: NutritionGoalCategory;
  effectiveFrom: string;
  effectiveUntil: string | null;
  inputMode: NutritionTargetInputMode;
  kilocalories: number;
  proteinGrams: number;
  carbohydrateGrams: number;
  fatGrams: number;
  proteinPercent: number | null;
  carbohydratePercent: number | null;
  fatPercent: number | null;
  origin: "Manual";
  algorithmVersion: string | null;
  reason: string | null;
}

export interface LocalNutritionTargetSchedule {
  versions: LocalNutritionTargetVersion[];
  createdAtUtc: string;
  updatedAtUtc: string;
}

export async function readReusableMeals(
  database: AccountDatabase,
  includeArchived = false,
): Promise<Array<LocalReusableMeal & { id: string }>> {
  const records = await database.reusableMeals.toArray() as LocalResourceRecord<LocalReusableMeal>[];
  return records
    .filter((record) => includeArchived || record.envelope.workingCopy.status === "Active")
    .map((record) => ({ id: record.id, ...structuredClone(record.envelope.workingCopy) }))
    .sort((left, right) => left.name.localeCompare(right.name));
}

export async function saveReusableMeal(
  database: AccountDatabase,
  input: Omit<LocalReusableMeal, "status" | "createdAtUtc" | "updatedAtUtc"> & { id?: string },
): Promise<string> {
  validateMeal(input);
  const id = input.id ?? crypto.randomUUID();
  const existing = await database.reusableMeals.get(id) as LocalResourceRecord<LocalReusableMeal> | undefined;
  const now = new Date().toISOString();
  const value: LocalReusableMeal = {
    name: input.name.trim(),
    description: input.description?.trim() || null,
    standardPortion: input.standardPortion,
    status: "Active",
    components: [...input.components].sort((a, b) => a.position - b.position).map((item) => structuredClone(item)),
    createdAtUtc: existing?.envelope.workingCopy.createdAtUtc ?? now,
    updatedAtUtc: now,
  };
  const record: LocalResourceRecord<LocalReusableMeal> = existing
    ? { ...existing, envelope: changeWorkingCopy(existing.envelope, (draft) => Object.assign(draft, value)) }
    : { id, envelope: createLocalAggregate(id, value) };
  await commitLocalMutation(database, "reusableMeals", record, prepareLocalMutation({
    aggregateType: "reusable-meal",
    aggregateId: id,
    operation: existing ? "update" : "create",
    baseVersion: existing?.envelope.serverVersion ?? null,
    payload: value,
  }));
  return id;
}

export async function archiveReusableMeal(database: AccountDatabase, id: string): Promise<void> {
  const existing = await database.reusableMeals.get(id) as LocalResourceRecord<LocalReusableMeal> | undefined;
  if (!existing) throw new Error("Das Gericht wurde nicht gefunden.");
  const changed: LocalResourceRecord<LocalReusableMeal> = {
    ...existing,
    envelope: changeWorkingCopy(existing.envelope, (draft) => {
      draft.status = "Archived";
      draft.updatedAtUtc = new Date().toISOString();
    }),
  };
  await commitLocalMutation(database, "reusableMeals", changed, prepareLocalMutation({
    aggregateType: "reusable-meal",
    aggregateId: id,
    operation: "update",
    baseVersion: existing.envelope.serverVersion,
    payload: changed.envelope.workingCopy,
  }));
}

export async function addReusableMealToDay(
  database: AccountDatabase,
  meal: LocalReusableMeal,
  localDate: string,
  targetMeal: MealType,
  portionFactor: number,
): Promise<string> {
  if (!Number.isFinite(portionFactor) || portionFactor < 0.01 || portionFactor > 100)
    throw new Error("Der Portionsfaktor muss zwischen 0,01 und 100 liegen.");
  const existing = await readLocalNutritionDay(database, localDate);
  const offset = existing?.entries.filter((entry) => entry.meal === targetMeal).length ?? 0;
  const additions: LocalNutritionEntry[] = [...meal.components]
    .sort((left, right) => left.position - right.position)
    .map((component, index) => createNutritionEntry({
      entryId: crypto.randomUUID(),
      meal: targetMeal,
      position: offset + index,
      productName: component.name,
      brand: component.brand,
      amountGrams: component.amountGrams * portionFactor,
      per100Grams: structuredClone(component.per100Grams),
      source: component.source ? structuredClone(component.source) : null,
    }));
  return saveLocalNutritionDay(database, localDate, [...(existing?.entries ?? []), ...additions]);
}

export async function readNutritionTargetSchedule(
  database: AccountDatabase,
): Promise<(LocalNutritionTargetSchedule & { id: string }) | null> {
  const record = await database.nutritionTargetSchedules.toCollection().first() as LocalResourceRecord<LocalNutritionTargetSchedule> | undefined;
  return record ? { id: record.id, ...normalizeTargetSchedule(record.envelope.workingCopy) } : null;
}

export async function saveNutritionTargetVersion(
  database: AccountDatabase,
  version: LocalNutritionTargetVersion,
  options: { closeOpenPhase?: boolean } = {},
): Promise<string> {
  validateTarget(version);
  const existing = await database.nutritionTargetSchedules.toCollection().first() as LocalResourceRecord<LocalNutritionTargetSchedule> | undefined;
  const now = new Date().toISOString();
  const id = existing?.id ?? crypto.randomUUID();
  const prior = existing ? normalizeTargetSchedule(existing.envelope.workingCopy).versions : [];
  const current = prior.find((item) => item.targetVersionId === version.targetVersionId);
  const versions = prior
    .filter((item) => item.targetVersionId !== version.targetVersionId)
    .map((item) => structuredClone(item));
  if (current && current.effectiveFrom <= localToday())
    throw new Error("Eine bereits begonnene Zielphase kann nicht bearbeitet werden.");

  const openPredecessor = versions
    .filter((item) => item.effectiveFrom < version.effectiveFrom && item.effectiveUntil === null)
    .sort((left, right) => right.effectiveFrom.localeCompare(left.effectiveFrom))[0];
  if (openPredecessor) {
    if (!options.closeOpenPhase)
      throw new Error(`Die offene Zielphase „${openPredecessor.name}“ muss zuerst beendet werden.`);
    openPredecessor.effectiveUntil = shiftLocalDate(version.effectiveFrom, -1);
  }

  versions.push(structuredClone(version));
  versions.sort((left, right) => left.effectiveFrom.localeCompare(right.effectiveFrom));
  validateNoTargetOverlap(versions);
  const value: LocalNutritionTargetSchedule = {
    versions,
    createdAtUtc: existing?.envelope.workingCopy.createdAtUtc ?? now,
    updatedAtUtc: now,
  };
  const record: LocalResourceRecord<LocalNutritionTargetSchedule> = existing
    ? { ...existing, envelope: changeWorkingCopy(existing.envelope, (draft) => Object.assign(draft, value)) }
    : { id, envelope: createLocalAggregate(id, value) };
  await commitLocalMutation(database, "nutritionTargetSchedules", record, prepareLocalMutation({
    aggregateType: "nutrition-target-schedule",
    aggregateId: id,
    operation: existing ? "update" : "create",
    baseVersion: existing?.envelope.serverVersion ?? null,
    payload: value,
  }));
  return id;
}

export async function removeNutritionTargetVersion(database: AccountDatabase, targetVersionId: string): Promise<void> {
  const existing = await database.nutritionTargetSchedules.toCollection().first() as LocalResourceRecord<LocalNutritionTargetSchedule> | undefined;
  if (!existing) throw new Error("Die Zielphase wurde nicht gefunden.");
  const schedule = normalizeTargetSchedule(existing.envelope.workingCopy);
  const target = schedule.versions.find((item) => item.targetVersionId === targetVersionId);
  if (!target) throw new Error("Die Zielphase wurde nicht gefunden.");
  if (target.effectiveFrom <= localToday()) throw new Error("Eine bereits begonnene Zielphase kann nicht gelöscht werden.");
  const value: LocalNutritionTargetSchedule = {
    ...schedule,
    versions: schedule.versions.filter((item) => item.targetVersionId !== targetVersionId),
    updatedAtUtc: new Date().toISOString(),
  };
  const changed: LocalResourceRecord<LocalNutritionTargetSchedule> = {
    ...existing,
    envelope: changeWorkingCopy(existing.envelope, (draft) => Object.assign(draft, value)),
  };
  await commitLocalMutation(database, "nutritionTargetSchedules", changed, prepareLocalMutation({
    aggregateType: "nutrition-target-schedule",
    aggregateId: existing.id,
    operation: "update",
    baseVersion: existing.envelope.serverVersion,
    payload: value,
  }));
}

export function effectiveTarget(
  schedule: LocalNutritionTargetSchedule | null,
  localDate: string,
): LocalNutritionTargetVersion | null {
  return schedule?.versions
    .filter((item) => item.effectiveFrom <= localDate && (item.effectiveUntil === null || item.effectiveUntil >= localDate))
    .sort((left, right) => right.effectiveFrom.localeCompare(left.effectiveFrom))[0] ?? null;
}

function validateMeal(input: Omit<LocalReusableMeal, "status" | "createdAtUtc" | "updatedAtUtc">) {
  if (!input.name.trim() || input.name.trim().length > 120) throw new Error("Der Gerichtsname ist ungültig.");
  if (!Number.isFinite(input.standardPortion) || input.standardPortion < 0.01 || input.standardPortion > 100)
    throw new Error("Die Standardportion ist ungültig.");
  if (!input.components.length || input.components.length > 50) throw new Error("Ein Gericht benötigt 1 bis 50 Komponenten.");
  if (new Set(input.components.map((item) => item.componentId)).size !== input.components.length ||
      new Set(input.components.map((item) => item.position)).size !== input.components.length)
    throw new Error("Komponenten-IDs und Positionen müssen eindeutig sein.");
}

export function deriveMacroTargets(
  kilocalories: number,
  proteinPercent: number,
  carbohydratePercent: number,
  fatPercent: number,
): Pick<LocalNutritionTargetVersion, "proteinGrams" | "carbohydrateGrams" | "fatGrams"> {
  validatePercentages(proteinPercent, carbohydratePercent, fatPercent);
  if (!Number.isFinite(kilocalories) || kilocalories <= 0 || kilocalories > 20_000)
    throw new Error("Das Kalorienziel ist ungültig.");
  return {
    proteinGrams: round2(kilocalories * proteinPercent / 100 / 4),
    carbohydrateGrams: round2(kilocalories * carbohydratePercent / 100 / 4),
    fatGrams: round2(kilocalories * fatPercent / 100 / 9),
  };
}

function validateTarget(version: LocalNutritionTargetVersion) {
  if (!version.name.trim() || version.name.trim().length > 80) throw new Error("Der Name der Zielphase ist ungültig.");
  if (!["Custom", "Cut", "Maintenance", "Bulk"].includes(version.category)) throw new Error("Die Zielkategorie ist ungültig.");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(version.effectiveFrom)) throw new Error("Der Gültigkeitsbeginn ist ungültig.");
  if (version.effectiveUntil !== null && (!/^\d{4}-\d{2}-\d{2}$/.test(version.effectiveUntil) || version.effectiveUntil < version.effectiveFrom))
    throw new Error("Das Ende der Zielphase ist ungültig.");
  const values = [version.kilocalories, version.proteinGrams, version.carbohydrateGrams, version.fatGrams];
  if (values.some((value) => !Number.isFinite(value) || value <= 0)) throw new Error("Alle Zielwerte müssen positiv sein.");
  if (version.kilocalories > 20_000 || values.slice(1).some((value) => value > 2_000)) throw new Error("Ein Zielwert überschreitet den erlaubten Bereich.");
  if (version.origin !== "Manual" || version.algorithmVersion !== null || version.reason !== null)
    throw new Error("Ernährungsziele können nur manuell erfasst werden.");
  if (version.inputMode === "Percent") {
    validatePercentages(version.proteinPercent, version.carbohydratePercent, version.fatPercent);
    const derived = deriveMacroTargets(version.kilocalories, version.proteinPercent!, version.carbohydratePercent!, version.fatPercent!);
    if (derived.proteinGrams !== version.proteinGrams || derived.carbohydrateGrams !== version.carbohydrateGrams || derived.fatGrams !== version.fatGrams)
      throw new Error("Die Makrogramme passen nicht zur prozentualen Verteilung.");
  } else if (version.inputMode !== "Grams" || version.proteinPercent !== null || version.carbohydratePercent !== null || version.fatPercent !== null) {
    throw new Error("Die Makro-Eingabeart ist ungültig.");
  }
}

function normalizeTargetSchedule(schedule: LocalNutritionTargetSchedule): LocalNutritionTargetSchedule {
  const raw = structuredClone(schedule);
  const versions = raw.versions.map((item) => ({
    ...item,
    name: item.name?.trim() || "Ziel",
    category: item.category ?? "Custom",
    effectiveUntil: item.effectiveUntil ?? null,
    inputMode: item.inputMode ?? "Grams",
    proteinPercent: item.proteinPercent ?? null,
    carbohydratePercent: item.carbohydratePercent ?? null,
    fatPercent: item.fatPercent ?? null,
  })).sort((left, right) => left.effectiveFrom.localeCompare(right.effectiveFrom));
  for (let index = 0; index < versions.length - 1; index++) {
    const current = versions[index]!;
    const next = versions[index + 1]!;
    if (current.effectiveUntil === null) current.effectiveUntil = shiftLocalDate(next.effectiveFrom, -1);
  }
  return { ...raw, versions };
}

function validateNoTargetOverlap(versions: LocalNutritionTargetVersion[]) {
  for (let index = 0; index < versions.length - 1; index++) {
    const current = versions[index]!;
    const next = versions[index + 1]!;
    if (current.effectiveUntil === null || current.effectiveUntil >= next.effectiveFrom)
      throw new Error(`Die Zielphasen „${current.name}“ und „${next.name}“ überschneiden sich.`);
  }
}

function validatePercentages(protein: number | null, carbohydrates: number | null, fat: number | null) {
  const values: Array<number | null> = [protein, carbohydrates, fat];
  if (values.some((value) => value === null || !Number.isFinite(value) || value! <= 0 || value! > 100) ||
      Math.abs((protein ?? 0) + (carbohydrates ?? 0) + (fat ?? 0) - 100) > 1e-9)
    throw new Error("Die Makroverteilung muss aus positiven Werten bestehen und genau 100 % ergeben.");
}

function shiftLocalDate(value: string, days: number): string {
  const date = new Date(`${value}T12:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function localToday(): string {
  const now = new Date();
  const offset = now.getTimezoneOffset() * 60_000;
  return new Date(now.getTime() - offset).toISOString().slice(0, 10);
}

function round2(value: number): number { return Math.round((value + Number.EPSILON) * 100) / 100; }
