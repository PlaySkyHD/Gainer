import Dexie, { type EntityTable } from "dexie";
import type { LocalAggregateEnvelope, SyncState } from "./aggregate-envelope";

const profileDatabaseName = "gainer-local-profiles";
const installationIdKey = "installation-id";
const activeAccountIdKey = "active-account-id";
const accountIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export const accountStoresV1 = {
  syncMeta: "&key",
  outbox: "&mutationId, aggregateKey, [aggregateKey+sequence], status, createdAtUtc",
  conflicts: "&conflictId, aggregateKey, createdAtUtc",
  tombstones: "&resourceKey, [resourceType+resourceId], revision",
  goals: "&id",
  checkIns: "&id",
  customExercises: "&id",
  templates: "&id",
  rotation: "&id",
  workouts: "&id",
  exerciseCatalog: "&id, catalogVersion",
  analyticsCache: "&key, asOfRevision",
} as const;

export const accountStoresV2 = {
  ...accountStoresV1,
  outbox: "&mutationId, aggregateKey, [aggregateKey+sequence], status, createdAtUtc, [status+createdAtUtc]",
} as const;

export const accountStoresV3 = {
  ...accountStoresV2,
  outbox: "&mutationId, aggregateKey, [aggregateKey+sequence], status, createdAtUtc, [status+createdAtUtc], &clientSequence, [status+nextAttemptAtUtc]",
} as const;

export const accountStoresV4 = {
  ...accountStoresV3,
  nutritionDays: "&id",
} as const;

export const accountStoresV5 = {
  ...accountStoresV4,
  reusableMeals: "&id",
  nutritionTargetSchedules: "&id",
} as const;

export interface LocalMetadata {
  key: string;
  value: string;
}

export interface LocalProfile {
  accountId: string;
  databaseName: string;
  email?: string;
  lastOpenedAtUtc: string;
}

export interface SyncMetadata {
  key: string;
  value: unknown;
}

export interface OutboxRecord {
  mutationId: string;
  aggregateKey: string;
  sequence: number;
  status: OutboxStatus;
  createdAtUtc: string;
  payload: unknown;
  clientSequence?: number;
  dependsOnMutationId?: string | null;
  attemptCount?: number;
  nextAttemptAtUtc?: string | null;
  lastErrorCode?: string | null;
}

export type OutboxStatus = SyncState | "syncing" | "inactive-client" | "upgrade-required";

export interface ConflictRecord {
  conflictId: string;
  aggregateKey: string;
  createdAtUtc: string;
  detail: unknown;
}

export interface TombstoneRecord {
  resourceKey: string;
  resourceType: string;
  resourceId: string;
  revision: number;
}

export interface LocalResourceRecord<T = unknown> {
  id: string;
  envelope: LocalAggregateEnvelope<T>;
}

export interface CatalogRecord {
  id: string;
  catalogVersion: number;
  value: unknown;
}

export interface AnalyticsCacheRecord {
  key: string;
  asOfRevision: number;
  value: unknown;
}

class LocalProfileDatabase extends Dexie {
  metadata!: EntityTable<LocalMetadata, "key">;
  profiles!: EntityTable<LocalProfile, "accountId">;

  constructor() {
    super(profileDatabaseName);
    this.version(1).stores({
      metadata: "&key",
      profiles: "&accountId, databaseName, lastOpenedAtUtc",
    });
  }
}

export class AccountDatabase extends Dexie {
  syncMeta!: EntityTable<SyncMetadata, "key">;
  outbox!: EntityTable<OutboxRecord, "mutationId">;
  conflicts!: EntityTable<ConflictRecord, "conflictId">;
  tombstones!: EntityTable<TombstoneRecord, "resourceKey">;
  goals!: EntityTable<LocalResourceRecord, "id">;
  checkIns!: EntityTable<LocalResourceRecord, "id">;
  customExercises!: EntityTable<LocalResourceRecord, "id">;
  templates!: EntityTable<LocalResourceRecord, "id">;
  rotation!: EntityTable<LocalResourceRecord, "id">;
  workouts!: EntityTable<LocalResourceRecord, "id">;
  nutritionDays!: EntityTable<LocalResourceRecord, "id">;
  reusableMeals!: EntityTable<LocalResourceRecord, "id">;
  nutritionTargetSchedules!: EntityTable<LocalResourceRecord, "id">;
  exerciseCatalog!: EntityTable<CatalogRecord, "id">;
  analyticsCache!: EntityTable<AnalyticsCacheRecord, "key">;

  readonly accountId: string;

  constructor(accountId: string) {
    const normalizedAccountId = normalizeAccountId(accountId);
    super(accountDatabaseName(normalizedAccountId));
    this.accountId = normalizedAccountId;
    this.version(1).stores(accountStoresV1);
    this.version(2).stores(accountStoresV2);
    this.version(3).stores(accountStoresV3);
    this.version(4).stores(accountStoresV4);
    this.version(5).stores(accountStoresV5);
  }
}

export class PendingLocalMutationsError extends Error {
  readonly pendingCount: number;

  constructor(pendingCount: number) {
    super(`${pendingCount} lokale Änderung(en) wurden noch nicht synchronisiert.`);
    this.name = "PendingLocalMutationsError";
    this.pendingCount = pendingCount;
  }
}

let profileDatabase: LocalProfileDatabase | undefined;

function profiles(): LocalProfileDatabase {
  profileDatabase ??= new LocalProfileDatabase();
  return profileDatabase;
}

export async function getOrCreateInstallationId(): Promise<string> {
  const database = profiles();
  return database.transaction("rw", database.metadata, async () => {
    const existing = await database.metadata.get(installationIdKey);
    if (existing) return existing.value;

    const value = crypto.randomUUID();
    await database.metadata.add({ key: installationIdKey, value });
    return value;
  });
}

export async function openAccountDatabase(accountId: string, email?: string): Promise<AccountDatabase> {
  const normalizedAccountId = normalizeAccountId(accountId);
  await getOrCreateInstallationId();
  const database = new AccountDatabase(normalizedAccountId);
  await database.open();
  const existingProfile = await profiles().profiles.get(normalizedAccountId);
  await profiles().profiles.put({
    accountId: normalizedAccountId,
    databaseName: database.name,
    email: email ?? existingProfile?.email,
    lastOpenedAtUtc: new Date().toISOString(),
  });
  return database;
}

export async function listLocalProfiles(): Promise<LocalProfile[]> {
  return profiles().profiles.orderBy("lastOpenedAtUtc").reverse().toArray();
}

export async function rememberActiveLocalProfile(accountId: string, email: string): Promise<void> {
  const normalizedAccountId = normalizeAccountId(accountId);
  const database = await openAccountDatabase(normalizedAccountId, email);
  database.close();
  await profiles().metadata.put({ key: activeAccountIdKey, value: normalizedAccountId });
}

export async function getActiveLocalProfile(): Promise<LocalProfile | undefined> {
  const active = await profiles().metadata.get(activeAccountIdKey);
  return active ? profiles().profiles.get(active.value) : undefined;
}

export async function clearActiveLocalProfile(): Promise<void> {
  await profiles().metadata.delete(activeAccountIdKey);
}

export async function deleteLocalAccountData(accountId: string, allowPendingMutations = false): Promise<void> {
  const normalizedAccountId = normalizeAccountId(accountId);
  const database = new AccountDatabase(normalizedAccountId);
  await database.open();
  const pendingCount = await database.outbox.count();
  database.close();
  if (pendingCount > 0 && !allowPendingMutations) {
    throw new PendingLocalMutationsError(pendingCount);
  }

  await Dexie.delete(database.name);
  await profiles().profiles.delete(normalizedAccountId);
}

export function accountDatabaseName(accountId: string): string {
  return `gainer-account-${normalizeAccountId(accountId)}`;
}

function normalizeAccountId(accountId: string): string {
  if (!accountIdPattern.test(accountId)) throw new Error("Die Konto-ID ist ungültig.");
  return accountId.toLowerCase();
}
