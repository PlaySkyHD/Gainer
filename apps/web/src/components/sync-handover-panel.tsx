"use client";

import { useCallback, useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import type { AccountDatabase } from "@/lib/offline/database";
import { canonicalizeApiOrigin, createHandoverTransferBundle, parseHandoverTransferBundle, type HandoverTransferBundle } from "@/lib/offline/handover-transfer-bundle";
import {
  beginPwaHandover,
  cancelPwaHandover,
  finishPwaHandoverTarget,
  readHandoverLocalStatus,
  readHandoverRecovery,
  startPwaAsHandoverTarget,
  type HandoverLocalStatus,
  type HandoverRecovery,
} from "@/lib/offline/sync-handover";

export function SyncHandoverPanel({ database, online }: { database: AccountDatabase; online: boolean }) {
  const [recovery, setRecovery] = useState<HandoverRecovery>();
  const [status, setStatus] = useState<HandoverLocalStatus>({ unresolvedCount: 0, blockedCount: 0, conflictCount: 0 });
  const [handoverId, setHandoverId] = useState("");
  const [oneTimeCode, setOneTimeCode] = useState("");
  const [frozenRevision, setFrozenRevision] = useState("");
  const [transferText, setTransferText] = useState("");
  const [parsedBundle, setParsedBundle] = useState<HandoverTransferBundle>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();

  const refresh = useCallback(async () => {
    const [current, counts] = await Promise.all([readHandoverRecovery(database), readHandoverLocalStatus(database)]);
    setRecovery(current);
    setStatus(counts);
  }, [database]);

  useEffect(() => {
    const refreshTimer = window.setTimeout(() => { void refresh(); }, 0);
    return () => window.clearTimeout(refreshTimer);
  }, [refresh]);

  async function run(action: () => Promise<void>) {
    setBusy(true);
    setError(undefined);
    setNotice(undefined);
    try {
      await action();
      await refresh();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Geräteübergabe fehlgeschlagen.");
      await refresh();
    } finally {
      setBusy(false);
    }
  }

  async function begin() {
    if (!online) throw new Error("Zum Starten der Übergabe brauchst du eine aktive Verbindung.");
    const response = await beginPwaHandover(database);
    const sourceRecovery = await readHandoverRecovery(database);
    setNotice("Übergabe vorbereitet. Der Einmalcode ist nur für das authentifizierte Zielgerät bestimmt.");
    setRecovery({
      kind: "source",
      phase: "pending",
      handoverId: response.handoverId,
      oneTimeCode: response.oneTimeCode,
      frozenRevision: response.frozenRevision,
      expiresAtUtc: response.expiresAtUtc,
      sourceClientId: sourceRecovery?.sourceClientId ?? sourceRecovery?.targetClientId ?? "",
      requestId: sourceRecovery?.requestId,
      targetClientId: sourceRecovery?.targetClientId ?? "",
    });
  }

  async function cancel() {
    if (!window.confirm("Übergabe abbrechen? Die lokale Outbox bleibt erhalten.")) return;
    await cancelPwaHandover(database);
    setNotice("Übergabe abgebrochen. Dieses Gerät bleibt Schreibgerät.");
  }

  async function startTarget() {
    if (!online) throw new Error("Zum Wiederherstellen brauchst du eine aktive Verbindung.");
    const revision = parsedBundle?.frozenRevision ?? Number(frozenRevision);
    const selectedHandoverId = parsedBundle?.handoverId ?? handoverId.trim();
    const selectedOneTimeCode = parsedBundle?.oneTimeCode ?? oneTimeCode.trim();
    if (!selectedHandoverId || !selectedOneTimeCode || !Number.isSafeInteger(revision) || revision < 0) {
      throw new Error("Übergabe-ID, Einmalcode und eingefrorene Revision sind erforderlich.");
    }
    await startPwaAsHandoverTarget(database, {
      handoverId: selectedHandoverId,
      oneTimeCode: selectedOneTimeCode,
      frozenRevision: revision,
    });
    setNotice("Rückübergabe abgeschlossen. Die PWA öffnet jetzt die frisch synchronisierte Datenbank.");
    window.setTimeout(() => window.location.reload(), 500);
  }

  async function copyTransferBundle() {
    if (!source?.handoverId || !source.oneTimeCode || !source.expiresAtUtc) throw new Error("Übergabepaket ist auf diesem Gerät nicht vollständig verfügbar.");
    const bundle = createHandoverTransferBundle({
      accountId: database.accountId,
      apiOrigin: canonicalizeApiOrigin(window.location.origin),
      sourceClientId: source.sourceClientId ?? source.targetClientId,
      handoverId: source.handoverId,
      oneTimeCode: source.oneTimeCode,
      frozenRevision: source.frozenRevision,
      expiresAtUtc: source.expiresAtUtc,
    });
    await navigator.clipboard.writeText(bundle);
    setNotice("Übergabepaket in die Zwischenablage kopiert. Teile es nur mit dem authentifizierten Zielgerät.");
  }

  function validateTransferBundle() {
    const bundle = parseHandoverTransferBundle(transferText, database.accountId, canonicalizeApiOrigin(window.location.origin));
    setParsedBundle(bundle);
    setHandoverId(bundle.handoverId);
    setOneTimeCode(bundle.oneTimeCode);
    setFrozenRevision(String(bundle.frozenRevision));
  }

  async function resumeTarget() {
    await finishPwaHandoverTarget(database);
    setNotice("Rückübergabe wiederhergestellt. Die PWA öffnet jetzt die frisch synchronisierte Datenbank.");
    window.setTimeout(() => window.location.reload(), 500);
  }

  const source = recovery?.kind === "source" ? recovery : undefined;
  const target = recovery?.kind === "target" ? recovery : undefined;
  const sourceFrozen = source !== undefined;

  return (
    <section aria-label="Geräteübergabe" className="space-y-4 rounded-2xl border bg-card p-5">
      <div>
        <h2 className="font-semibold">Gerätewechsel</h2>
        <p className="mt-1 text-sm leading-6 text-muted-foreground">
          Änderungen werden zuerst synchronisiert. Die lokale Datenbank bleibt während der Übergabe erhalten.
        </p>
      </div>
      <div className="grid gap-3 rounded-xl bg-muted/40 p-3 text-sm sm:grid-cols-3">
        <p>Offene Änderungen: <strong>{status.unresolvedCount}</strong></p>
        <p>Blockierte Änderungen: <strong>{status.blockedCount}</strong></p>
        <p>Konflikte: <strong>{status.conflictCount}</strong></p>
      </div>
      {source && <div className="space-y-3 rounded-xl border border-primary/30 p-4">
        <p className="font-medium">{source.phase === "pending" ? "Übergabe wartet auf das Zielgerät" : "Übergabe kann sicher fortgesetzt werden"}</p>
        {source.handoverId && <dl className="grid gap-2 text-sm sm:grid-cols-[9rem_minmax(0,1fr)]">
          <dt className="text-muted-foreground">Übergabe-ID</dt><dd className="break-all font-mono">{source.handoverId}</dd>
          <dt className="text-muted-foreground">Quellgerät-ID</dt><dd className="break-all font-mono">{source.sourceClientId ?? source.targetClientId}</dd>
          <dt className="text-muted-foreground">Einmalcode</dt><dd><output className="break-all font-mono">{source.oneTimeCode}</output></dd>
          <dt className="text-muted-foreground">Serverrevision</dt><dd>{source.frozenRevision}</dd>
          {source.expiresAtUtc && <><dt className="text-muted-foreground">Gültig bis (UTC)</dt><dd><time dateTime={source.expiresAtUtc} className="break-all font-mono">{source.expiresAtUtc}</time></dd></>}
        </dl>}
        <p className="text-sm text-muted-foreground">Das Zielgerät muss mit demselben Konto angemeldet sein und vor dem Abschluss alle Änderungen bis zu dieser Revision laden.</p>
        <div className="flex flex-wrap gap-2">
          {source.phase === "pending" && <Button type="button" variant="outline" disabled={busy} onClick={() => void run(copyTransferBundle)}>Übergabepaket kopieren</Button>}
          {source.phase !== "pending" && <Button type="button" disabled={busy || !online} onClick={() => void run(begin)}>{busy ? "Wird vorbereitet …" : "Übergabe fortsetzen"}</Button>}
          <Button type="button" variant="outline" disabled={busy || !online} onClick={() => void run(cancel)}>Übergabe abbrechen</Button>
        </div>
      </div>}
      {target && <div className="space-y-3 rounded-xl border border-primary/30 p-4">
        <p className="font-medium">Rückübergabe wird auf diesem PWA-Gerät vorbereitet</p>
        <p className="text-sm text-muted-foreground">Die native Quelle bleibt gesperrt, bis die PWA den vollständigen Serverstand geladen und den Wechsel bestätigt hat.</p>
        <Button type="button" disabled={busy || !online} onClick={() => void run(resumeTarget)}>{busy ? "Daten werden geprüft …" : "Rückübergabe wiederherstellen"}</Button>
      </div>}
      {!recovery && <>
        <div className="flex flex-wrap gap-2">
          <Button type="button" disabled={busy || !online || status.blockedCount > 0 || status.conflictCount > 0} onClick={() => void run(begin)}>
            {busy ? "Outbox wird synchronisiert …" : "Dieses PWA-Gerät sicher übergeben"}
          </Button>
        </div>
        {(status.blockedCount > 0 || status.conflictCount > 0) && <p className="text-sm text-amber-700 dark:text-amber-300">Löse blockierte Änderungen und Konflikte zuerst im Sync-Bereich.</p>}
        <form onSubmit={(event) => { event.preventDefault(); void run(startTarget); }} className="space-y-3 border-t pt-4">
          <h3 className="font-medium">PWA als Zielgerät wiederherstellen</h3>
          <p className="text-sm text-muted-foreground">Füge das Übergabepaket vom Quellgerät ein. Konto und App-Origin werden geprüft; vor dem Schreiben werden die Daten bis zur eingefrorenen Revision geladen. Die bisherige PWA-Datenbank bleibt als Recovery erhalten.</p>
          <label className="block space-y-1 text-sm"><span>Übergabepaket (JSON)</span><textarea className="min-h-28 w-full rounded-lg border bg-background p-3 font-mono text-xs" value={transferText} onChange={(event) => { setTransferText(event.target.value); setParsedBundle(undefined); }} maxLength={16384} autoComplete="off" /></label>
          <Button type="button" variant="outline" disabled={busy || !transferText.trim()} onClick={() => void run(async () => { validateTransferBundle(); })}>Paket prüfen</Button>
          {parsedBundle && <p role="status" className="break-all text-sm text-muted-foreground">Quelle {parsedBundle.sourceClientId} · Revision {parsedBundle.frozenRevision} · Ablauf {parsedBundle.expiresAtUtc}. Bestätige die Übernahme unten.</p>}
          <details>
            <summary className="cursor-pointer text-sm text-muted-foreground">Erweiterte manuelle Eingabe</summary>
          <label className="block space-y-1 text-sm"><span>Übergabe-ID</span><input className="h-11 w-full rounded-lg border bg-background px-3 font-mono text-sm" value={handoverId} onChange={(event) => { setHandoverId(event.target.value); setParsedBundle(undefined); }} autoComplete="off" /></label>
          <label className="block space-y-1 text-sm"><span>Einmalcode</span><input className="h-11 w-full rounded-lg border bg-background px-3 font-mono text-sm" value={oneTimeCode} onChange={(event) => { setOneTimeCode(event.target.value); setParsedBundle(undefined); }} autoComplete="off" /></label>
          <label className="block space-y-1 text-sm"><span>Eingefrorene Serverrevision</span><input className="h-11 w-full rounded-lg border bg-background px-3 text-sm" inputMode="numeric" type="number" min="0" step="1" value={frozenRevision} onChange={(event) => { setFrozenRevision(event.target.value); setParsedBundle(undefined); }} /></label>
          </details>
          <Button type="submit" disabled={busy || !online}>{busy ? "Serverstand wird geladen …" : "PWA als Schreibgerät übernehmen"}</Button>
        </form>
      </>}
      {sourceFrozen && <p role="status" className="text-sm text-muted-foreground">Lokale Schreibaktionen sind pausiert. Synchronisiere und löse alle Konflikte, bevor du die Übergabe fortsetzt.</p>}
      {error && <p role="alert" className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
      {notice && <p role="status" className="rounded-lg bg-primary/10 p-3 text-sm">{notice}</p>}
    </section>
  );
}
