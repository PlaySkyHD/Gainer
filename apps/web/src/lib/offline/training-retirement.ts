import type { AccountDatabase } from "./database.ts";

// Training is no longer written or synchronized by the web app; it lives in the iPhone app.
// Legacy local training aggregates and their outbox entries would otherwise be rejected by the
// server with upgrade_required and block the whole outbox, so they are discarded on start.
const retiredAggregateTypes = ["workout", "workout-template", "workout-rotation", "custom-exercise"] as const;
const retiredResourceTypes = ["Workout", "WorkoutTemplate", "WorkoutRotation", "CustomExercise"] as const;

export function isRetiredTrainingAggregate(aggregateKey: string): boolean {
  return retiredAggregateTypes.some((type) => aggregateKey.startsWith(`${type}:`));
}

/**
 * Removes local training data and its outbox/conflict entries in one transaction.
 * Returns the number of discarded unsent outbox entries so the caller can report the loss.
 * Idempotent: a second run on a clean database discards nothing.
 */
export async function retireLocalTrainingData(database: AccountDatabase): Promise<number> {
  return database.transaction("rw", [
    database.outbox, database.conflicts, database.tombstones, database.syncMeta,
    database.workouts, database.templates, database.rotation, database.customExercises,
  ], async () => {
    const discarded = await database.outbox.filter((item) => isRetiredTrainingAggregate(item.aggregateKey)).toArray();
    await database.outbox.bulkDelete(discarded.map((item) => item.mutationId));
    await database.conflicts.filter((item) => isRetiredTrainingAggregate(item.aggregateKey)).delete();
    await database.tombstones.filter((item) => (retiredResourceTypes as readonly string[]).includes(item.resourceType)).delete();
    await database.syncMeta.filter((item) => item.key.startsWith("last-mutation:") &&
      isRetiredTrainingAggregate(item.key.slice("last-mutation:".length))).delete();
    await database.workouts.clear();
    await database.templates.clear();
    await database.rotation.clear();
    await database.customExercises.clear();
    return discarded.length;
  });
}
