export type SyncState = "clean" | "pending" | "conflict" | "auth-blocked" | "failed";

export interface LocalAggregateEnvelope<T> {
  aggregateId: string;
  serverSnapshot: T | null;
  workingCopy: T;
  serverVersion: number | null;
  optimisticVersion: number;
  syncState: SyncState;
}

export function createServerAggregate<T>(
  aggregateId: string,
  serverSnapshot: T,
  serverVersion: number,
): LocalAggregateEnvelope<T> {
  assertVersion(serverVersion);
  return {
    aggregateId,
    serverSnapshot: clone(serverSnapshot),
    workingCopy: clone(serverSnapshot),
    serverVersion,
    optimisticVersion: serverVersion,
    syncState: "clean",
  };
}

export function createLocalAggregate<T>(aggregateId: string, workingCopy: T): LocalAggregateEnvelope<T> {
  return {
    aggregateId,
    serverSnapshot: null,
    workingCopy: clone(workingCopy),
    serverVersion: null,
    optimisticVersion: 1,
    syncState: "pending",
  };
}

export function changeWorkingCopy<T>(
  envelope: LocalAggregateEnvelope<T>,
  change: (draft: T) => void,
): LocalAggregateEnvelope<T> {
  const workingCopy = clone(envelope.workingCopy);
  change(workingCopy);
  return {
    ...envelope,
    serverSnapshot: envelope.serverSnapshot === null ? null : clone(envelope.serverSnapshot),
    workingCopy,
    optimisticVersion: envelope.optimisticVersion + 1,
    syncState: "pending",
  };
}

export function restoreServerSnapshot<T>(envelope: LocalAggregateEnvelope<T>): LocalAggregateEnvelope<T> {
  if (envelope.serverSnapshot === null || envelope.serverVersion === null) {
    throw new Error("Ein noch nicht synchronisiertes Aggregat besitzt keinen Serverstand.");
  }

  return createServerAggregate(envelope.aggregateId, envelope.serverSnapshot, envelope.serverVersion);
}

function assertVersion(version: number): void {
  if (!Number.isSafeInteger(version) || version < 0) {
    throw new Error("Die Serverversion muss eine nichtnegative ganze Zahl sein.");
  }
}

function clone<T>(value: T): T {
  return structuredClone(value);
}
