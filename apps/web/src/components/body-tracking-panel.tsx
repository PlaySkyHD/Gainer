"use client";

import { type FormEvent, useCallback, useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import type { AccountDatabase } from "@/lib/offline/database";
import {
  activateLocalGoal,
  BodyTrackingInputError,
  readLocalBodyTracking,
  saveLocalCheckIn,
} from "@/lib/offline/body-tracking";

type View = Awaited<ReturnType<typeof readLocalBodyTracking>>;
const inputClass = "h-11 w-full rounded-xl border bg-background px-3 text-sm outline-none";

export function BodyTrackingPanel({
  database,
  onPendingChange,
}: {
  database: AccountDatabase;
  onPendingChange: (count: number) => void;
}) {
  const [view, setView] = useState<View>();
  const [error, setError] = useState<string>();
  const [message, setMessage] = useState<string>();

  const refresh = useCallback(async () => {
    setView(await readLocalBodyTracking(database));
    onPendingChange(await database.outbox.where("status").equals("pending").count());
  }, [database, onPendingChange]);
  useEffect(() => {
    let current = true;
    void Promise.all([
      readLocalBodyTracking(database),
      database.outbox.where("status").equals("pending").count(),
    ]).then(([loaded, pending]) => {
      if (current) {
        setView(loaded);
        onPendingChange(pending);
      }
    });
    return () => { current = false; };
  }, [database, onPendingChange]);

  async function saveGoal(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setError(undefined); setMessage(undefined);
    const form = new FormData(event.currentTarget);
    try {
      await activateLocalGoal(database, {
        kind: String(form.get("kind")) as "Bulk" | "Maintain" | "Cut",
        startWeightKg: Number(form.get("startWeightKg")),
        targetWeightKg: Number(form.get("targetWeightKg")),
        startDate: String(form.get("startDate")),
        targetDate: nullableText(form.get("targetDate")),
      });
      setMessage("Ziel lokal gespeichert.");
      await refresh();
    } catch (caught) { setError(errorMessage(caught)); }
  }

  async function saveCheckIn(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setError(undefined); setMessage(undefined);
    const form = new FormData(event.currentTarget);
    try {
      await saveLocalCheckIn(database, {
        localDate: String(form.get("localDate")),
        weightKg: Number(form.get("weightKg")),
        caloriesKcal: nullableNumber(form.get("caloriesKcal")),
        proteinGrams: nullableNumber(form.get("proteinGrams")),
        carbohydrateGrams: nullableNumber(form.get("carbohydrateGrams")),
        fatGrams: nullableNumber(form.get("fatGrams")),
        steps: nullableNumber(form.get("steps")),
        sleepMinutes: nullableNumber(form.get("sleepMinutes")),
      });
      setMessage("Check-in gespeichert.");
      await refresh();
    } catch (caught) { setError(errorMessage(caught)); }
  }

  return (
    <div className="space-y-6">
      {error && <p role="alert" className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
      {message && <p role="status" className="rounded-xl bg-emerald-500/12 p-3 text-sm text-emerald-800 dark:text-emerald-300">{message}</p>}
      <section id="check-in" className="rounded-2xl border bg-card p-5 sm:p-6">
        <h2 className="text-lg font-semibold">Daily Check-in</h2>
        <form className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4" onSubmit={saveCheckIn}>
          <Field label="Kalendertag"><input className={inputClass} name="localDate" type="date" defaultValue={localDate()} required /></Field>
          <Field label="Gewicht (kg)"><input className={inputClass} name="weightKg" type="number" min="0.01" step="0.01" required /></Field>
          <Field label="Kalorien (kcal)"><input className={inputClass} name="caloriesKcal" type="number" min="0" step="0.01" /></Field>
          <Field label="Protein (g)"><input className={inputClass} name="proteinGrams" type="number" min="0" step="0.01" /></Field>
          <Field label="Kohlenhydrate (g)"><input className={inputClass} name="carbohydrateGrams" type="number" min="0" step="0.01" /></Field>
          <Field label="Fett (g)"><input className={inputClass} name="fatGrams" type="number" min="0" step="0.01" /></Field>
          <Field label="Schritte"><input className={inputClass} name="steps" type="number" min="0" step="1" /></Field>
          <Field label="Schlaf (Minuten)"><input className={inputClass} name="sleepMinutes" type="number" min="0" max="1440" step="1" /></Field>
          <Button className="h-10 sm:col-span-2 lg:col-span-4" type="submit">Check-in speichern</Button>
        </form>
      </section>

      <section id="overview" className="rounded-2xl border bg-card p-5 sm:p-6">
        <h2 className="text-lg font-semibold">Körperziel</h2>
        {view?.activeGoal ? <p className="mt-2 text-sm">{view.activeGoal.kind}: {view.activeGoal.startWeightKg} kg → {view.activeGoal.targetWeightKg} kg</p> : <p className="mt-2 text-sm text-muted-foreground">Noch kein aktives Ziel.</p>}
        <form className="mt-5 grid gap-4 sm:grid-cols-2" onSubmit={saveGoal}>
          <Field label="Zielart"><select className={inputClass} name="kind"><option>Bulk</option><option>Maintain</option><option>Cut</option></select></Field>
          <Field label="Startgewicht (kg)"><input className={inputClass} name="startWeightKg" type="number" min="0.01" step="0.01" required /></Field>
          <Field label="Zielgewicht (kg)"><input className={inputClass} name="targetWeightKg" type="number" min="0.01" step="0.01" required /></Field>
          <Field label="Startdatum"><input className={inputClass} name="startDate" type="date" defaultValue={localDate()} required /></Field>
          <Field label="Zieldatum (optional)"><input className={inputClass} name="targetDate" type="date" /></Field>
          <Button className="h-10 sm:self-end" type="submit">Ziel aktivieren</Button>
        </form>
        <h3 className="mt-6 text-sm font-semibold">Zielhistorie</h3>
        {view?.goalHistory.length ? <ul className="mt-2 space-y-1 text-sm">{view.goalHistory.map((goal) => <li key={goal.id}>{goal.kind}: {goal.startWeightKg} kg → {goal.targetWeightKg} kg</li>)}</ul> : <p className="mt-2 text-sm text-muted-foreground">Noch keine vergangenen Ziele.</p>}
      </section>

      <section id="history" className="rounded-2xl border bg-card p-5 sm:p-6">
        <h2 className="text-lg font-semibold">Letzte Check-ins</h2>
        {view?.checkIns.length ? <ul className="mt-3 divide-y">{view.checkIns.slice(0, 10).map((item) => <li className="flex justify-between py-2 text-sm" key={item.id}><span>{item.localDate}</span><span className="font-medium">{item.weightKg} kg</span></li>)}</ul> : <p className="mt-2 text-sm text-muted-foreground">Noch keine Check-ins.</p>}
      </section>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <label className="space-y-1.5 text-sm font-medium"><span>{label}</span>{children}</label>;
}

function nullableText(value: FormDataEntryValue | null) {
  const text = String(value ?? "").trim();
  return text || null;
}

function nullableNumber(value: FormDataEntryValue | null) {
  const text = String(value ?? "").trim();
  return text === "" ? null : Number(text);
}

function localDate() {
  const date = new Date();
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function errorMessage(error: unknown) {
  if (error instanceof BodyTrackingInputError) return Object.values(error.fields).join(" ");
  return error instanceof Error ? error.message : "Lokales Speichern ist fehlgeschlagen.";
}
