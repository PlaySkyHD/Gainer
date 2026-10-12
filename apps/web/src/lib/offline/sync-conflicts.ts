import { restoreServerSnapshot } from "./aggregate-envelope.ts";
import type { AccountDatabase, LocalResourceRecord, OutboxRecord } from "./database.ts";
import { withLocalEditLock } from "./handover-locks.ts";

export async function acceptConflictServerState(
  database: AccountDatabase,
  conflictId: string,
): Promise<void> {
  await withLocalEditLock(database, () => database.transaction(
    "rw",
    [database.conflicts, database.outbox, database.goals, database.checkIns,
      database.customExercises, database.templates, database.rotation, database.workouts,
      database.nutritionDays, database.reusableMeals, database.nutritionTargetSchedules],
    async () => {
      const conflict = await database.conflicts.get(conflictId);
      if (!conflict) throw new Error("Der Konflikt ist nicht mehr vorhanden.");
      const mapping = localMapping(database, conflict.aggregateKey);
      const record = await mapping.table.get(mapping.id) as LocalResourceRecord | undefined;
      if (!record?.envelope.serverSnapshot || record.envelope.serverVersion === null) {
        throw new Error("Für diesen Konflikt ist kein Serverstand verfügbar.");
      }
      await mapping.table.put({ id: mapping.id, envelope: restoreServerSnapshot(record.envelope) });
      await database.outbox.where("aggregateKey").equals(conflict.aggregateKey).delete();
      await database.conflicts.delete(conflictId);
    },
  ));
}

export async function retryConflictOnCurrentServerVersion(
  database: AccountDatabase,
  conflictId: string,
): Promise<string> {
  let replacementId = "";
  await withLocalEditLock(database, () => database.transaction(
    "rw",
    [database.conflicts, database.outbox, database.tombstones, database.goals, database.checkIns,
      database.customExercises, database.templates, database.rotation, database.workouts,
      database.nutritionDays, database.reusableMeals, database.nutritionTargetSchedules],
    async () => {
      const conflict = await database.conflicts.get(conflictId);
      if (!conflict) throw new Error("Der Konflikt ist nicht mehr vorhanden.");
      if (await database.tombstones.get(conflict.aggregateKey)) {
        throw new Error("Eine serverseitig gelöschte Ressource kann nicht still wiederhergestellt werden.");
      }
      const mapping = localMapping(database, conflict.aggregateKey);
      const record = await mapping.table.get(mapping.id) as LocalResourceRecord | undefined;
      if (!record || record.envelope.serverVersion === null) {
        throw new Error("Für diesen Konflikt ist keine aktuelle Basisversion verfügbar.");
      }
      if (mapping.type === "workout" &&
          ["completed", "discarded"].includes(String((record.envelope.workingCopy as { status?: string }).status).toLowerCase())) {
        throw new Error("Abgeschlossene oder verworfene Workouts können nicht erneut angewendet werden.");
      }
      const old = await database.outbox.where("aggregateKey").equals(conflict.aggregateKey).first();
      if (!old) throw new Error("Die lokale Änderung ist nicht mehr vorhanden.");
      replacementId = crypto.randomUUID();
      const payload = structuredClone(old.payload) as { baseVersion?: number; body?: unknown };
      payload.baseVersion = record.envelope.serverVersion;
      const replacement: OutboxRecord = {
        ...old,
        mutationId: replacementId,
        status: "pending",
        createdAtUtc: new Date().toISOString(),
        payload,
        clientSequence: undefined,
        dependsOnMutationId: old.mutationId,
        attemptCount: 0,
        nextAttemptAtUtc: null,
        lastErrorCode: null,
      };
      await database.outbox.where("aggregateKey").equals(conflict.aggregateKey).delete();
      await database.outbox.add(replacement);
      await mapping.table.put({
        ...record,
        envelope: { ...record.envelope, syncState: "pending" },
      });
      await database.conflicts.delete(conflictId);
    },
  ));
  return replacementId;
}

function localMapping(database: AccountDatabase, aggregateKey: string) {
  const separator = aggregateKey.lastIndexOf(":");
  const type = aggregateKey.slice(0, separator);
  const id = aggregateKey.slice(separator + 1);
  const tables = {
    "body-goal": database.goals,
    "daily-check-in": database.checkIns,
    "custom-exercise": database.customExercises,
    "workout-template": database.templates,
    "workout-rotation": database.rotation,
    workout: database.workouts,
    "workout-completion": database.workouts,
    "nutrition-day": database.nutritionDays,
    "reusable-meal": database.reusableMeals,
    "nutrition-target-schedule": database.nutritionTargetSchedules,
  } as const;
  const table = tables[type as keyof typeof tables];
  if (!table || !id) throw new Error("Der Konflikt verweist auf ein unbekanntes Aggregat.");
  return { type, id, table };
}
