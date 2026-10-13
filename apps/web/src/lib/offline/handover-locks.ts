import type { AccountDatabase } from "./database.ts";

const editLockPrefix = "gainer-account-edit:";
const syncLockPrefix = "gainer-account-sync:";
const localLockTails = new Map<string, Promise<void>>();

export function editLockName(database: AccountDatabase): string {
  return `${editLockPrefix}${database.name}`;
}

export function syncLockName(database: AccountDatabase): string {
  return `${syncLockPrefix}${database.name}`;
}

export function withBrowserLock<T>(name: string, action: () => Promise<T>): Promise<T>;
export function withBrowserLock<T>(
  name: string,
  action: () => Promise<T>,
  options: { ifAvailable: true },
): Promise<T | undefined>;
export async function withBrowserLock<T>(
  name: string,
  action: () => Promise<T>,
  options: { ifAvailable?: boolean } = {},
): Promise<T | undefined> {
  if (typeof navigator !== "undefined" && navigator.locks) {
    return navigator.locks.request(name, { mode: "exclusive", ifAvailable: options.ifAvailable }, (lock) =>
      lock ? action() : undefined);
  }
  if (typeof window !== "undefined") {
    throw new Error("Dieser Browser unterstützt die sichere kontoweite Übergabesperre nicht.");
  }
  if (options.ifAvailable && localLockTails.has(name)) return undefined;
  const prior = localLockTails.get(name) ?? Promise.resolve();
  let release!: () => void;
  const current = new Promise<void>((resolve) => { release = resolve; });
  const tail = prior.then(() => current);
  localLockTails.set(name, tail);
  await prior;
  try {
    return await action();
  } finally {
    release();
    if (localLockTails.get(name) === tail) localLockTails.delete(name);
  }
}

export async function withLocalEditLock<T>(
  database: AccountDatabase,
  action: () => Promise<T>,
  options: { allowFrozen?: boolean } = {},
): Promise<T> {
  return withBrowserLock(editLockName(database), async () => {
    if (!options.allowFrozen && (await database.syncMeta.get("handover-write-freeze"))?.value === true) {
      throw new Error("Lokale Änderungen sind während der Geräteübergabe eingefroren.");
    }
    return action();
  });
}
