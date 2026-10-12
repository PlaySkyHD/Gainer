import { BrowserSyncHandoverTransport, type BeginHandoverResponse, type SyncHandoverTransport } from "../api/sync-handover-transport.ts";
import { BrowserSyncTransport } from "../api/sync-transport.ts";
import { AccountDatabase, activateStagedAccountDatabase, getOrCreateInstallationId, type OutboxRecord } from "./database.ts";
import { syncLockName, withBrowserLock, withLocalEditLock } from "./handover-locks.ts";
import { preparePendingMutations, pullReadOnlyToRevision, runSync, type SyncTransport } from "./sync-engine.ts";

const recoveryKey = "handover-recovery";
const freezeKey = "handover-write-freeze";
const blockedStatuses = ["failed", "conflict", "auth-blocked", "inactive-client", "upgrade-required"] as const;

export interface HandoverRecovery {
  kind: "source" | "target";
  phase: "preparing" | "pending" | "staging" | "ready" | "completing" | "completed";
  handoverId?: string;
  oneTimeCode: string;
  frozenRevision: number;
  expiresAtUtc?: string;
  requestId?: string;
  /** Canonical source identifier for cross-client handover instructions. */
  sourceClientId?: string;
  targetClientId: string;
  stageDatabaseName?: string;
}

export interface HandoverLocalStatus {
  unresolvedCount: number;
  blockedCount: number;
  conflictCount: number;
}

export interface HandoverRecoveryTransports {
  sync: SyncTransport;
  handover: SyncHandoverTransport;
}

export async function readHandoverRecovery(database: AccountDatabase): Promise<HandoverRecovery | undefined> {
  return (await database.syncMeta.get(recoveryKey))?.value as HandoverRecovery | undefined;
}

export async function readHandoverLocalStatus(database: AccountDatabase): Promise<HandoverLocalStatus> {
  const records = await database.outbox.toArray();
  const conflicts = await database.conflicts.count();
  return {
    unresolvedCount: records.filter((item) => item.status !== "clean").length,
    blockedCount: records.filter((item) => blockedStatuses.includes(item.status as typeof blockedStatuses[number])).length,
    conflictCount: conflicts,
  };
}

export async function beginPwaHandover(database: AccountDatabase): Promise<BeginHandoverResponse> {
  const clientId = await getOrCreateInstallationId();
  return withLocalEditLock(database, async () => {
    let recovery = await readHandoverRecovery(database);
    if (recovery && recovery.kind !== "source") throw new Error("Auf diesem PWA-Gerät läuft bereits eine Zielübergabe.");
    if (!recovery) {
      const status = await readHandoverLocalStatus(database);
      if (status.conflictCount > 0 || status.blockedCount > 0) {
        throw new Error("Löse zuerst alle Synchronisationskonflikte und blockierten Änderungen.");
      }
      recovery = {
        kind: "source",
        phase: "preparing",
        requestId: crypto.randomUUID(),
        oneTimeCode: "",
        frozenRevision: Number((await database.syncMeta.get("pull-cursor"))?.value ?? 0),
        sourceClientId: clientId,
        targetClientId: clientId,
      };
      await database.syncMeta.put({ key: freezeKey, value: true });
      await database.syncMeta.put({ key: recoveryKey, value: recovery });
    }
    return withBrowserLock(syncLockName(database), async () => {
      await recoverOrphanedPushes(database);
      await drainOutbox(database);
      const status = await readHandoverLocalStatus(database);
      if (status.unresolvedCount > 0 || status.conflictCount > 0) {
        throw new Error("Die Übergabe bleibt gesperrt, bis alle Änderungen synchronisiert und Konflikte gelöst sind.");
      }
      const revision = Number((await database.syncMeta.get("pull-cursor"))?.value ?? 0);
      recovery = { ...recovery!, frozenRevision: revision };
      await database.syncMeta.put({ key: recoveryKey, value: recovery });
      const result = await new BrowserSyncHandoverTransport(database.accountId).begin({
        requestId: recovery.requestId!,
        sourceClientId: clientId,
        expectedRevision: revision,
      });
      recovery = {
        ...recovery,
        phase: "pending",
        handoverId: result.handoverId,
        oneTimeCode: result.oneTimeCode,
        frozenRevision: result.frozenRevision,
        expiresAtUtc: result.expiresAtUtc,
      };
      await database.syncMeta.put({ key: recoveryKey, value: recovery });
      return result;
    });
  }, { allowFrozen: true });
}

export async function cancelPwaHandover(
  database: AccountDatabase,
  transports: HandoverRecoveryTransports = {
    sync: new BrowserSyncTransport(database.accountId),
    handover: new BrowserSyncHandoverTransport(database.accountId),
  },
): Promise<void> {
  await withLocalEditLock(database, async () => {
    const recovery = await readHandoverRecovery(database);
    if (!recovery || recovery.kind !== "source") return;
    if (recovery.requestId && !recovery.handoverId) {
      try {
        const recovered = await transports.handover.begin({
          requestId: recovery.requestId,
          sourceClientId: recovery.targetClientId,
          expectedRevision: recovery.frozenRevision,
        });
        recovery.handoverId = recovered.handoverId;
      } catch (error) {
        if (!isDefinitiveBeginMiss(error)) throw error;
        await releaseSourceFreezeIfActive(database, recovery.targetClientId, transports.sync);
        return;
      }
    }
    if (recovery.handoverId) {
      try {
        await transports.handover.cancel(recovery.handoverId, recovery.targetClientId);
      } catch (error) {
        if (!(error instanceof Error && "code" in error && error.code === "handover_not_pending")) throw error;
        await releaseSourceFreezeIfActive(database, recovery.targetClientId, transports.sync);
        return;
      }
    }
    await clearSourceFreeze(database);
  }, { allowFrozen: true });
}

export async function startPwaAsHandoverTarget(
  database: AccountDatabase,
  input: { handoverId: string; oneTimeCode: string; frozenRevision: number },
): Promise<void> {
  const targetClientId = await getOrCreateInstallationId();
  const stageDatabaseName = stagingDatabaseName(database.accountId, input.handoverId, targetClientId);
  await withLocalEditLock(database, async () => {
    const status = await readHandoverLocalStatus(database);
    if (status.unresolvedCount > 0 || status.conflictCount > 0) {
      throw new Error("Auf dieser PWA liegen noch lokale Änderungen. Bewahre sie auf und löse sie vor der Rückübernahme.");
    }
    const existing = await readHandoverRecovery(database);
    if (existing && (existing.kind !== "target" || existing.handoverId !== input.handoverId)) {
      throw new Error("Eine andere Geräteübergabe benötigt zuerst eine Wiederherstellung oder einen Abbruch.");
    }
    if (existing?.kind === "target" &&
        (existing.oneTimeCode !== input.oneTimeCode || existing.frozenRevision !== input.frozenRevision)) {
      throw new Error("Die gespeicherte Zielübergabe hat andere Übergabedaten. Verwende denselben Einmalcode und dieselbe Revision.");
    }
    const recovery: HandoverRecovery = {
      kind: "target",
      phase: existing?.phase === "completed" ? "completed" : "staging",
      handoverId: input.handoverId,
      oneTimeCode: input.oneTimeCode,
      frozenRevision: input.frozenRevision,
      targetClientId,
      stageDatabaseName,
    };
    await database.syncMeta.put({ key: freezeKey, value: true });
    await database.syncMeta.put({ key: recoveryKey, value: recovery });
  }, { allowFrozen: true });

  await finishPwaHandoverTarget(database);
}

export async function finishPwaHandoverTarget(
  database: AccountDatabase,
  transports: HandoverRecoveryTransports = {
    sync: new BrowserSyncTransport(database.accountId),
    handover: new BrowserSyncHandoverTransport(database.accountId),
  },
): Promise<void> {
  let recovery = await readHandoverRecovery(database);
  if (!recovery || recovery.kind !== "target" || !recovery.handoverId || !recovery.stageDatabaseName) {
    throw new Error("Für diese PWA wurde keine fortsetzbare Zielübergabe gefunden.");
  }
  const handoverId = recovery.handoverId;
  const stage = new AccountDatabase(database.accountId, recovery.stageDatabaseName);
  await stage.open();
  try {
    const syncTransport = transports.sync;
    if (recovery.phase !== "completed") {
      await syncTransport.register(recovery.targetClientId, false);
      await pullReadOnlyToRevision(stage, syncTransport, recovery.frozenRevision);
      const status = await readHandoverLocalStatus(database);
      if (status.unresolvedCount > 0 || status.conflictCount > 0) {
        throw new Error("Lokale PWA-Änderungen sind hinzugekommen. Die Rückübernahme bleibt bis zur Recovery gesperrt.");
      }
      await validateImmutableLocalHistory(database, stage);
      recovery = { ...recovery, phase: "ready" };
      await database.syncMeta.put({ key: recoveryKey, value: recovery });
      recovery = { ...recovery, phase: "completing" };
      await database.syncMeta.put({ key: recoveryKey, value: recovery });
      const completion = await transports.handover.complete(handoverId, {
        oneTimeCode: recovery.oneTimeCode,
        targetClientId: recovery.targetClientId,
        caughtUpRevision: Number((await stage.syncMeta.get("pull-cursor"))?.value ?? 0),
      });
      if (!completion.isActiveWriter) {
        throw new Error("Der Server hat die Übergabe bestätigt, aber dieses Zielgerät ist inzwischen kein aktiver Writer mehr. Das Staging bleibt als Recoveryprofil erhalten.");
      }
      recovery = { ...recovery, phase: "completed" };
      await database.syncMeta.put({ key: recoveryKey, value: recovery });
    }
    const status = await readHandoverLocalStatus(database);
    if (status.unresolvedCount > 0 || status.conflictCount > 0) {
      throw new Error("Die lokale PWA-Outbox änderte sich; der Staging-Stand bleibt erhalten und muss geprüft werden.");
    }
    await database.syncMeta.put({
      key: recoveryKey,
      value: { ...recovery, phase: "completed", oneTimeCode: "" } satisfies HandoverRecovery,
    });
    await activateStagedAccountDatabase(database.accountId, undefined, stage.name);
  } finally {
    stage.close();
  }
}

async function releaseSourceFreezeIfActive(
  database: AccountDatabase,
  sourceClientId: string,
  syncTransport: SyncTransport,
): Promise<void> {
  const current = await syncTransport.register(sourceClientId, false);
  if (!current.isActiveWriter) {
    throw new Error("Der Übergabestatus ist unklar und dieses Gerät ist kein aktiver Writer. Lokale Schreibvorgänge bleiben zum Schutz eingefroren.");
  }
  await clearSourceFreeze(database);
}

async function clearSourceFreeze(database: AccountDatabase): Promise<void> {
  await database.syncMeta.delete(recoveryKey);
  await database.syncMeta.delete(freezeKey);
}

function isDefinitiveBeginMiss(error: unknown): boolean {
  return error instanceof Error && "code" in error &&
    (error.code === "stale_revision" || error.code === "handover_not_pending");
}

async function drainOutbox(database: AccountDatabase): Promise<void> {
  const transport = new BrowserSyncTransport(database.accountId);
  await preparePendingMutations(database);
  for (let attempt = 0; attempt < 100; attempt++) {
    const before = await database.outbox.filter((item) => item.status !== "clean").count();
    if (before === 0) return;
    const status = await readHandoverLocalStatus(database);
    if (status.blockedCount > 0 || status.conflictCount > 0) {
      throw new Error("Mindestens eine lokale Änderung ist blockiert oder konfliktbehaftet.");
    }
    await runSync(database, transport);
    const after = await database.outbox.filter((item) => item.status !== "clean").count();
    if (after === 0) return;
    const records = await database.outbox.filter((item) => item.status !== "clean").toArray();
    if (records.some((item) => item.status !== "pending")) {
      throw new Error("Der Outbox-Drain ist blockiert. Die lokalen Änderungen bleiben erhalten und können später erneut synchronisieren.");
    }
    if (after >= before && records.some((item) => item.nextAttemptAtUtc && item.nextAttemptAtUtc > new Date().toISOString())) {
      throw new Error("Ein Push wurde für einen späteren Retry vorgemerkt. Übergabe nach dem Retry erneut starten.");
    }
  }
  throw new Error("Die Outbox konnte nicht vollständig geleert werden. Wiederhole die Übergabe später.");
}

async function recoverOrphanedPushes(database: AccountDatabase): Promise<void> {
  const syncing = await database.outbox.where("status").equals("syncing").toArray();
  if (syncing.length === 0) return;
  await database.outbox.bulkPut(syncing.map((item: OutboxRecord) => ({
    ...item,
    status: "pending",
    nextAttemptAtUtc: null,
    lastErrorCode: "handover_recovered_push",
  })));
}

async function validateImmutableLocalHistory(database: AccountDatabase, stage: AccountDatabase): Promise<void> {
  const local = await database.workouts.toArray() as { id: string; envelope: { workingCopy: { status?: string } } }[];
  for (const item of local) {
    if (item.envelope.workingCopy.status?.toLowerCase() !== "completed") continue;
    const staged = await stage.workouts.get(item.id) as { envelope?: { workingCopy?: unknown } } | undefined;
    if (staged && JSON.stringify(item.envelope.workingCopy) !== JSON.stringify(staged.envelope?.workingCopy)) {
      throw new Error("Ein lokaler abgeschlossener Workout-Snapshot weicht vom Server ab. Er bleibt erhalten; die Übergabe wird nicht abgeschlossen.");
    }
  }
}

function stagingDatabaseName(accountId: string, handoverId: string, targetClientId: string): string {
  return `gainer-handover-stage-${accountId}-${handoverId}-${targetClientId}`.toLowerCase();
}
