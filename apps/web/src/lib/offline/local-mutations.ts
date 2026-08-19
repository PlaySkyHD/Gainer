import Dexie, { type EntityTable } from "dexie";
import type { AccountDatabase, LocalResourceRecord, OutboxRecord } from "./database";

export type MutableAggregateTable =
  | "goals"
  | "checkIns"
  | "customExercises"
  | "templates"
  | "rotation"
  | "workouts";

export type MutationOperation = "create" | "update" | "delete" | "complete" | "discard";

export interface PreparedLocalMutation {
  readonly mutationId: string;
  readonly aggregateKey: string;
  readonly operation: MutationOperation;
  readonly baseVersion: number | null;
  readonly createdAtUtc: string;
  readonly payload: unknown;
}

export interface PrepareMutationInput {
  aggregateType: string;
  aggregateId: string;
  operation: MutationOperation;
  baseVersion: number | null;
  payload: unknown;
}

export function prepareLocalMutation(input: PrepareMutationInput): PreparedLocalMutation {
  if (!input.aggregateType.trim() || !input.aggregateId.trim()) {
    throw new Error("Aggregattyp und Aggregat-ID müssen gesetzt sein.");
  }
  if (input.baseVersion !== null && (!Number.isSafeInteger(input.baseVersion) || input.baseVersion < 0)) {
    throw new Error("Die Basisversion muss null oder eine nichtnegative ganze Zahl sein.");
  }

  return Object.freeze({
    mutationId: crypto.randomUUID(),
    aggregateKey: `${input.aggregateType}:${input.aggregateId}`,
    operation: input.operation,
    baseVersion: input.baseVersion,
    createdAtUtc: new Date().toISOString(),
    payload: structuredClone(input.payload),
  });
}

export async function commitLocalMutation<T>(
  database: AccountDatabase,
  tableName: MutableAggregateTable,
  resource: LocalResourceRecord<T>,
  mutation: PreparedLocalMutation,
): Promise<OutboxRecord> {
  if (resource.envelope.syncState !== "pending") {
    throw new Error("Eine lokale Mutation muss einen ausstehenden Working Copy speichern.");
  }

  const table = database.table<LocalResourceRecord<T>, string>(tableName) as EntityTable<
    LocalResourceRecord<T>,
    "id"
  >;

  return database.transaction("rw", table, database.outbox, async () => {
    const prior = await database.outbox.where("aggregateKey").equals(mutation.aggregateKey).toArray();
    const sequence = prior.reduce((highest, item) => Math.max(highest, item.sequence), 0) + 1;
    const outboxRecord: OutboxRecord = {
      mutationId: mutation.mutationId,
      aggregateKey: mutation.aggregateKey,
      sequence,
      status: "pending",
      createdAtUtc: mutation.createdAtUtc,
      payload: {
        operation: mutation.operation,
        baseVersion: mutation.baseVersion,
        body: structuredClone(mutation.payload),
      },
    };

    await table.put(structuredClone(resource));
    await database.outbox.add(outboxRecord);
    return structuredClone(outboxRecord);
  });
}

export async function pendingMutationsForAggregate(
  database: AccountDatabase,
  aggregateKey: string,
): Promise<OutboxRecord[]> {
  return database.outbox
    .where("[aggregateKey+sequence]")
    .between([aggregateKey, Dexie.minKey], [aggregateKey, Dexie.maxKey])
    .sortBy("sequence");
}
