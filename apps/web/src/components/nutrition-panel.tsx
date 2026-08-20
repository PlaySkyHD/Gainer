"use client";

import { type FormEvent, useCallback, useEffect, useRef, useState } from "react";
import {
  Apple,
  Barcode,
  ChefHat,
  Copy,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  ChevronUp,
  Plus,
  Search,
  SlidersHorizontal,
  Sparkles,
  Trash2,
  Utensils,
  X,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  FoodCatalogApiError,
  estimateMeal,
  lookupFoodBarcode,
  searchFoods,
  type FoodCatalogProduct,
} from "@/lib/api/client";
import type { AccountDatabase } from "@/lib/offline/database";
import {
  deleteLocalNutritionDay,
  meals,
  NutritionInputError,
  readLocalNutritionDay,
  recentLocalNutritionEntries,
  saveLocalNutritionDay,
  sumNutrition,
  type LocalNutritionEntry,
  type LocalNutritionTotals,
  type MealType,
} from "@/lib/offline/nutrition-tracking";
import {
  addReusableMealToDay,
  archiveReusableMeal,
  deriveMacroTargets,
  effectiveTarget,
  readNutritionTargetSchedule,
  readReusableMeals,
  removeNutritionTargetVersion,
  saveNutritionTargetVersion,
  saveReusableMeal,
  type LocalNutritionTargetSchedule,
  type LocalNutritionTargetVersion,
  type LocalReusableMeal,
  type LocalReusableMealComponent,
} from "@/lib/offline/smart-nutrition";
import {
  createFoodComponentDraft,
  foodCatalogProductToDraft,
  foodDraftToNutritionEntry,
  foodDraftToReusableMealComponent,
  mealEstimateToFoodDrafts,
  nutritionEntryToFoodDraft,
  type FoodComponentDraft,
} from "@/lib/nutrition/food-component-draft";

const mealLabels: Record<MealType, string> = {
  Breakfast: "Frühstück",
  Lunch: "Mittagessen",
  Dinner: "Abendessen",
  Snacks: "Snacks",
};
const inputClass = "h-11 w-full rounded-xl border bg-background px-3 text-sm outline-none";
type AddMode = "recent" | "meals" | "ai" | "barcode" | "search" | "manual";
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
  const [targetSchedule, setTargetSchedule] = useState<(LocalNutritionTargetSchedule & { id: string }) | null>(null);
  const [showTargetConfig, setShowTargetConfig] = useState(false);
  const [section, setSection] = useState<"diary" | "meals">("diary");

  const refresh = useCallback(async () => {
    const [loaded, used, targets, pending] = await Promise.all([
      readLocalNutritionDay(database, localDate),
      recentLocalNutritionEntries(database),
      readNutritionTargetSchedule(database),
      database.outbox.where("status").equals("pending").count(),
    ]);
    setDay(loaded);
    setRecent(used);
    setTargetSchedule(targets);
    onPendingChange(pending);
  }, [database, localDate, onPendingChange]);

  useEffect(() => {
    let current = true;
    void Promise.all([
      readLocalNutritionDay(database, localDate),
      recentLocalNutritionEntries(database),
      readNutritionTargetSchedule(database),
      database.outbox.where("status").equals("pending").count(),
    ]).then(([loaded, used, targets, pending]) => {
      if (!current) return;
      setDay(loaded);
      setRecent(used);
      setTargetSchedule(targets);
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

  async function saveEntries(entriesToAdd: LocalNutritionEntry[]) {
    const entries = normalizePositions([...(day?.entries ?? []), ...entriesToAdd]);
    await saveLocalNutritionDay(database, localDate, entries);
    setSheet(undefined);
    setMessage(`${entriesToAdd.length} geschätzte Komponente(n) hinzugefügt.`);
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
  const target = effectiveTarget(targetSchedule, localDate);
  if (section === "meals") return <div id="nutrition" className="space-y-4">
    <NutritionSectionTabs value={section} onChange={setSection} />
    <section className="rounded-[1.75rem] border bg-card p-5 sm:p-6">
      <div className="mb-4"><p className="text-xs font-semibold uppercase tracking-wider text-primary">Meal Prep</p><h1 className="text-2xl font-bold">Gerichte</h1><p className="mt-1 text-sm text-muted-foreground">Pflege wiederverwendbare Gerichte unabhängig von einem Ernährungstag.</p></div>
      <MealsMode database={database} recent={recent} online={online} library onChanged={refresh} />
    </section>
  </div>;
  return (
    <div id="nutrition" className="space-y-4">
      <NutritionSectionTabs value={section} onChange={setSection} />
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
          <div className="mt-4 space-y-3 rounded-2xl bg-background/70 p-4 backdrop-blur-sm">
            <div className="flex items-center justify-between gap-3"><div><p className="text-sm font-semibold">Tagesziele</p>{target && <p className="text-xs text-muted-foreground">{target.name} · {goalCategoryLabel(target.category)} · {formatPhaseRange(target)}</p>}</div><Button type="button" size="sm" variant="ghost" onClick={() => setShowTargetConfig(true)}><SlidersHorizontal className="size-4" /> Verwalten</Button></div>
            {target ? <div className="grid gap-3 sm:grid-cols-2">
              <NutrientProgress label="Kalorien" consumed={totals.kilocalories} target={target.kilocalories} unit="kcal" complete />
              <NutrientProgress label="Protein" consumed={totals.proteinGrams} target={target.proteinGrams} unit="g" complete={totals.proteinGrams !== null} />
              <NutrientProgress label="Kohlenhydrate" consumed={totals.carbohydrateGrams} target={target.carbohydrateGrams} unit="g" complete={totals.carbohydrateGrams !== null} />
              <NutrientProgress label="Fett" consumed={totals.fatGrams} target={target.fatGrams} unit="g" complete={totals.fatGrams !== null} />
            </div> : <p className="text-sm text-muted-foreground">Noch keine Ziele für diesen Tag. Aufnahme wird trotzdem vollständig angezeigt.</p>}
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

      {sheet && <FoodPickerSheet
        contextLabel={mealLabels[sheet.meal]}
        meal={sheet.meal}
        initial={sheet.entry ? nutritionEntryToFoodDraft(sheet.entry, sheet.entry.entryId) : undefined}
        recent={recent}
        database={database}
        localDate={localDate}
        online={online}
        includeSavedMeals={!sheet.entry}
        showMealSelector
        onClose={() => setSheet(undefined)}
        onAccept={async (drafts, targetMeal) => {
          setError(undefined);
          try {
            if (sheet.entry && drafts.length === 1) {
              await saveEntry(foodDraftToNutritionEntry(drafts[0]!, targetMeal, sheet.entry.position, sheet.entry.entryId));
            } else {
              await saveEntries(drafts.map((draft, position) => foodDraftToNutritionEntry(draft, targetMeal, position)));
            }
          }
          catch (caught) { setError(errorMessage(caught)); }
        }}
        onChanged={async () => { setSheet(undefined); await refresh(); }}
        onOpenLibrary={() => { setSheet(undefined); setSection("meals"); }}
      />}
      {showTargetConfig && <TargetConfigSheet database={database} schedule={targetSchedule} onClose={() => setShowTargetConfig(false)} onSaved={refresh} />}
    </div>
  );
}

function FoodPickerSheet({
  contextLabel,
  meal,
  initial,
  recent,
  database,
  localDate,
  online,
  includeSavedMeals = false,
  showMealSelector = false,
  onClose,
  onAccept,
  onChanged,
  onOpenLibrary,
}: {
  contextLabel: string;
  meal: MealType;
  initial?: FoodComponentDraft;
  recent: LocalNutritionEntry[];
  database?: AccountDatabase;
  localDate?: string;
  online: boolean;
  includeSavedMeals?: boolean;
  showMealSelector?: boolean;
  onClose: () => void;
  onAccept: (drafts: FoodComponentDraft[], meal: MealType) => Promise<void>;
  onChanged?: () => Promise<void>;
  onOpenLibrary?: () => void;
}) {
  const [mode, setMode] = useState<AddMode>(initial ? "manual" : "recent");
  const [seed, setSeed] = useState<FoodComponentDraft | undefined>(initial);
  const [targetMeal, setTargetMeal] = useState(meal);
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
    setSeed(foodCatalogProductToDraft(product));
    setMode("manual");
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/35 p-0 backdrop-blur-[2px] sm:items-center sm:p-6" role="dialog" aria-modal="true" aria-labelledby="nutrition-sheet-title">
      <section ref={sheetRef} tabIndex={-1} className="max-h-[92dvh] w-full max-w-xl overflow-y-auto rounded-t-[2rem] border bg-card p-5 pb-[max(1.25rem,env(safe-area-inset-bottom))] shadow-2xl outline-none sm:rounded-[2rem] sm:p-6">
        <div className="flex items-center justify-between"><div><p className="text-xs font-semibold uppercase tracking-wider text-primary">{contextLabel}</p><h2 id="nutrition-sheet-title" className="text-xl font-bold">{initial ? (showMealSelector ? "Eintrag bearbeiten" : "Lebensmittel bearbeiten") : "Lebensmittel hinzufügen"}</h2></div><Button type="button" size="icon" variant="ghost" aria-label="Schließen" onClick={() => { stopScan(); onClose(); }}><X /></Button></div>
        {!initial && <div className={`mt-4 grid grid-cols-3 gap-1 rounded-xl bg-muted p-1 ${includeSavedMeals ? "sm:grid-cols-6" : "sm:grid-cols-5"}`} role="tablist" aria-label="Erfassungsart">
          {(["recent", ...(includeSavedMeals ? ["meals" as const] : []), "ai", "barcode", "search", "manual"] as const).map((item) => <button key={item} type="button" role="tab" aria-selected={mode === item} className={`min-h-10 rounded-lg px-1 text-xs font-semibold ${mode === item ? "bg-card text-foreground shadow-sm" : "text-muted-foreground"}`} onClick={() => { stopScan(); setMode(item); setError(undefined); }}>{modeLabel(item)}</button>)}
        </div>}
        {error && <p role="alert" className="mt-4 rounded-xl bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}

        {mode === "recent" && <div className="mt-4 space-y-2">{recent.length ? recent.map((entry) => <button type="button" key={`${entry.entryId}-${entry.productName}`} className="flex w-full items-center justify-between rounded-xl border p-3 text-left hover:bg-muted/50" onClick={() => { setSeed(nutritionEntryToFoodDraft(entry)); setMode("manual"); }}><span><span className="block font-semibold">{entry.productName}</span><span className="text-xs text-muted-foreground">{format(entry.amountGrams)} g · {format(entry.totals.kilocalories, 0)} kcal</span></span><Apple className="size-5 text-primary" /></button>) : <p className="rounded-xl border border-dashed p-5 text-center text-sm text-muted-foreground">Noch keine zuletzt verwendeten Lebensmittel auf diesem Gerät.</p>}</div>}

        {mode === "meals" && includeSavedMeals && database && localDate && onChanged && <MealsMode database={database} recent={recent} online={online} localDate={localDate} targetMeal={targetMeal} onChanged={onChanged} onOpenLibrary={onOpenLibrary} />}

        {mode === "ai" && <AiEstimateMode online={online} onSave={async (drafts) => onAccept(drafts, targetMeal)} />}

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

        {mode === "manual" && <FoodDraftForm key={seed?.draftId ?? "new"} destinationMeal={targetMeal} showMealSelector={showMealSelector} seed={seed} onSave={async (draft, destination) => onAccept([draft], destination)} onMealChange={setTargetMeal} />}

        {(mode === "search" || mode === "barcode" || seed?.source) && <p className="mt-5 text-xs leading-5 text-muted-foreground">Quelle: Open Food Facts (ODbL). Community-Daten können unvollständig oder fehlerhaft sein; gleiche die Werte bei Bedarf mit der Verpackung ab. Es werden keine Produktbilder verwendet.</p>}
      </section>
    </div>
  );
}

function MealsMode({ database, recent, online, localDate = today(), targetMeal = "Lunch", onChanged, library = false, onOpenLibrary }: {
  database: AccountDatabase;
  recent: LocalNutritionEntry[];
  online: boolean;
  localDate?: string;
  targetMeal?: MealType;
  onChanged: () => Promise<void>;
  library?: boolean;
  onOpenLibrary?: () => void;
}) {
  const [saved, setSaved] = useState<Array<LocalReusableMeal & { id: string }>>([]);
  const [editing, setEditing] = useState<(LocalReusableMeal & { id: string }) | null>(null);
  const [componentPicker, setComponentPicker] = useState<number | "new" | null>(null);
  const [preview, setPreview] = useState<(LocalReusableMeal & { id: string }) | null>(null);
  const [portionFactor, setPortionFactor] = useState(1);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [includeArchived, setIncludeArchived] = useState(false);
  const reload = useCallback(() => readReusableMeals(database, library && includeArchived).then(setSaved), [database, includeArchived, library]);
  useEffect(() => { void reload(); }, [reload]);

  async function saveEdit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!editing) return;
    const form = new FormData(event.currentTarget);
    setBusy(true); setError(undefined);
    try {
      await saveReusableMeal(database, {
        id: editing.id,
        name: String(form.get("name")),
        description: String(form.get("description") || "") || null,
        standardPortion: Number(form.get("standardPortion")),
        components: editing.components.map((component, position) => ({ ...component, position })),
      });
      setEditing(null);
      await reload();
    } catch (caught) { setError(errorMessage(caught)); }
    finally { setBusy(false); }
  }

  function updateEditingComponent(index: number, update: (value: LocalReusableMealComponent) => LocalReusableMealComponent) {
    if (!editing) return;
    setEditing({ ...editing, components: editing.components.map((component, itemIndex) => itemIndex === index ? update(component) : component) });
  }

  function moveEditingComponent(index: number, direction: -1 | 1) {
    if (!editing) return;
    const destination = index + direction;
    if (destination < 0 || destination >= editing.components.length) return;
    const components = [...editing.components];
    [components[index], components[destination]] = [components[destination], components[index]];
    setEditing({ ...editing, components });
  }

  if (editing) return <><form className="mt-4 space-y-4" onSubmit={saveEdit}>
    {error && <p role="alert" className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
    <div className="flex items-center justify-between"><div><p className="text-xs font-semibold uppercase tracking-wider text-primary">Gericht bearbeiten</p><h3 className="text-lg font-bold">Komponenten und Portion</h3></div><Button type="button" variant="ghost" size="sm" onClick={() => setEditing(null)}>Abbrechen</Button></div>
    <Field label="Name"><input className={inputClass} name="name" defaultValue={editing.name} maxLength={120} required /></Field>
    <Field label="Beschreibung (optional)"><input className={inputClass} name="description" defaultValue={editing.description ?? ""} maxLength={500} /></Field>
    <Field label="Standardportion (Faktor)"><input className={inputClass} name="standardPortion" type="number" min="0.01" max="100" step="0.01" defaultValue={editing.standardPortion} required /></Field>
    <div className="space-y-2">{editing.components.map((component, index) => <div key={component.componentId} className="rounded-2xl border p-3">
      <div className="flex items-center gap-2"><button type="button" className="min-w-0 flex-1 truncate text-left font-semibold" onClick={() => setComponentPicker(index)}>{component.name}</button><Button type="button" size="icon" variant="ghost" aria-label={`${component.name} nach oben`} disabled={index === 0} onClick={() => moveEditingComponent(index, -1)}><ChevronUp /></Button><Button type="button" size="icon" variant="ghost" aria-label={`${component.name} nach unten`} disabled={index === editing.components.length - 1} onClick={() => moveEditingComponent(index, 1)}><ChevronDown /></Button></div>
      <div className="mt-2 grid grid-cols-[1fr_auto_auto] items-end gap-2"><Field label="Menge (g)"><input className={inputClass} type="number" min="0.01" max="100000" step="0.01" value={component.amountGrams} onChange={(event) => updateEditingComponent(index, (value) => resizeMealComponent(value, Number(event.target.value)))} /></Field><Button type="button" variant="outline" onClick={() => setComponentPicker(index)}>Bearbeiten</Button><Button type="button" variant="ghost" aria-label={`${component.name} entfernen`} onClick={() => setEditing({ ...editing, components: editing.components.filter((_, itemIndex) => itemIndex !== index) })}><Trash2 /></Button></div>
      <p className="mt-2 text-xs text-muted-foreground">{format(component.totals.kilocalories, 0)} kcal · P {format(component.totals.proteinGrams)} · KH {format(component.totals.carbohydrateGrams)} · F {format(component.totals.fatGrams)}</p>
    </div>)}</div>
    <Button type="button" variant="outline" className="w-full" onClick={() => setComponentPicker("new")}><Plus /> Lebensmittel hinzufügen</Button>
    <p className="rounded-xl bg-muted p-3 text-sm">Summe: <strong>{format(mealKilocalories(editing.components), 0)} kcal</strong></p>
    <Button type="submit" className="w-full" disabled={busy || editing.components.length === 0}><ChefHat /> Gericht speichern</Button>
  </form>
  {componentPicker !== null && <FoodPickerSheet
    contextLabel="Gerichtskomponente"
    meal="Lunch"
    initial={typeof componentPicker === "number" ? componentToFoodDraft(editing.components[componentPicker]!) : undefined}
    recent={recent}
    online={online}
    onClose={() => setComponentPicker(null)}
    onAccept={async (drafts) => {
      const currentIndex = componentPicker;
      const retained = typeof currentIndex === "number" ? editing.components.filter((_, index) => index !== currentIndex) : editing.components;
      const insertionIndex = typeof currentIndex === "number" ? currentIndex : retained.length;
      const additions = drafts.map((draft, offset) => foodDraftToReusableMealComponent(
        draft,
        insertionIndex + offset,
        typeof currentIndex === "number" && offset === 0 ? editing.components[currentIndex]!.componentId : undefined,
      ));
      const components = [...retained.slice(0, insertionIndex), ...additions, ...retained.slice(insertionIndex)]
        .map((component, position) => ({ ...component, position }));
      setEditing({ ...editing, components });
      setComponentPicker(null);
    }}
  />}
  </>;

  if (preview) {
    const scaled = preview.components.map((component) => ({ ...component, amountGrams: component.amountGrams * portionFactor, totals: scaleTotals(component.totals, portionFactor) }));
    return <div className="mt-4 space-y-4">
      {error && <p role="alert" className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
      <div className="flex items-center justify-between"><div><p className="text-xs font-semibold uppercase tracking-wider text-primary">Vorschau</p><h3 className="text-lg font-bold">{preview.name}</h3></div><Button type="button" variant="ghost" size="sm" onClick={() => setPreview(null)}>Zurück</Button></div>
      <Field label="Portionsfaktor"><input className={inputClass} aria-label="Portionsfaktor" type="number" min="0.01" max="100" step="0.01" value={portionFactor} onChange={(event) => setPortionFactor(Number(event.target.value))} /></Field>
      <div className="space-y-2" aria-label="Resultierende Komponenten">{scaled.map((component) => <div key={component.componentId} className="flex items-center justify-between gap-3 rounded-xl border p-3 text-sm"><span><span className="block font-semibold">{component.name}</span><span className="text-xs text-muted-foreground">{format(component.amountGrams)} g</span></span><span className="tabular-nums">{format(component.totals.kilocalories, 0)} kcal</span></div>)}</div>
      <p className="rounded-xl bg-muted p-3 text-sm">Gesamt: <strong>{format(mealKilocalories(scaled), 0)} kcal</strong> · wird als {scaled.length} unabhängige {scaled.length === 1 ? "Komponente" : "Komponenten"} zu {mealLabels[targetMeal]} kopiert.</p>
      <Button type="button" className="w-full" disabled={busy || !Number.isFinite(portionFactor) || portionFactor < 0.01 || portionFactor > 100} onClick={async () => { setBusy(true); setError(undefined); try { await addReusableMealToDay(database, preview, localDate, targetMeal, portionFactor); await onChanged(); setPreview(null); } catch (caught) { setError(errorMessage(caught)); } finally { setBusy(false); } }}><ChefHat /> Komponenten hinzufügen</Button>
    </div>;
  }

  return <div className={`${library ? "" : "mt-4"} space-y-4`}>
    {error && <p role="alert" className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
    {library && <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={includeArchived} onChange={(event) => setIncludeArchived(event.target.checked)} /> Archivierte Gerichte anzeigen</label>}
    <div className="space-y-2">{saved.length ? saved.map((item) => <div key={item.id} className="rounded-2xl border p-4">
      <div className="flex items-start justify-between gap-3"><div><p className="font-semibold">{item.name}</p><p className="text-xs text-muted-foreground">{item.components.length} Komponenten · {format(item.components.reduce((sum, part) => sum + part.totals.kilocalories, 0), 0)} kcal{item.status === "Archived" ? " · Archiviert" : ""}</p></div><ChefHat className="size-5 text-primary" /></div>
      <div className="mt-3 flex flex-wrap gap-2">
        {!library && <Button type="button" size="sm" disabled={busy} onClick={() => { setPortionFactor(item.standardPortion); setPreview(structuredClone(item)); }}>Auswählen</Button>}
        {library && item.status === "Active" && <Button type="button" size="sm" variant="outline" disabled={busy} onClick={() => setEditing(structuredClone(item))}>Bearbeiten</Button>}
        {library && item.status === "Active" && <Button type="button" size="sm" variant="outline" disabled={busy} onClick={() => setEditing({ ...structuredClone(item), id: crypto.randomUUID(), name: `${item.name} Kopie`, components: item.components.map((component) => ({ ...structuredClone(component), componentId: crypto.randomUUID() })) })}><Copy className="size-4" /> Duplizieren</Button>}
        {library && item.status === "Active" && <Button type="button" size="sm" variant="ghost" disabled={busy} onClick={async () => { if (!window.confirm(`„${item.name}“ archivieren?`)) return; setBusy(true); try { await archiveReusableMeal(database, item.id); await reload(); } catch (caught) { setError(errorMessage(caught)); } finally { setBusy(false); } }}>Archivieren</Button>}
      </div>
    </div>) : <p className="rounded-xl border border-dashed p-5 text-center text-sm text-muted-foreground">Noch keine gespeicherten Gerichte.</p>}</div>
    {!library && <Button type="button" variant="outline" className="w-full" onClick={onOpenLibrary}><ChefHat /> Gerichte separat verwalten</Button>}
    {library && <Button type="button" className="w-full" onClick={() => {
      const now = new Date().toISOString();
      setEditing({ id: crypto.randomUUID(), name: "", description: null, standardPortion: 1, status: "Active", components: [], createdAtUtc: now, updatedAtUtc: now });
    }}><Plus /> Neues Gericht</Button>}
  </div>;
}

function AiEstimateMode({ online, onSave }: {
  online: boolean;
  onSave: (drafts: FoodComponentDraft[]) => Promise<void>;
}) {
  const [draft, setDraft] = useState<Awaited<ReturnType<typeof estimateMeal>>>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const abortRef = useRef<AbortController | null>(null);

  if (draft) return <div className="mt-4 space-y-3">
    <div className="rounded-xl bg-amber-500/10 p-3 text-sm text-amber-900 dark:text-amber-200">AI-Werte sind Schätzungen. Prüfe Menge und Nährwerte vor dem Speichern.</div>
    {draft.components.map((component, index) => <div key={`${component.name}-${index}`} className="grid gap-2 rounded-2xl border p-4 sm:grid-cols-2">
      <Field label="Komponente"><input className={inputClass} value={component.name} onChange={(event) => setDraft(updateEstimate(draft, index, "name", event.target.value))} /></Field>
      <Field label="Menge (g)"><input className={inputClass} type="number" min="0.01" step="0.01" value={Number(component.amountGrams)} onChange={(event) => setDraft(updateEstimate(draft, index, "amountGrams", Number(event.target.value)))} /></Field>
      <Field label="Kalorien"><input className={inputClass} type="number" min="0.01" step="0.01" value={Number(component.kilocalories)} onChange={(event) => setDraft(updateEstimate(draft, index, "kilocalories", Number(event.target.value)))} /></Field>
      <Field label="Protein (g)"><input className={inputClass} type="number" min="0" step="0.01" value={component.proteinGrams === null ? "" : Number(component.proteinGrams)} onChange={(event) => setDraft(updateEstimate(draft, index, "proteinGrams", event.target.value === "" ? null : Number(event.target.value)))} /></Field>
      <Field label="Kohlenhydrate (g)"><input className={inputClass} type="number" min="0" step="0.01" value={component.carbohydrateGrams === null ? "" : Number(component.carbohydrateGrams)} onChange={(event) => setDraft(updateEstimate(draft, index, "carbohydrateGrams", event.target.value === "" ? null : Number(event.target.value)))} /></Field>
      <Field label="Fett (g)"><input className={inputClass} type="number" min="0" step="0.01" value={component.fatGrams === null ? "" : Number(component.fatGrams)} onChange={(event) => setDraft(updateEstimate(draft, index, "fatGrams", event.target.value === "" ? null : Number(event.target.value)))} /></Field>
      <p className="self-end pb-3 text-xs text-muted-foreground">Sicherheit: {component.confidence}{component.dataGaps.length ? ` · ${component.dataGaps.join(", ")}` : ""}</p>
      <Button type="button" variant="ghost" className="sm:col-span-2" onClick={() => setDraft({ ...draft, components: draft.components.filter((_, itemIndex) => itemIndex !== index) })}><Trash2 className="size-4" /> Entfernen</Button>
    </div>)}
    <Button type="button" variant="outline" className="w-full" disabled={draft.components.length >= 20} onClick={() => setDraft({ ...draft, components: [...draft.components, { name: "Neue Komponente", amountGrams: 100, kilocalories: 1, proteinGrams: null, carbohydrateGrams: null, fatGrams: null, confidence: "Low", dataGaps: ["Manuell ergänzt"] }] })}><Plus /> Komponente ergänzen</Button>
    <Button type="button" className="w-full" disabled={busy || draft.components.length === 0} onClick={async () => {
      setBusy(true); setError(undefined);
      try {
        await onSave(mealEstimateToFoodDrafts(draft));
      } catch (caught) { setError(errorMessage(caught)); }
      finally { setBusy(false); }
    }}><Sparkles /> Geprüfte Komponenten übernehmen</Button>
    <Button type="button" variant="ghost" className="w-full" onClick={() => setDraft(undefined)}>Entwurf verwerfen</Button>
    {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
  </div>;

  return <form className="mt-4 space-y-4" onSubmit={async (event) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const image = form.get("image") instanceof File && (form.get("image") as File).size ? form.get("image") as File : null;
    const consent = form.get("imageConsent") === "on";
    if (!online) { setError("AI-Schätzung benötigt eine Internetverbindung. Manuelle Eingabe und Gerichte bleiben verfügbar."); return; }
    setBusy(true); setError(undefined);
    abortRef.current = new AbortController();
    try { setDraft(await estimateMeal(String(form.get("text") ?? ""), image, consent, abortRef.current.signal)); }
    catch (caught) { if ((caught as Error).name !== "AbortError") setError(aiError(caught)); }
    finally { setBusy(false); abortRef.current = null; }
  }}>
    <div className="rounded-xl bg-primary/8 p-4 text-sm"><p className="font-semibold">Datenschutzhinweis</p><p className="mt-1 text-muted-foreground">Freitext und ein ausgewähltes Foto werden zur einmaligen, ungenauen Schätzung an OpenAI übertragen. Gainer speichert weder Foto noch AI-Entwurf. Der Request nutzt <code>store=false</code>; OpenAI kann API-Inhalte standardmäßig dennoch bis zu 30 Tage zur Missbrauchserkennung aufbewahren, sofern für das verwendete Projekt keine strengere Aufbewahrung aktiviert ist.</p></div>
    <Field label="Mahlzeit beschreiben"><textarea className="min-h-28 w-full rounded-xl border bg-background p-3 text-sm outline-none" name="text" maxLength={2000} placeholder="z. B. 200 g Reis mit Hähnchen und Gemüse" /></Field>
    <Field label="Foto (optional)"><input className={inputClass} name="image" type="file" accept="image/jpeg,image/png,image/webp" capture="environment" /></Field>
    <label className="flex items-start gap-3 text-sm"><input className="mt-1" name="imageConsent" type="checkbox" /><span>Ich stimme der einmaligen Übertragung des ausgewählten Fotos an OpenAI zu.</span></label>
    {error && <p role="alert" className="rounded-xl bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
    <Button type="submit" className="w-full" disabled={busy || !online}><Sparkles /> {busy ? "Schätzung läuft …" : "Mit AI schätzen"}</Button>
    {busy && <Button type="button" variant="ghost" className="w-full" onClick={() => abortRef.current?.abort()}>Abbrechen</Button>}
  </form>;
}

function TargetConfigSheet({ database, schedule, onClose, onSaved }: {
  database: AccountDatabase;
  schedule: (LocalNutritionTargetSchedule & { id: string }) | null;
  onClose: () => void;
  onSaved: () => Promise<void>;
}) {
  const [editing, setEditing] = useState<LocalNutritionTargetVersion | null>(null);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string>();
  return <div className="fixed inset-0 z-[60] flex items-end justify-center bg-black/35 backdrop-blur-[2px] sm:items-center sm:p-6" role="dialog" aria-modal="true" aria-labelledby="target-title">
    <section className="max-h-[92dvh] w-full max-w-lg overflow-y-auto rounded-t-[2rem] border bg-card p-5 pb-[max(1.25rem,env(safe-area-inset-bottom))] shadow-2xl sm:rounded-[2rem]">
      <div className="flex items-center justify-between"><h2 id="target-title" className="text-xl font-bold">Zielphasen</h2><Button type="button" size="icon" variant="ghost" aria-label="Schließen" onClick={onClose}><X /></Button></div>
      <p className="mt-2 text-sm text-muted-foreground">Trage deine eigenen Zielwerte ein. Die App und der Coach berechnen oder empfehlen keine Kalorien- oder Makroziele.</p>
      {error && <p role="alert" className="mt-3 rounded-xl bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
      {!creating && !editing && <>
        <div className="mt-4 space-y-2">{schedule?.versions.length ? schedule.versions.map((phase) => <div key={phase.targetVersionId} className="rounded-2xl border p-4">
          <div className="flex items-start justify-between gap-3"><div><p className="font-semibold">{phase.name}</p><p className="text-xs text-muted-foreground">{goalCategoryLabel(phase.category)} · {formatPhaseRange(phase)}</p></div><span className="text-sm font-semibold tabular-nums">{format(phase.kilocalories, 0)} kcal</span></div>
          <p className="mt-2 text-xs text-muted-foreground">P {format(phase.proteinGrams)} g · KH {format(phase.carbohydrateGrams)} g · F {format(phase.fatGrams)} g{phase.inputMode === "Percent" ? ` · ${format(phase.proteinPercent)} / ${format(phase.carbohydratePercent)} / ${format(phase.fatPercent)} %` : ""}</p>
          {phase.effectiveFrom > today() && <div className="mt-3 flex gap-2"><Button type="button" size="sm" variant="outline" onClick={() => setEditing(structuredClone(phase))}>Bearbeiten</Button><Button type="button" size="sm" variant="ghost" onClick={async () => { if (!window.confirm(`„${phase.name}“ löschen?`)) return; try { await removeNutritionTargetVersion(database, phase.targetVersionId); await onSaved(); } catch (caught) { setError(errorMessage(caught)); } }}>Löschen</Button></div>}
        </div>) : <p className="rounded-xl border border-dashed p-5 text-center text-sm text-muted-foreground">Noch keine Zielphase angelegt.</p>}</div>
        <Button type="button" className="mt-4 w-full" onClick={() => setCreating(true)}><Plus /> Neue Zielphase</Button>
      </>}
      {(creating || editing) && <TargetPhaseForm key={editing?.targetVersionId ?? "new"} database={database} schedule={schedule} initial={editing} onCancel={() => { setCreating(false); setEditing(null); setError(undefined); }} onSaved={async () => { setCreating(false); setEditing(null); await onSaved(); }} />}
    </section>
  </div>;
}

function TargetPhaseForm({ database, schedule, initial, onCancel, onSaved }: {
  database: AccountDatabase;
  schedule: LocalNutritionTargetSchedule | null;
  initial: LocalNutritionTargetVersion | null;
  onCancel: () => void;
  onSaved: () => Promise<void>;
}) {
  const [mode, setMode] = useState<"Grams" | "Percent">(initial?.inputMode ?? "Grams");
  const [kilocalories, setKilocalories] = useState(initial?.kilocalories ?? 0);
  const [protein, setProtein] = useState(initial?.proteinGrams ?? 0);
  const [carbohydrates, setCarbohydrates] = useState(initial?.carbohydrateGrams ?? 0);
  const [fat, setFat] = useState(initial?.fatGrams ?? 0);
  const [proteinPercent, setProteinPercent] = useState(initial?.proteinPercent ?? 0);
  const [carbohydratePercent, setCarbohydratePercent] = useState(initial?.carbohydratePercent ?? 0);
  const [fatPercent, setFatPercent] = useState(initial?.fatPercent ?? 0);
  const [warningAccepted, setWarningAccepted] = useState(false);
  const [error, setError] = useState<string>();
  const percentageTotal = proteinPercent + carbohydratePercent + fatPercent;
  let derived: ReturnType<typeof deriveMacroTargets> | null = null;
  if (mode === "Percent" && percentageTotal === 100 && kilocalories > 0) {
    try { derived = deriveMacroTargets(kilocalories, proteinPercent, carbohydratePercent, fatPercent); } catch { derived = null; }
  }
  return <form className="mt-4 grid gap-3 sm:grid-cols-2" onSubmit={async (event) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const effectiveFrom = String(form.get("effectiveFrom"));
    const effectiveUntil = String(form.get("effectiveUntil") || "") || null;
    const macros = mode === "Percent" ? deriveMacroTargets(kilocalories, proteinPercent, carbohydratePercent, fatPercent) : { proteinGrams: protein, carbohydrateGrams: carbohydrates, fatGrams: fat };
    const macroEnergy = macros.proteinGrams * 4 + macros.carbohydrateGrams * 4 + macros.fatGrams * 9;
    if (mode === "Grams" && !warningAccepted && Math.abs(macroEnergy - kilocalories) / kilocalories > 0.1) { setWarningAccepted(true); return; }
    const phase: LocalNutritionTargetVersion = {
      targetVersionId: initial?.targetVersionId ?? crypto.randomUUID(),
      name: String(form.get("name")), category: String(form.get("category")) as LocalNutritionTargetVersion["category"],
      effectiveFrom, effectiveUntil, inputMode: mode, kilocalories, ...macros,
      proteinPercent: mode === "Percent" ? proteinPercent : null,
      carbohydratePercent: mode === "Percent" ? carbohydratePercent : null,
      fatPercent: mode === "Percent" ? fatPercent : null,
      origin: "Manual", algorithmVersion: null, reason: null,
    };
    const openPredecessor = schedule?.versions.find((item) => item.targetVersionId !== phase.targetVersionId && item.effectiveFrom < effectiveFrom && item.effectiveUntil === null);
    const closeOpenPhase = Boolean(openPredecessor);
    if (openPredecessor && !window.confirm(`Die offene Phase „${openPredecessor.name}“ wird am ${formatLocalDate(shiftDate(effectiveFrom, -1))} beendet. Fortfahren?`)) return;
    try { setError(undefined); await saveNutritionTargetVersion(database, phase, { closeOpenPhase }); await onSaved(); }
    catch (caught) { setError(errorMessage(caught)); }
  }}>
    <div className="flex items-center justify-between sm:col-span-2"><h3 className="font-bold">{initial ? "Zielphase bearbeiten" : "Neue Zielphase"}</h3><Button type="button" size="sm" variant="ghost" onClick={onCancel}>Abbrechen</Button></div>
    <Field label="Name"><input className={inputClass} name="name" defaultValue={initial?.name ?? ""} maxLength={80} placeholder="z. B. Sommer-Cut" required /></Field>
    <Field label="Kategorie"><select className={inputClass} name="category" defaultValue={initial?.category ?? "Custom"}><option value="Cut">Cut</option><option value="Maintenance">Maintenance</option><option value="Bulk">Bulk</option><option value="Custom">Benutzerdefiniert</option></select></Field>
    <Field label="Start"><input className={inputClass} type="date" name="effectiveFrom" min={today()} defaultValue={initial?.effectiveFrom ?? shiftDate(today(), 1)} required /></Field>
    <Field label="Ende (optional, inklusive)"><input className={inputClass} type="date" name="effectiveUntil" min={initial?.effectiveFrom ?? today()} defaultValue={initial?.effectiveUntil ?? ""} /></Field>
    <Field label="Kalorien"><input className={inputClass} type="number" min="1" max="20000" value={kilocalories || ""} onChange={(event) => setKilocalories(Number(event.target.value))} required /></Field>
    <Field label="Eingabe"><select className={inputClass} value={mode} onChange={(event) => { setMode(event.target.value as "Grams" | "Percent"); setWarningAccepted(false); }}><option value="Grams">Gramm</option><option value="Percent">Prozent</option></select></Field>
    {mode === "Grams" ? <><MacroInput label="Protein (g)" value={protein} onChange={setProtein} /><MacroInput label="Kohlenhydrate (g)" value={carbohydrates} onChange={setCarbohydrates} /><MacroInput label="Fett (g)" value={fat} onChange={setFat} /></> : <><MacroInput label="Protein (%)" value={proteinPercent} onChange={setProteinPercent} max={100} /><MacroInput label="Kohlenhydrate (%)" value={carbohydratePercent} onChange={setCarbohydratePercent} max={100} /><MacroInput label="Fett (%)" value={fatPercent} onChange={setFatPercent} max={100} /><p className={`rounded-xl p-3 text-sm sm:col-span-2 ${percentageTotal === 100 ? "bg-emerald-500/10" : "bg-amber-500/10"}`}>Summe: <strong>{format(percentageTotal)} %</strong> · erforderlich: exakt 100 %{derived && ` · ${format(derived.proteinGrams)} g Protein, ${format(derived.carbohydrateGrams)} g Kohlenhydrate, ${format(derived.fatGrams)} g Fett`}</p></>}
    {warningAccepted && <p className="rounded-xl bg-amber-500/10 p-3 text-sm text-amber-900 dark:text-amber-200 sm:col-span-2">Die Grammwerte weichen nach 4/4/9 um mehr als 10 % vom Kalorienziel ab. Erneut speichern, um bewusst zu bestätigen.</p>}
    {error && <p role="alert" className="text-sm text-destructive sm:col-span-2">{error}</p>}
    <Button className="sm:col-span-2" type="submit">Zielphase speichern</Button>
  </form>;
}

function MacroInput({ label, value, onChange, max = 2000 }: { label: string; value: number; onChange: (value: number) => void; max?: number }) {
  return <Field label={label}><input className={inputClass} type="number" min="0.01" max={max} step="0.01" value={value || ""} onChange={(event) => onChange(Number(event.target.value))} required /></Field>;
}

function NutrientProgress({ label, consumed, target, unit, complete }: { label: string; consumed: number | null; target: number; unit: string; complete: boolean }) {
  const value = consumed ?? 0;
  const difference = target - value;
  const ratio = target > 0 ? value / target : 0;
  const description = complete ? `${format(value)} von ${format(target)} ${unit}; ${difference >= 0 ? `${format(difference)} ${unit} verbleibend` : `${format(Math.abs(difference))} ${unit} überschritten`}` : `${format(value)} ${unit} aufgenommen; unvollständige Makrodaten`;
  return <div aria-label={`${label}: ${description}`}>
    <div className="flex justify-between gap-2 text-xs"><span className="font-medium">{label}</span><span className="tabular-nums text-muted-foreground">{description}</span></div>
    <div className="mt-1 h-2 overflow-hidden rounded-full bg-muted"><div className={`h-full rounded-full ${ratio > 1 ? "bg-amber-500" : "bg-primary"}`} style={{ width: `${Math.min(100, Math.max(0, ratio * 100))}%` }} /></div>
  </div>;
}

function updateEstimate<T extends Awaited<ReturnType<typeof estimateMeal>>>(draft: T, index: number, field: keyof T["components"][number], value: unknown): T {
  return { ...draft, components: draft.components.map((item, itemIndex) => itemIndex === index ? { ...item, [field]: value } : item) };
}

function FoodDraftForm({ destinationMeal, showMealSelector, seed, onSave, onMealChange }: {
  destinationMeal: MealType;
  showMealSelector: boolean;
  seed?: FoodComponentDraft;
  onSave: (draft: FoodComponentDraft, meal: MealType) => Promise<void>;
  onMealChange: (meal: MealType) => void;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  return <form className="mt-4 grid gap-3 sm:grid-cols-2" onSubmit={async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); setBusy(true); setError(undefined);
    const form = new FormData(event.currentTarget);
    try {
      const selectedMeal = showMealSelector ? String(form.get("meal")) as MealType : destinationMeal;
      await onSave(createFoodComponentDraft({
        draftId: seed?.draftId,
        name: String(form.get("productName")),
        brand: nullableText(form.get("brand")),
        amountGrams: Number(form.get("amountGrams")),
        per100Grams: {
          kilocalories: Number(form.get("kilocalories")),
          proteinGrams: nullableNumber(form.get("protein")),
          carbohydrateGrams: nullableNumber(form.get("carbohydrates")),
          fatGrams: nullableNumber(form.get("fat")),
        },
        source: seed?.source ?? null,
      }), selectedMeal);
    } catch (caught) { setError(errorMessage(caught)); }
    finally { setBusy(false); }
  }}>
    <Field label="Lebensmittel"><input className={inputClass} name="productName" defaultValue={seed?.name} maxLength={200} required /></Field>
    <Field label="Marke (optional)"><input className={inputClass} name="brand" defaultValue={seed?.brand ?? ""} maxLength={160} /></Field>
    {showMealSelector && <Field label="Mahlzeit"><select className={inputClass} name="meal" value={destinationMeal} onChange={(event) => onMealChange(event.target.value as MealType)}>{meals.map((item) => <option key={item} value={item}>{mealLabels[item]}</option>)}</select></Field>}
    <Field label="Menge (g)"><input className={inputClass} name="amountGrams" type="number" min="0.01" step="0.01" defaultValue={seed?.amountGrams ?? 100} required /></Field>
    <Field label="kcal pro 100 g"><input className={inputClass} name="kilocalories" type="number" min="0.01" step="0.01" defaultValue={seed?.per100Grams.kilocalories} required /></Field>
    <Field label="Protein pro 100 g"><input className={inputClass} name="protein" type="number" min="0" step="0.01" defaultValue={seed?.per100Grams.proteinGrams ?? ""} /></Field>
    <Field label="Kohlenhydrate pro 100 g"><input className={inputClass} name="carbohydrates" type="number" min="0" step="0.01" defaultValue={seed?.per100Grams.carbohydrateGrams ?? ""} /></Field>
    <Field label="Fett pro 100 g"><input className={inputClass} name="fat" type="number" min="0" step="0.01" defaultValue={seed?.per100Grams.fatGrams ?? ""} /></Field>
    {error && <p role="alert" className="text-sm text-destructive sm:col-span-2">{error}</p>}
    <Button type="submit" disabled={busy} className="sm:col-span-2"><Utensils />{busy ? (showMealSelector ? "Speichert …" : "Übernimmt …") : (showMealSelector ? "Eintrag speichern" : "Lebensmittel übernehmen")}</Button>
  </form>;
}

function LookupForm({ busy, onSubmit }: { busy: boolean; onSubmit: (barcode: string) => void }) {
  return <form className="flex gap-2" onSubmit={(event) => { event.preventDefault(); onSubmit(String(new FormData(event.currentTarget).get("barcode") ?? "")); }}><input className={inputClass} name="barcode" aria-label="Barcode manuell eingeben" inputMode="numeric" pattern="[0-9]{4,32}" placeholder="Barcode eintippen" required /><Button type="submit" disabled={busy}>Nachschlagen</Button></form>;
}

function NutritionSectionTabs({ value, onChange }: { value: "diary" | "meals"; onChange: (value: "diary" | "meals") => void }) {
  return <div className="grid grid-cols-2 rounded-2xl bg-muted p-1" role="tablist" aria-label="Ernährungsbereich">
    <button type="button" role="tab" aria-selected={value === "diary"} className={`min-h-11 rounded-xl text-sm font-semibold ${value === "diary" ? "bg-card shadow-sm" : "text-muted-foreground"}`} onClick={() => onChange("diary")}>Tagebuch</button>
    <button type="button" role="tab" aria-selected={value === "meals"} className={`min-h-11 rounded-xl text-sm font-semibold ${value === "meals" ? "bg-card shadow-sm" : "text-muted-foreground"}`} onClick={() => onChange("meals")}>Gerichte</button>
  </div>;
}

function Field({ label, children }: { label: string; children: React.ReactNode }) { return <label className="space-y-1.5 text-sm font-medium"><span>{label}</span>{children}</label>; }
function Metric({ label, value, suffix, prominent = false }: { label: string; value: string; suffix?: string; prominent?: boolean }) { return <div><p className={`${prominent ? "text-xl" : "text-base"} font-bold tabular-nums`}>{value}{suffix && <span className="ml-0.5 text-xs font-medium text-muted-foreground">{suffix}</span>}</p><p className="text-[0.65rem] text-muted-foreground">{label}</p></div>; }
function modeLabel(mode: AddMode) { return ({ recent: "Zuletzt", meals: "Gerichte", ai: "AI", barcode: "Barcode", search: "Suchen", manual: "Manuell" })[mode]; }
function normalizePositions(entries: LocalNutritionEntry[]) { return meals.flatMap((meal) => entries.filter((entry) => entry.meal === meal).sort((a, b) => a.position - b.position).map((entry, position) => ({ ...entry, position }))); }

function scaleTotals(totals: LocalNutritionTotals, factor: number): LocalNutritionTotals {
  const scale = (value: number | null) => value === null ? null : value * factor;
  return {
    kilocalories: scale(totals.kilocalories) ?? 0,
    proteinGrams: scale(totals.proteinGrams),
    carbohydrateGrams: scale(totals.carbohydrateGrams),
    fatGrams: scale(totals.fatGrams),
  };
}

function resizeMealComponent(component: LocalReusableMealComponent, amountGrams: number): LocalReusableMealComponent {
  return { ...component, amountGrams, totals: scaleTotals(component.per100Grams, amountGrams / 100) };
}

function mealKilocalories(components: LocalReusableMealComponent[]) {
  return components.reduce((sum, component) => sum + component.totals.kilocalories, 0);
}
function componentToFoodDraft(component: LocalReusableMealComponent): FoodComponentDraft {
  return createFoodComponentDraft({
    draftId: component.componentId,
    name: component.name,
    brand: component.brand,
    amountGrams: component.amountGrams,
    per100Grams: structuredClone(component.per100Grams),
    source: component.source ? structuredClone(component.source) : null,
  });
}
function nullableText(value: FormDataEntryValue | null) { return String(value ?? "").trim() || null; }
function nullableNumber(value: FormDataEntryValue | null) { const text = String(value ?? "").trim(); return text ? Number(text) : null; }
function format(value: number | null, digits = 1) { return value === null ? "–" : new Intl.NumberFormat("de-DE", { maximumFractionDigits: digits }).format(value); }
function today() { const date = new Date(); return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`; }
function shiftDate(value: string, days: number) { const date = new Date(`${value}T12:00:00`); date.setDate(date.getDate() + days); return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`; }
function goalCategoryLabel(category: LocalNutritionTargetVersion["category"]) { return ({ Cut: "Cut", Maintenance: "Erhalt", Bulk: "Aufbau", Custom: "Benutzerdefiniert" })[category]; }
function formatLocalDate(value: string) { return new Intl.DateTimeFormat("de-DE", { day: "2-digit", month: "2-digit", year: "numeric", timeZone: "UTC" }).format(new Date(`${value}T12:00:00Z`)); }
function formatPhaseRange(phase: Pick<LocalNutritionTargetVersion, "effectiveFrom" | "effectiveUntil">) { return `${formatLocalDate(phase.effectiveFrom)} – ${phase.effectiveUntil ? formatLocalDate(phase.effectiveUntil) : "offen"}`; }
function errorMessage(error: unknown) { if (error instanceof NutritionInputError) return Object.values(error.fields).join(" "); return error instanceof Error ? error.message : "Lokales Speichern ist fehlgeschlagen."; }
function foodError(error: unknown) { if (error instanceof FoodCatalogApiError) { if (error.code === "product_not_found") return "Kein Produkt gefunden. Du kannst es manuell erfassen."; if (error.status === 429) return "Zu viele Anfragen. Bitte kurz warten oder manuell erfassen."; if (error.status >= 500) return "Open Food Facts ist vorübergehend nicht erreichbar. Manuelle Erfassung bleibt verfügbar."; } return error instanceof Error ? error.message : "Die Produktsuche ist fehlgeschlagen."; }

function aiError(error: unknown) {
  if (error instanceof FoodCatalogApiError) {
    if (error.code === "image_consent_required") return "Für ein Foto ist deine ausdrückliche Zustimmung erforderlich.";
    if (error.code === "daily_budget_exhausted" || error.status === 429) return "Das AI-Tageslimit ist erreicht. Nutze ein Gericht oder die manuelle Eingabe.";
    if (error.code.startsWith("invalid_image")) return "Das Bild konnte nicht sicher verarbeitet werden. Nutze JPEG, PNG oder WebP bis 8 MB.";
    if (error.status >= 500) return "Die AI-Schätzung ist vorübergehend nicht verfügbar. Manuelle Eingabe und Gerichte bleiben verfügbar.";
  }
  return error instanceof Error ? error.message : "Die AI-Schätzung ist fehlgeschlagen.";
}

interface BarcodeDetectorConstructor {
  new(options?: { formats?: string[] }): { detect(source: HTMLVideoElement): Promise<{ rawValue: string }[]> };
}
