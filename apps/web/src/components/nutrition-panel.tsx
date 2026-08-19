"use client";

import { type FormEvent, useCallback, useEffect, useRef, useState } from "react";
import {
  Apple,
  Barcode,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  ChevronUp,
  Plus,
  Search,
  Trash2,
  Utensils,
  X,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  FoodCatalogApiError,
  lookupFoodBarcode,
  searchFoods,
  type FoodCatalogProduct,
} from "@/lib/api/client";
import type { AccountDatabase } from "@/lib/offline/database";
import {
  createNutritionEntry,
  deleteLocalNutritionDay,
  meals,
  NutritionInputError,
  readLocalNutritionDay,
  recentLocalNutritionEntries,
  saveLocalNutritionDay,
  sumNutrition,
  type LocalNutritionEntry,
  type MealType,
} from "@/lib/offline/nutrition-tracking";

const mealLabels: Record<MealType, string> = {
  Breakfast: "Frühstück",
  Lunch: "Mittagessen",
  Dinner: "Abendessen",
  Snacks: "Snacks",
};
const inputClass = "h-11 w-full rounded-xl border bg-background px-3 text-sm outline-none";
type AddMode = "recent" | "barcode" | "search" | "manual";
type DayView = Awaited<ReturnType<typeof readLocalNutritionDay>>;

export function NutritionPanel({
  database,
  online,
  onPendingChange,
}: {
  database: AccountDatabase;
  online: boolean;
  onPendingChange: (count: number) => void;
}) {
  const [localDate, setLocalDate] = useState(today());
  const [day, setDay] = useState<DayView>();
  const [recent, setRecent] = useState<LocalNutritionEntry[]>([]);
  const [sheet, setSheet] = useState<{ meal: MealType; entry?: LocalNutritionEntry }>();
  const [message, setMessage] = useState<string>();
  const [error, setError] = useState<string>();

  const refresh = useCallback(async () => {
    const [loaded, used, pending] = await Promise.all([
      readLocalNutritionDay(database, localDate),
      recentLocalNutritionEntries(database),
      database.outbox.where("status").equals("pending").count(),
    ]);
    setDay(loaded);
    setRecent(used);
    onPendingChange(pending);
  }, [database, localDate, onPendingChange]);

  useEffect(() => {
    let current = true;
    void Promise.all([
      readLocalNutritionDay(database, localDate),
      recentLocalNutritionEntries(database),
      database.outbox.where("status").equals("pending").count(),
    ]).then(([loaded, used, pending]) => {
      if (!current) return;
      setDay(loaded);
      setRecent(used);
      onPendingChange(pending);
    });
    return () => { current = false; };
  }, [database, localDate, onPendingChange]);

  async function saveEntry(entry: LocalNutritionEntry) {
    const entries = [...(day?.entries ?? [])];
    const existingIndex = entries.findIndex((item) => item.entryId === entry.entryId);
    if (existingIndex >= 0) entries[existingIndex] = entry;
    else entries.push(entry);
    await saveLocalNutritionDay(database, localDate, normalizePositions(entries));
    setSheet(undefined);
    setMessage(existingIndex >= 0 ? "Eintrag aktualisiert." : "Eintrag hinzugefügt.");
    await refresh();
  }

  async function remove(entryId: string) {
    if (!window.confirm("Lebensmittel aus diesem Tag entfernen?")) return;
    const entries = (day?.entries ?? []).filter((entry) => entry.entryId !== entryId);
    if (entries.length) await saveLocalNutritionDay(database, localDate, normalizePositions(entries));
    else await deleteLocalNutritionDay(database, localDate);
    setMessage("Eintrag entfernt.");
    await refresh();
  }

  async function move(entryId: string, direction: -1 | 1) {
    const entries = [...(day?.entries ?? [])];
    const index = entries.findIndex((item) => item.entryId === entryId);
    if (index < 0) return;
    const mealEntries = entries.filter((item) => item.meal === entries[index]!.meal).sort((a, b) => a.position - b.position);
    const mealIndex = mealEntries.findIndex((item) => item.entryId === entryId);
    const other = mealEntries[mealIndex + direction];
    if (!other) return;
    const position = entries[index]!.position;
    entries[index] = { ...entries[index]!, position: other.position };
    const otherIndex = entries.findIndex((item) => item.entryId === other.entryId);
    entries[otherIndex] = { ...entries[otherIndex]!, position };
    await saveLocalNutritionDay(database, localDate, entries);
    await refresh();
  }

  const totals = day?.totals ?? { kilocalories: 0, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0 };
  return (
    <div id="nutrition" className="space-y-4">
      <section className="overflow-hidden rounded-[1.75rem] border bg-card">
        <div className="bg-gradient-to-br from-primary/14 via-primary/5 to-transparent p-5 sm:p-6">
          <div className="flex items-center justify-between gap-3">
            <Button type="button" size="icon" variant="outline" aria-label="Vorheriger Tag" onClick={() => setLocalDate(shiftDate(localDate, -1))}><ChevronLeft aria-hidden="true" /></Button>
            <label className="text-center"><span className="block text-xs font-semibold uppercase tracking-wider text-muted-foreground">Ernährungstag</span><input aria-label="Ernährungstag auswählen" className="mt-1 bg-transparent text-center text-lg font-bold outline-none" type="date" value={localDate} onChange={(event) => setLocalDate(event.target.value)} /></label>
            <Button type="button" size="icon" variant="outline" aria-label="Nächster Tag" onClick={() => setLocalDate(shiftDate(localDate, 1))}><ChevronRight aria-hidden="true" /></Button>
          </div>
          <div className="mt-6 grid grid-cols-[1.2fr_repeat(3,1fr)] gap-2 rounded-2xl bg-background/70 p-3 text-center backdrop-blur-sm">
            <Metric label="kcal" value={format(totals.kilocalories, 0)} prominent />
            <Metric label="Protein" value={format(totals.proteinGrams)} suffix="g" />
            <Metric label="Carbs" value={format(totals.carbohydrateGrams)} suffix="g" />
            <Metric label="Fett" value={format(totals.fatGrams)} suffix="g" />
          </div>
          {day?.syncState === "pending" && <p role="status" className="mt-3 text-center text-xs text-muted-foreground">Lokal gespeichert · Synchronisierung ausstehend</p>}
        </div>
      </section>

      {error && <p role="alert" className="rounded-2xl bg-destructive/10 p-4 text-sm text-destructive">{error}</p>}
      {message && <p role="status" className="rounded-2xl bg-emerald-500/12 p-4 text-sm text-emerald-800 dark:text-emerald-300">{message}</p>}

      <div className="space-y-3">
        {meals.map((meal) => {
          const entries = (day?.entries ?? []).filter((entry) => entry.meal === meal).sort((a, b) => a.position - b.position);
          const mealTotals = sumNutrition(entries);
          return (
            <section key={meal} aria-labelledby={`meal-${meal}`} className="rounded-[1.5rem] border bg-card p-4 sm:p-5">
              <div className="flex items-center justify-between gap-3">
                <div><h2 id={`meal-${meal}`} className="text-lg font-bold">{mealLabels[meal]}</h2><p className="text-xs text-muted-foreground">{format(mealTotals.kilocalories, 0)} kcal · {entries.length} {entries.length === 1 ? "Eintrag" : "Einträge"}</p></div>
                <Button type="button" size="sm" variant="outline" onClick={() => { setError(undefined); setMessage(undefined); setSheet({ meal }); }}><Plus aria-hidden="true" /> Hinzufügen</Button>
              </div>
              {entries.length === 0 ? <button type="button" className="mt-4 flex min-h-20 w-full items-center justify-center rounded-2xl border border-dashed text-sm text-muted-foreground hover:bg-muted/50" onClick={() => setSheet({ meal })}>Noch nichts eingetragen</button> : (
                <ul className="mt-3 divide-y">
                  {entries.map((entry, index) => <li key={entry.entryId} className="flex items-center gap-3 py-3">
                    <button type="button" className="min-w-0 flex-1 text-left" onClick={() => setSheet({ meal: entry.meal, entry })}>
                      <span className="block truncate font-semibold">{entry.productName}</span>
                      <span className="block text-xs text-muted-foreground">{format(entry.amountGrams)} g · {format(entry.totals.kilocalories, 0)} kcal{entry.brand ? ` · ${entry.brand}` : ""}</span>
                    </button>
                    <div className="flex shrink-0 gap-1">
                      <button type="button" className="rounded-lg p-2 text-muted-foreground disabled:opacity-25" aria-label={`${entry.productName} nach oben`} disabled={index === 0} onClick={() => void move(entry.entryId, -1)}><ChevronUp className="size-4" /></button>
                      <button type="button" className="rounded-lg p-2 text-muted-foreground disabled:opacity-25" aria-label={`${entry.productName} nach unten`} disabled={index === entries.length - 1} onClick={() => void move(entry.entryId, 1)}><ChevronDown className="size-4" /></button>
                      <button type="button" className="rounded-lg p-2 text-destructive" aria-label={`${entry.productName} löschen`} onClick={() => void remove(entry.entryId)}><Trash2 className="size-4" /></button>
                    </div>
                  </li>)}
                </ul>
              )}
            </section>
          );
        })}
      </div>

      {sheet && <NutritionSheet
        meal={sheet.meal}
        existing={sheet.entry}
        recent={recent}
        online={online}
        onClose={() => setSheet(undefined)}
        onSave={async (entry) => {
          setError(undefined);
          try { await saveEntry(entry); }
          catch (caught) { setError(errorMessage(caught)); }
        }}
      />}
    </div>
  );
}

function NutritionSheet({
  meal,
  existing,
  recent,
  online,
  onClose,
  onSave,
}: {
  meal: MealType;
  existing?: LocalNutritionEntry;
  recent: LocalNutritionEntry[];
  online: boolean;
  onClose: () => void;
  onSave: (entry: LocalNutritionEntry) => Promise<void>;
}) {
  const [mode, setMode] = useState<AddMode>(existing ? "manual" : "recent");
  const [seed, setSeed] = useState<LocalNutritionEntry | undefined>(existing);
  const [results, setResults] = useState<FoodCatalogProduct[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [scanning, setScanning] = useState(false);
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | undefined>(undefined);
  const scanFrameRef = useRef<number | undefined>(undefined);
  const sheetRef = useRef<HTMLElement | null>(null);

  const stopScan = useCallback(() => {
    if (scanFrameRef.current) cancelAnimationFrame(scanFrameRef.current);
    streamRef.current?.getTracks().forEach((track) => track.stop());
    streamRef.current = undefined;
    setScanning(false);
  }, []);
  useEffect(() => stopScan, [stopScan]);
  useEffect(() => {
    sheetRef.current?.focus();
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") { stopScan(); onClose(); }
    };
    window.addEventListener("keydown", closeOnEscape);
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, [onClose, stopScan]);

  async function lookup(barcode: string) {
    if (!online) { setError("Barcode-Suche ist offline nicht verfügbar. Du kannst das Produkt manuell erfassen."); return; }
    setBusy(true); setError(undefined);
    try { chooseProduct(await lookupFoodBarcode(barcode)); }
    catch (caught) { setError(foodError(caught)); }
    finally { setBusy(false); }
  }

  async function startScanner() {
    const Detector = (window as unknown as { BarcodeDetector?: BarcodeDetectorConstructor }).BarcodeDetector;
    if (!Detector) { setError("Der Kamerascan wird auf diesem Gerät nicht unterstützt. Bitte Barcode eintippen."); return; }
    try {
      setError(undefined);
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: "environment" } }, audio: false });
      streamRef.current = stream;
      if (!videoRef.current) return;
      videoRef.current.srcObject = stream;
      await videoRef.current.play();
      setScanning(true);
      const detector = new Detector({ formats: ["ean_13", "ean_8", "upc_a", "upc_e"] });
      const scan = async () => {
        if (!videoRef.current || !streamRef.current) return;
        const codes = await detector.detect(videoRef.current).catch(() => []);
        if (codes[0]?.rawValue) { stopScan(); await lookup(codes[0].rawValue); return; }
        scanFrameRef.current = requestAnimationFrame(() => void scan());
      };
      scanFrameRef.current = requestAnimationFrame(() => void scan());
    } catch {
      stopScan();
      setError("Kamerazugriff wurde nicht erlaubt. Barcodeeingabe und Suche bleiben verfügbar.");
    }
  }

  function chooseProduct(product: FoodCatalogProduct) {
    setSeed(createNutritionEntry({
      meal,
      position: existing?.position ?? 0,
      productName: product.productName,
      brand: product.brand,
      amountGrams: 100,
      per100Grams: {
        kilocalories: Number(product.kilocaloriesPer100Grams),
        proteinGrams: nullableApiNumber(product.proteinGramsPer100Grams),
        carbohydrateGrams: nullableApiNumber(product.carbohydrateGramsPer100Grams),
        fatGrams: nullableApiNumber(product.fatGramsPer100Grams),
      },
      source: {
        provider: product.source,
        barcode: product.barcode,
        retrievedAtUtc: product.retrievedAtUtc,
        basisGrams: Number(product.basisGrams),
      },
    }));
    setMode("manual");
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/35 p-0 backdrop-blur-[2px] sm:items-center sm:p-6" role="dialog" aria-modal="true" aria-labelledby="nutrition-sheet-title">
      <section ref={sheetRef} tabIndex={-1} className="max-h-[92dvh] w-full max-w-xl overflow-y-auto rounded-t-[2rem] border bg-card p-5 pb-[max(1.25rem,env(safe-area-inset-bottom))] shadow-2xl outline-none sm:rounded-[2rem] sm:p-6">
        <div className="flex items-center justify-between"><div><p className="text-xs font-semibold uppercase tracking-wider text-primary">{mealLabels[meal]}</p><h2 id="nutrition-sheet-title" className="text-xl font-bold">{existing ? "Eintrag bearbeiten" : "Lebensmittel hinzufügen"}</h2></div><Button type="button" size="icon" variant="ghost" aria-label="Schließen" onClick={() => { stopScan(); onClose(); }}><X /></Button></div>
        {!existing && <div className="mt-4 grid grid-cols-4 gap-1 rounded-xl bg-muted p-1" role="tablist" aria-label="Erfassungsart">
          {(["recent", "barcode", "search", "manual"] as const).map((item) => <button key={item} type="button" role="tab" aria-selected={mode === item} className={`min-h-10 rounded-lg px-1 text-xs font-semibold ${mode === item ? "bg-card text-foreground shadow-sm" : "text-muted-foreground"}`} onClick={() => { stopScan(); setMode(item); setError(undefined); }}>{modeLabel(item)}</button>)}
        </div>}
        {error && <p role="alert" className="mt-4 rounded-xl bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}

        {mode === "recent" && <div className="mt-4 space-y-2">{recent.length ? recent.map((entry) => <button type="button" key={`${entry.entryId}-${entry.productName}`} className="flex w-full items-center justify-between rounded-xl border p-3 text-left hover:bg-muted/50" onClick={() => { setSeed({ ...entry, entryId: crypto.randomUUID(), meal, position: 0 }); setMode("manual"); }}><span><span className="block font-semibold">{entry.productName}</span><span className="text-xs text-muted-foreground">{format(entry.amountGrams)} g · {format(entry.totals.kilocalories, 0)} kcal</span></span><Apple className="size-5 text-primary" /></button>) : <p className="rounded-xl border border-dashed p-5 text-center text-sm text-muted-foreground">Noch keine zuletzt verwendeten Lebensmittel auf diesem Gerät.</p>}</div>}

        {mode === "barcode" && <div className="mt-4 space-y-4">
          <video ref={videoRef} muted playsInline className={`${scanning ? "block" : "hidden"} aspect-video w-full rounded-2xl bg-black object-cover`} />
          <Button type="button" className="w-full" variant="outline" disabled={!online || scanning} onClick={() => void startScanner()}><Barcode /> {scanning ? "Kamera läuft …" : "Barcode mit Kamera scannen"}</Button>
          <LookupForm busy={busy} onSubmit={(value) => void lookup(value)} />
          {!online && <p className="text-sm text-muted-foreground">Offline: Nutze „Zuletzt“ oder „Manuell“.</p>}
        </div>}

        {mode === "search" && <form className="mt-4 space-y-3" onSubmit={async (event) => {
          event.preventDefault(); if (!online || busy) return;
          const query = String(new FormData(event.currentTarget).get("query") ?? "").trim();
          if (query.length < 2) { setError("Bitte mindestens zwei Zeichen eingeben."); return; }
          setBusy(true); setError(undefined);
          try { setResults((await searchFoods(query)).products); }
          catch (caught) { setError(foodError(caught)); }
          finally { setBusy(false); }
        }}>
          <div className="flex gap-2"><input className={inputClass} name="query" aria-label="Produkt oder Marke" placeholder="Produkt oder Marke" minLength={2} maxLength={100} required /><Button type="submit" disabled={!online || busy} aria-label="Suche absenden"><Search />{busy ? "Suche …" : "Suchen"}</Button></div>
          {!online && <p className="text-sm text-muted-foreground">Die externe Suche ist offline nicht verfügbar.</p>}
          <div className="space-y-2">{results.map((product) => <button type="button" key={product.barcode} className="w-full rounded-xl border p-3 text-left hover:bg-muted/50" onClick={() => chooseProduct(product)}><span className="block font-semibold">{product.productName}</span><span className="text-xs text-muted-foreground">{product.brand ? `${product.brand} · ` : ""}{format(Number(product.kilocaloriesPer100Grams), 0)} kcal / 100 g</span>{product.qualityIndicators.length > 0 && <span className="mt-1 block text-xs text-amber-700 dark:text-amber-300">Einzelne Angaben fehlen – bitte Verpackung prüfen.</span>}</button>)}</div>
        </form>}

        {mode === "manual" && <EntryForm key={seed?.entryId ?? "new"} meal={meal} seed={seed} onSave={onSave} />}

        {(mode === "search" || mode === "barcode" || seed?.source) && <p className="mt-5 text-xs leading-5 text-muted-foreground">Quelle: Open Food Facts (ODbL). Community-Daten können unvollständig oder fehlerhaft sein; gleiche die Werte bei Bedarf mit der Verpackung ab. Es werden keine Produktbilder verwendet.</p>}
      </section>
    </div>
  );
}

function EntryForm({ meal, seed, onSave }: { meal: MealType; seed?: LocalNutritionEntry; onSave: (entry: LocalNutritionEntry) => Promise<void> }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  return <form className="mt-4 grid gap-3 sm:grid-cols-2" onSubmit={async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); setBusy(true); setError(undefined);
    const form = new FormData(event.currentTarget);
    try {
      await onSave(createNutritionEntry({
        entryId: seed?.entryId,
        meal: String(form.get("meal")) as MealType,
        position: seed?.position ?? 0,
        productName: String(form.get("productName")),
        brand: nullableText(form.get("brand")),
        amountGrams: Number(form.get("amountGrams")),
        per100Grams: {
          kilocalories: Number(form.get("kilocalories")),
          proteinGrams: nullableNumber(form.get("protein")),
          carbohydrateGrams: nullableNumber(form.get("carbohydrates")),
          fatGrams: nullableNumber(form.get("fat")),
        },
        source: seed?.source,
      }));
    } catch (caught) { setError(errorMessage(caught)); }
    finally { setBusy(false); }
  }}>
    <Field label="Lebensmittel"><input className={inputClass} name="productName" defaultValue={seed?.productName} maxLength={200} required /></Field>
    <Field label="Marke (optional)"><input className={inputClass} name="brand" defaultValue={seed?.brand ?? ""} maxLength={160} /></Field>
    <Field label="Mahlzeit"><select className={inputClass} name="meal" defaultValue={seed?.meal ?? meal}>{meals.map((item) => <option key={item} value={item}>{mealLabels[item]}</option>)}</select></Field>
    <Field label="Menge (g)"><input className={inputClass} name="amountGrams" type="number" min="0.01" step="0.01" defaultValue={seed?.amountGrams ?? 100} required /></Field>
    <Field label="kcal pro 100 g"><input className={inputClass} name="kilocalories" type="number" min="0.01" step="0.01" defaultValue={seed?.per100Grams.kilocalories} required /></Field>
    <Field label="Protein pro 100 g"><input className={inputClass} name="protein" type="number" min="0" step="0.01" defaultValue={seed?.per100Grams.proteinGrams ?? ""} /></Field>
    <Field label="Kohlenhydrate pro 100 g"><input className={inputClass} name="carbohydrates" type="number" min="0" step="0.01" defaultValue={seed?.per100Grams.carbohydrateGrams ?? ""} /></Field>
    <Field label="Fett pro 100 g"><input className={inputClass} name="fat" type="number" min="0" step="0.01" defaultValue={seed?.per100Grams.fatGrams ?? ""} /></Field>
    {error && <p role="alert" className="text-sm text-destructive sm:col-span-2">{error}</p>}
    <Button type="submit" disabled={busy} className="sm:col-span-2"><Utensils />{busy ? "Speichert …" : "Eintrag speichern"}</Button>
  </form>;
}

function LookupForm({ busy, onSubmit }: { busy: boolean; onSubmit: (barcode: string) => void }) {
  return <form className="flex gap-2" onSubmit={(event) => { event.preventDefault(); onSubmit(String(new FormData(event.currentTarget).get("barcode") ?? "")); }}><input className={inputClass} name="barcode" aria-label="Barcode manuell eingeben" inputMode="numeric" pattern="[0-9]{4,32}" placeholder="Barcode eintippen" required /><Button type="submit" disabled={busy}>Nachschlagen</Button></form>;
}

function Field({ label, children }: { label: string; children: React.ReactNode }) { return <label className="space-y-1.5 text-sm font-medium"><span>{label}</span>{children}</label>; }
function Metric({ label, value, suffix, prominent = false }: { label: string; value: string; suffix?: string; prominent?: boolean }) { return <div><p className={`${prominent ? "text-xl" : "text-base"} font-bold tabular-nums`}>{value}{suffix && <span className="ml-0.5 text-xs font-medium text-muted-foreground">{suffix}</span>}</p><p className="text-[0.65rem] text-muted-foreground">{label}</p></div>; }
function modeLabel(mode: AddMode) { return ({ recent: "Zuletzt", barcode: "Barcode", search: "Suchen", manual: "Manuell" })[mode]; }
function normalizePositions(entries: LocalNutritionEntry[]) { return meals.flatMap((meal) => entries.filter((entry) => entry.meal === meal).sort((a, b) => a.position - b.position).map((entry, position) => ({ ...entry, position }))); }
function nullableText(value: FormDataEntryValue | null) { return String(value ?? "").trim() || null; }
function nullableNumber(value: FormDataEntryValue | null) { const text = String(value ?? "").trim(); return text ? Number(text) : null; }
function nullableApiNumber(value: number | string | null) { return value === null ? null : Number(value); }
function format(value: number | null, digits = 1) { return value === null ? "–" : new Intl.NumberFormat("de-DE", { maximumFractionDigits: digits }).format(value); }
function today() { const date = new Date(); return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`; }
function shiftDate(value: string, days: number) { const date = new Date(`${value}T12:00:00`); date.setDate(date.getDate() + days); return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`; }
function errorMessage(error: unknown) { if (error instanceof NutritionInputError) return Object.values(error.fields).join(" "); return error instanceof Error ? error.message : "Lokales Speichern ist fehlgeschlagen."; }
function foodError(error: unknown) { if (error instanceof FoodCatalogApiError) { if (error.code === "product_not_found") return "Kein Produkt gefunden. Du kannst es manuell erfassen."; if (error.status === 429) return "Zu viele Anfragen. Bitte kurz warten oder manuell erfassen."; if (error.status >= 500) return "Open Food Facts ist vorübergehend nicht erreichbar. Manuelle Erfassung bleibt verfügbar."; } return error instanceof Error ? error.message : "Die Produktsuche ist fehlgeschlagen."; }

interface BarcodeDetectorConstructor {
  new(options?: { formats?: string[] }): { detect(source: HTMLVideoElement): Promise<{ rawValue: string }[]> };
}
