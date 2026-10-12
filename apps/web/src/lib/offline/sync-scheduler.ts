import type { AccountDatabase } from "./database.ts";
import { runSync, type SyncRunResult, type SyncTransport } from "./sync-engine.ts";
import { syncLockName, withBrowserLock } from "./handover-locks.ts";

const leaseKey = "sync-lease";

interface LeaseValue {
  ownerId: string;
  expiresAtUtc: string;
}

export async function withSyncLease<T>(
  database: AccountDatabase,
  ownerId: string,
  action: () => Promise<T>,
  now: Date = new Date(),
  durationMs = 30_000,
): Promise<T | undefined> {
  return withBrowserLock(syncLockName(database), async () => {
    const acquired = await acquireDexieLease(database, ownerId, now, durationMs);
    if (!acquired) return undefined;
    try {
      return await action();
    } finally {
      await releaseDexieLease(database, ownerId);
    }
  }, { ifAvailable: true });
}

export async function withSyncLock<T>(database: AccountDatabase, action: () => Promise<T>): Promise<T> {
  return withBrowserLock(syncLockName(database), action);
}

async function acquireDexieLease(
  database: AccountDatabase,
  ownerId: string,
  now: Date,
  durationMs: number,
): Promise<boolean> {
  const acquired = await database.transaction("rw", database.syncMeta, async () => {
    const current = (await database.syncMeta.get(leaseKey))?.value as LeaseValue | undefined;
    if (current && current.ownerId !== ownerId && current.expiresAtUtc > now.toISOString()) return false;
    await database.syncMeta.put({
      key: leaseKey,
      value: { ownerId, expiresAtUtc: new Date(now.getTime() + durationMs).toISOString() } satisfies LeaseValue,
    });
    return true;
  });
  return acquired;
}

async function releaseDexieLease(database: AccountDatabase, ownerId: string): Promise<void> {
  await database.transaction("rw", database.syncMeta, async () => {
    const current = (await database.syncMeta.get(leaseKey))?.value as LeaseValue | undefined;
    if (current?.ownerId === ownerId) await database.syncMeta.delete(leaseKey);
  });
}

export class ForegroundSyncScheduler {
  private readonly ownerId = crypto.randomUUID();
  private timer: ReturnType<typeof setTimeout> | undefined;
  private stopped = true;
  private readonly database: AccountDatabase;
  private readonly transport: SyncTransport;
  private readonly onResult: (result: SyncRunResult | undefined, error?: unknown) => void;

  constructor(
    database: AccountDatabase,
    transport: SyncTransport,
    onResult: (result: SyncRunResult | undefined, error?: unknown) => void,
  ) {
    this.database = database;
    this.transport = transport;
    this.onResult = onResult;
  }

  start(): void {
    if (!this.stopped) return;
    this.stopped = false;
    window.addEventListener("online", this.onForeground);
    document.addEventListener("visibilitychange", this.onVisibility);
    this.schedule(0);
  }

  stop(): void {
    this.stopped = true;
    window.removeEventListener("online", this.onForeground);
    document.removeEventListener("visibilitychange", this.onVisibility);
    if (this.timer) clearTimeout(this.timer);
    this.timer = undefined;
  }

  mutationCommitted(): void {
    this.schedule(750);
  }

  retryNow(takeOverWriting = false): void {
    this.schedule(0, takeOverWriting);
  }

  private readonly onForeground = () => this.schedule(0);
  private readonly onVisibility = () => {
    if (document.visibilityState === "visible") this.schedule(0);
  };

  private schedule(delayMs: number, takeOverWriting = false): void {
    if (this.stopped || !navigator.onLine) return;
    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      this.timer = undefined;
      void withSyncLease(this.database, this.ownerId, () =>
        runSync(this.database, this.transport, { takeOverWriting }))
        .then((result) => this.onResult(result))
        .catch((error) => this.onResult(undefined, error));
    }, delayMs);
  }
}
