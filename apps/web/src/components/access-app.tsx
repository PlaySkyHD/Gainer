"use client";

import { type FormEvent, useCallback, useEffect, useRef, useState } from "react";
import { Dumbbell, HeartPulse, Home, LogOut, Monitor, Moon, Sparkles, Sun, Utensils } from "lucide-react";
import { Button } from "@/components/ui/button";
import { BodyTrackingPanel } from "@/components/body-tracking-panel";
import { InsightsDashboard } from "@/components/insights-dashboard";
import { CoachPanel } from "@/components/coach-panel";
import { NutritionPanel } from "@/components/nutrition-panel";
import { SyncHandoverPanel } from "@/components/sync-handover-panel";
import {
  createInvitation, getSession, listAccounts, login, logout, setAccountStatus,
  type AccountSummary, type Session,
} from "@/lib/api/client";
import {
  type AccountDatabase,
  clearActiveLocalProfile,
  deleteLocalAccountData,
  getActiveLocalProfile,
  getOrCreateInstallationId,
  openAccountDatabase,
  PendingLocalMutationsError,
  rememberActiveLocalProfile,
} from "@/lib/offline/database";
import type { ConflictRecord } from "@/lib/offline/database";
import { BrowserSyncTransport } from "@/lib/api/sync-transport";
import { resumeAfterAuthentication, SyncHttpError, type SyncRunResult } from "@/lib/offline/sync-engine";
import { ForegroundSyncScheduler } from "@/lib/offline/sync-scheduler";
import { acceptConflictServerState, retryConflictOnCurrentServerVersion } from "@/lib/offline/sync-conflicts";
import { retireLocalTrainingData } from "@/lib/offline/training-retirement";

const inputClass = "h-11 w-full rounded-lg border bg-background px-3 text-sm shadow-xs outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/30";
const message = (error: unknown) => error instanceof Error ? error.message : "Die Anfrage ist fehlgeschlagen.";

export function AccessApp() {
  const [session, setSession] = useState<AppSession | null>();
  useEffect(() => {
    void (async () => {
      await getOrCreateInstallationId();
      try {
        const current = await getSession();
        if (current) {
          await rememberActiveLocalProfile(current.userId, current.email);
          setSession(current);
        } else {
          await clearActiveLocalProfile();
          setSession(null);
        }
      } catch {
        const local = await getActiveLocalProfile();
        setSession(local?.email ? {
          userId: local.accountId,
          email: local.email,
          isAccountOperator: false,
          isOffline: true,
        } : null);
      }
    })();
  }, []);

  if (session === undefined) return <main className="grid min-h-dvh place-items-center p-6">Sitzung wird geprüft …</main>;
  return session ? <AuthenticatedArea session={session} onLogout={() => {
    setSession(null);
    void clearActiveLocalProfile();
  }} /> : <LoginForm onLogin={async (current) => {
    await rememberActiveLocalProfile(current.userId, current.email);
    setSession(current);
  }} />;
}

type AppSession = Session & { isOffline?: boolean };

function LoginForm({ onLogin }: { onLogin: (session: Session) => Promise<void> }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    setBusy(true); setError(undefined);
    try { await onLogin(await login(String(form.get("email")), String(form.get("password")))); }
    catch (caught) { setError(message(caught)); }
    finally { setBusy(false); }
  }

  return (
    <main className="app-shell grid min-h-dvh place-items-center p-5 sm:p-8">
      <ThemeToggle className="fixed right-5 top-5 sm:right-8 sm:top-8" />
      <form onSubmit={submit} className="login-card app-glass w-full max-w-sm space-y-6 rounded-[2rem] border p-7 sm:p-8">
        <div className="flex size-14 items-center justify-center rounded-2xl bg-primary text-primary-foreground shadow-lg shadow-primary/20"><Dumbbell className="size-7" aria-hidden="true" /></div>
        <div><p className="text-sm font-semibold text-primary">Willkommen zurück</p><h1 className="mt-2 text-3xl font-bold">Anmelden</h1><p className="mt-2 text-sm leading-6 text-muted-foreground">Training, Körperdaten und Fortschritt an einem privaten Ort.</p></div>
        <label className="block space-y-2 text-sm font-medium"><span>E-Mail-Adresse</span><input className={inputClass} name="email" type="email" autoComplete="email" required /></label>
        <label className="block space-y-2 text-sm font-medium"><span>Passwort</span><input className={inputClass} name="password" type="password" autoComplete="current-password" required /></label>
        {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
        <Button className="w-full" size="lg" type="submit" disabled={busy}>{busy ? "Anmeldung läuft …" : "Anmelden"}</Button>
      </form>
    </main>
  );
}

function AuthenticatedArea({ session, onLogout }: { session: AppSession; onLogout: () => void }) {
  const [activeTab, setActiveTab] = useState<TabId>("home");
  const [storageError, setStorageError] = useState<string>();
  const [storageMessage, setStorageMessage] = useState<string>();
  const [online, setOnline] = useState(() => navigator.onLine && !session.isOffline);
  const [pendingCount, setPendingCount] = useState(0);
  const [blockedCount, setBlockedCount] = useState(0);
  const [syncState, setSyncState] = useState<SyncRunResult["state"] | "offline">(online ? "idle" : "offline");
  const [lastSyncAt, setLastSyncAt] = useState<string>();
  const [syncError, setSyncError] = useState<string>();
  const [conflicts, setConflicts] = useState<ConflictRecord[]>([]);
  const [updateWorker, setUpdateWorker] = useState<ServiceWorker>();
  const [database, setDatabase] = useState<AccountDatabase>();
  const databaseRef = useRef<AccountDatabase | undefined>(undefined);
  const schedulerRef = useRef<ForegroundSyncScheduler | undefined>(undefined);

  const refreshSyncStatus = useCallback(async (current: AccountDatabase) => {
    const [pending, blockedOutbox, storedConflicts, lastSuccess] = await Promise.all([
      current.outbox.where("status").anyOf("pending", "syncing").count(),
      current.outbox.where("status").anyOf("failed", "conflict", "auth-blocked", "inactive-client", "upgrade-required").count(),
      current.conflicts.toArray(),
      current.syncMeta.get("last-sync-success-at"),
    ]);
    setPendingCount(pending);
    setBlockedCount(blockedOutbox + storedConflicts.length);
    setConflicts(storedConflicts);
    setLastSyncAt(typeof lastSuccess?.value === "string" ? lastSuccess.value : undefined);
  }, []);

  useEffect(() => {
    const updateOnline = () => {
      setOnline(navigator.onLine);
      if (!navigator.onLine) setSyncState("offline");
    };
    window.addEventListener("online", updateOnline);
    window.addEventListener("offline", updateOnline);
    return () => {
      window.removeEventListener("online", updateOnline);
      window.removeEventListener("offline", updateOnline);
    };
  }, []);

  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;
    const watch = (registration: ServiceWorkerRegistration) => {
      if (registration.waiting) setUpdateWorker(registration.waiting);
      registration.addEventListener("updatefound", () => {
        const installing = registration.installing;
        installing?.addEventListener("statechange", () => {
          if (installing.state === "installed" && navigator.serviceWorker.controller) setUpdateWorker(installing);
        });
      });
    };
    void navigator.serviceWorker.getRegistration().then((registration) => registration && watch(registration));
  }, []);

  useEffect(() => {
    let closed = false;
    let closeDatabase: (() => void) | undefined;
    void openAccountDatabase(session.userId, session.email)
      .then(async (database) => {
        if (closed) database.close();
        else {
          const discarded = await retireLocalTrainingData(database);
          if (discarded > 0) setStorageMessage(`${discarded} nicht synchronisierte Trainingsänderung(en) wurden verworfen. Training wird in der iPhone-App geführt.`);
          databaseRef.current = database;
          setDatabase(database);
          void refreshSyncStatus(database);
          if (!session.isOffline) {
            void resumeAfterAuthentication(database).then(() => refreshSyncStatus(database));
            const scheduler = new ForegroundSyncScheduler(database, new BrowserSyncTransport(database.accountId), (result, error) => {
              if (result) setSyncState(result.state);
              if (error instanceof SyncHttpError && error.code === "handover_required") {
                setSyncError("Dieses Konto wurde auf ein anderes Gerät übergeben. Für die Rückkehr ist die gesicherte Geräteübergabe erforderlich.");
              } else if (error instanceof SyncHttpError && error.code === "handover_in_progress") {
                setSyncError("Geräteübergabe läuft. Lokale Änderungen sind pausiert, bis sie abgeschlossen oder abgebrochen wird.");
              } else if (error) setSyncError(message(error));
              else setSyncError(undefined);
              void refreshSyncStatus(database);
            });
            schedulerRef.current = scheduler;
            scheduler.start();
          }
          closeDatabase = () => {
            schedulerRef.current?.stop();
            schedulerRef.current = undefined;
            database.close();
            if (databaseRef.current === database) databaseRef.current = undefined;
            setDatabase((current) => current === database ? undefined : current);
          };
        }
      })
      .catch((caught) => setStorageError(message(caught)));
    return () => {
      closed = true;
      closeDatabase?.();
    };
  }, [session.userId, session.email, session.isOffline, refreshSyncStatus]);

  const pendingChanged = useCallback((count: number) => {
    setPendingCount(count);
    schedulerRef.current?.mutationCommitted();
  }, []);

  async function resolveConflict(conflictId: string, useServer: boolean) {
    if (!database) return;
    setSyncError(undefined);
    try {
      if (useServer) await acceptConflictServerState(database, conflictId);
      else await retryConflictOnCurrentServerVersion(database, conflictId);
      await refreshSyncStatus(database);
      schedulerRef.current?.retryNow();
    } catch (caught) {
      setSyncError(message(caught));
    }
  }

  async function removeLocalData() {
    if (!window.confirm("Lokale Daten dieses Kontos von diesem Gerät löschen?")) return;
    setStorageError(undefined); setStorageMessage(undefined);
    databaseRef.current?.close();
    databaseRef.current = undefined;
    try {
      try {
        await deleteLocalAccountData(session.userId);
      } catch (caught) {
        if (!(caught instanceof PendingLocalMutationsError)) throw caught;
        const confirmed = window.confirm(
          `${caught.pendingCount} Änderung(en) sind noch nicht synchronisiert und gehen verloren. Trotzdem löschen?`,
        );
        if (!confirmed) {
          databaseRef.current = await openAccountDatabase(session.userId, session.email);
          setDatabase(databaseRef.current);
          return;
        }
        await deleteLocalAccountData(session.userId, true);
      }
      databaseRef.current = await openAccountDatabase(session.userId, session.email);
      setDatabase(databaseRef.current);
      setPendingCount(0); setBlockedCount(0);
      setStorageMessage("Die lokalen Kontodaten wurden gelöscht.");
    } catch (caught) {
      setStorageError(message(caught));
      databaseRef.current = await openAccountDatabase(session.userId, session.email).catch(() => undefined);
      setDatabase(databaseRef.current);
    }
  }

  async function signOut() {
    onLogout();
    try { await logout(); } catch { /* The personal UI stays cleared even if the request fails. */ }
  }

  const panelClass = (tab: TabId) => `${activeTab === tab ? "block" : "hidden"} tab-panel`;
  const activeItem = navigationItems.find((item) => item.id === activeTab)!;

  return (
    <main className="app-shell min-h-dvh pb-28 md:pb-10">
      <header className="app-glass sticky top-0 z-30 border-b px-4 py-3 md:static md:bg-transparent md:shadow-none md:backdrop-blur-none">
        <div className="mx-auto flex max-w-7xl items-center justify-between gap-4">
          <div className="min-w-0"><p className="text-xs font-semibold uppercase tracking-[0.12em] text-primary md:text-sm md:normal-case md:tracking-normal">{activeItem.label}</p><h1 className="truncate text-2xl font-bold md:mt-1 md:text-4xl">Dein Bereich</h1><p className="mt-1 hidden truncate text-sm text-muted-foreground sm:block">{session.email}{session.isOffline ? " · Offline" : ""}</p></div>
          <div className="flex items-center gap-2"><ThemeToggle /><Button aria-label="Abmelden" title="Abmelden" type="button" size="icon" variant="outline" onClick={signOut}><LogOut aria-hidden="true" /></Button></div>
        </div>
      </header>
      <div className="mx-auto max-w-7xl space-y-4 px-4 pt-4 sm:px-6 md:pt-7 lg:px-8">
        {!online && <div role="status" className="flex items-center gap-3 rounded-2xl bg-amber-500/12 px-4 py-3 text-sm text-amber-800 dark:text-amber-300"><span className="flex size-8 shrink-0 items-center justify-center rounded-full bg-amber-500/15"><Monitor className="size-4" aria-hidden="true" /></span><span>Offline – lokale Daten bleiben verfügbar; Online-Funktionen pausieren.</span></div>}
        {updateWorker && <div role="status" className="flex items-center justify-between gap-3 rounded-2xl bg-primary/10 px-4 py-3 text-sm"><span>Eine neue App-Version ist bereit. Offene Eingaben bleiben erhalten.</span><Button type="button" size="sm" variant="outline" onClick={() => { updateWorker.postMessage({ type: "SKIP_WAITING" }); setUpdateWorker(undefined); }}>Aktualisieren</Button></div>}
        {storageError && <p role="alert" className="rounded-2xl bg-destructive/10 p-4 text-sm text-destructive">Lokaler Speicher konnte nicht geöffnet werden: {storageError}</p>}
        {storageMessage && <p role="status" className="rounded-2xl bg-primary/10 p-4 text-sm">{storageMessage}</p>}
        <div className="grid gap-7 md:grid-cols-[15rem_minmax(0,1fr)]">
          <nav aria-label="Hauptnavigation" className="app-glass sticky top-6 hidden h-fit rounded-[1.75rem] border p-2.5 md:block">
            <div className="mb-3 flex items-center gap-3 px-3 py-3"><span className="flex size-10 items-center justify-center rounded-xl bg-primary text-primary-foreground"><Dumbbell className="size-5" aria-hidden="true" /></span><div><p className="font-bold">Gainer</p><p className="text-xs text-muted-foreground">Train smarter</p></div></div>
            {navigationItems.map((item) => <button key={item.id} type="button" onClick={() => { setActiveTab(item.id); document.getElementById(item.target)?.scrollIntoView({ behavior: "smooth", block: "start" }); }} className={`flex min-h-11 w-full items-center gap-3 rounded-xl px-3 text-left text-sm font-semibold transition-colors ${activeTab === item.id ? "bg-primary text-primary-foreground shadow-sm" : "text-muted-foreground hover:bg-muted hover:text-foreground"}`}><item.icon className="size-5" aria-hidden="true" />{item.label}</button>)}
          </nav>
          <div className="app-content min-w-0 space-y-6">
            <div className={panelClass("home")}><div className="space-y-6">
              <p role="note" className="rounded-2xl border bg-card p-4 text-sm text-muted-foreground">Training ist in der iPhone-App verfügbar.</p>
              {database ? <InsightsDashboard database={database} online={online} /> : <section className="rounded-2xl border bg-card p-6 text-sm text-muted-foreground">Lokale Daten werden geöffnet …</section>}
              <section aria-label="Synchronisationsstatus" className="grid gap-4 rounded-2xl border bg-card p-5 sm:grid-cols-4">
                <StatusValue label="Verbindung" value={online ? "Online" : "Offline"} />
                <StatusValue label="Sync" value={syncStateLabel(syncState)} />
                <StatusValue label="Ausstehend" value={String(pendingCount)} />
                <StatusValue label="Blockiert/Fehler" value={String(blockedCount)} />
                {lastSyncAt && <p className="text-xs text-muted-foreground sm:col-span-4">Letzter erfolgreicher Abgleich: {new Date(lastSyncAt).toLocaleString("de-DE")}</p>}
                {syncError && <p role="alert" className="text-xs text-destructive sm:col-span-4">{syncError}</p>}
                <div className="flex flex-wrap gap-2 sm:col-span-4"><Button type="button" size="sm" variant="outline" disabled={!online} onClick={() => schedulerRef.current?.retryNow()}>Erneut synchronisieren</Button></div>
                <p className="text-xs leading-5 text-muted-foreground sm:col-span-4">Lokaler Speicher ist kein Backup. Noch nicht synchronisierte Daten können bei Browser- oder Gerätespeicherverlust verloren gehen.</p>
              </section>
              {database && <SyncHandoverPanel database={database} online={online} />}
              {conflicts.length > 0 && <section aria-label="Synchronisationskonflikte" className="space-y-3 rounded-2xl border border-amber-300 bg-card p-5"><h2 className="font-semibold">Konflikte prüfen</h2>{conflicts.map((conflict) => <div className="rounded-lg border p-3" key={conflict.conflictId}><p className="text-sm">{conflict.aggregateKey}</p><div className="mt-2 flex gap-2"><Button size="sm" variant="outline" onClick={() => void resolveConflict(conflict.conflictId, true)}>Serverstand übernehmen</Button><Button size="sm" onClick={() => void resolveConflict(conflict.conflictId, false)}>Lokale Änderung erneut anwenden</Button></div></div>)}</section>}
              <section className="rounded-2xl border bg-card p-6"><h2 className="text-lg font-semibold">Lokaler Speicher</h2><p className="mt-2 text-sm text-muted-foreground">Verwalte die nur auf diesem Gerät gespeicherten Kontodaten.</p><Button className="mt-4" type="button" variant="destructive" onClick={removeLocalData}>Lokale Daten löschen</Button></section>
              {session.isAccountOperator && <OperatorPanel currentAccountId={session.userId} />}
            </div></div>
            <div className={panelClass("tracking")}>{database && <BodyTrackingPanel database={database} onPendingChange={pendingChanged} />}</div>
            <div className={panelClass("nutrition")}>{database && <NutritionPanel database={database} online={online} onPendingChange={pendingChanged} />}</div>
            <div className={panelClass("coach")}><CoachPanel online={online} /></div>
          </div>
        </div>
      </div>
      <nav aria-label="Mobile Hauptnavigation" className="bottom-nav app-glass fixed inset-x-2 bottom-2 z-40 grid grid-cols-4 rounded-[1.6rem] border px-1.5 pt-1.5 md:hidden">
        {navigationItems.map((item) => <button key={item.id} type="button" aria-current={activeTab === item.id ? "page" : undefined} onClick={() => { setActiveTab(item.id); window.scrollTo({ top: 0, behavior: "smooth" }); }} className={`flex min-h-14 min-w-0 flex-col items-center justify-center gap-0.5 rounded-[1.15rem] px-1 text-[0.68rem] font-semibold transition-[transform,background-color,color] active:scale-95 ${activeTab === item.id ? "bg-primary/12 text-primary" : "text-muted-foreground"}`}><item.icon className={`size-5 ${activeTab === item.id ? "stroke-[2.6]" : ""}`} aria-hidden="true" /><span className="truncate">{item.label}</span></button>)}
      </nav>
    </main>
  );
}

const navigationItems = [
  { id: "home", target: "overview", label: "Heute", icon: Home },
  { id: "tracking", target: "check-in", label: "Check-in", icon: HeartPulse },
  { id: "nutrition", target: "nutrition", label: "Essen", icon: Utensils },
  { id: "coach", target: "coach", label: "Coach", icon: Sparkles },
] as const;

type TabId = typeof navigationItems[number]["id"];

type ThemeMode = "system" | "light" | "dark";

function ThemeToggle({ className = "" }: { className?: string }) {
  const [mode, setMode] = useState<ThemeMode>("system");

  useEffect(() => {
    const stored = localStorage.getItem("gainer-theme");
    const syncStoredMode = window.setTimeout(() => {
      if (stored === "light" || stored === "dark" || stored === "system") setMode(stored);
    }, 0);
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const syncSystem = () => {
      if ((localStorage.getItem("gainer-theme") ?? "system") === "system") {
        document.documentElement.classList.toggle("dark", media.matches);
      }
    };
    media.addEventListener("change", syncSystem);
    return () => {
      window.clearTimeout(syncStoredMode);
      media.removeEventListener("change", syncSystem);
    };
  }, []);

  const changeMode = () => {
    const next: ThemeMode = mode === "system" ? "light" : mode === "light" ? "dark" : "system";
    const dark = next === "dark" || (next === "system" && window.matchMedia("(prefers-color-scheme: dark)").matches);
    localStorage.setItem("gainer-theme", next);
    document.documentElement.dataset.theme = next;
    document.documentElement.classList.toggle("dark", dark);
    setMode(next);
  };

  const Icon = mode === "light" ? Sun : mode === "dark" ? Moon : Monitor;
  const label = mode === "light" ? "Darstellung: Hell" : mode === "dark" ? "Darstellung: Dunkel" : "Darstellung: System";
  return <Button className={className} aria-label={label} title={`${label} · wechseln`} type="button" size="icon" variant="outline" onClick={changeMode}><Icon aria-hidden="true" /></Button>;
}

function StatusValue({ label, value }: { label: string; value: string }) {
  return <div><p className="text-xs font-medium text-muted-foreground">{label}</p><p className="mt-1 text-lg font-semibold">{value}</p></div>;
}

function syncStateLabel(state: SyncRunResult["state"] | "offline"): string {
  return ({
    idle: "Aktuell", synced: "Synchronisiert", offline: "Pausiert",
    "auth-blocked": "Anmeldung nötig", "inactive-client": "Nur Lesen",
    "upgrade-required": "Update nötig",
  } as const)[state];
}

function OperatorPanel({ currentAccountId }: { currentAccountId: string }) {
  const [accounts, setAccounts] = useState<AccountSummary[]>([]);
  const [invitationLink, setInvitationLink] = useState("");
  const [error, setError] = useState<string>();
  const [busy, setBusy] = useState(false);
  useEffect(() => { void listAccounts().then(setAccounts).catch((caught) => setError(message(caught))); }, []);

  async function invite(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = event.currentTarget;
    const email = String(new FormData(form).get("email"));
    setBusy(true); setError(undefined);
    try {
      const invitation = await createInvitation(email);
      setInvitationLink(new URL(invitation.activationPath, window.location.origin).toString());
      form.reset();
      setAccounts(await listAccounts());
    } catch (caught) { setError(message(caught)); }
    finally { setBusy(false); }
  }

  async function toggle(account: AccountSummary) {
    setError(undefined);
    try {
      await setAccountStatus(account.accountId, !account.isActive);
      setAccounts((current) => current.map((item) => item.accountId === account.accountId ? { ...item, isActive: !item.isActive } : item));
    } catch (caught) { setError(message(caught)); }
  }

  return (
    <section className="space-y-5 rounded-2xl border bg-card p-6">
      <div><p className="text-sm font-medium text-muted-foreground">Nur für Account Operator</p><h2 className="mt-1 text-xl font-semibold">Kontoverwaltung</h2></div>
      <form className="flex flex-col gap-3 sm:flex-row sm:items-end" onSubmit={invite}>
        <label className="block flex-1 space-y-2 text-sm font-medium"><span>Kollegen einladen</span><input className={inputClass} name="email" type="email" required /></label>
        <Button className="h-11" type="submit" disabled={busy}>Einladung erstellen</Button>
      </form>
      {invitationLink && <label className="block space-y-2 text-sm font-medium"><span>Einladungslink</span><input className={inputClass} readOnly value={invitationLink} onFocus={(event) => event.currentTarget.select()} /></label>}
      {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
      <div className="divide-y rounded-xl border">
        {accounts.length === 0 ? <p className="p-4 text-sm text-muted-foreground">Noch keine Konten vorhanden.</p> : accounts.map((account) => (
          <div className="flex items-center justify-between gap-3 p-4" key={account.accountId}>
            <div><p className="text-sm font-medium">{account.email}</p><p className="text-xs text-muted-foreground">{account.isActive ? "Aktiv" : "Deaktiviert"}</p></div>
            <Button type="button" variant={account.isActive ? "destructive" : "outline"} disabled={account.accountId === currentAccountId} onClick={() => toggle(account)}>{account.isActive ? "Deaktivieren" : "Reaktivieren"}</Button>
          </div>
        ))}
      </div>
    </section>
  );
}
