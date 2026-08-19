"use client";

import { type FormEvent, useCallback, useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import type { AccountDatabase } from "@/lib/offline/database";
import { readTrainingPlanning } from "@/lib/offline/training-planning";
import {
  addLocalWorkoutExercise,
  addLocalWorkoutSet,
  completeLocalWorkout,
  discardLocalWorkout,
  extendLocalRestTimer,
  type LocalPreviousPerformance,
  type LocalWorkout,
  moveLocalWorkoutExercise,
  readLocalPreviousPerformance,
  readLocalWorkoutHistory,
  readLocalWorkoutHistoryDetail,
  readRunningWorkout,
  removeLocalWorkoutExercise,
  removeLocalWorkoutSet,
  restartLocalRestTimer,
  restTimerRemainingSeconds,
  saveLocalWorkoutSet,
  skipLocalRestTimer,
  startLocalWorkout,
  WorkoutInputError,
} from "@/lib/offline/workout-execution";

type Running = Awaited<ReturnType<typeof readRunningWorkout>>;
type History = Awaited<ReturnType<typeof readLocalWorkoutHistory>>;
type Planning = Awaited<ReturnType<typeof readTrainingPlanning>>;
const inputClass = "h-11 w-full rounded-xl border bg-background px-3 text-sm outline-none sm:h-10";

export function WorkoutPanel({ database, onPendingChange }: { database: AccountDatabase; onPendingChange: (count: number) => void }) {
  const [running, setRunning] = useState<Running>();
  const [history, setHistory] = useState<History>([]);
  const [planning, setPlanning] = useState<Planning>();
  const [previous, setPrevious] = useState<Record<string, LocalPreviousPerformance | undefined>>({});
  const [detail, setDetail] = useState<(LocalWorkout & { id: string })>();
  const [error, setError] = useState<string>();
  const [message, setMessage] = useState<string>();
  const [, setClockTick] = useState(0);

  const apply = useCallback((loaded: Awaited<ReturnType<typeof loadView>>) => {
    setRunning(loaded.running);
    setHistory(loaded.history);
    setPlanning(loaded.planning);
    setPrevious(loaded.previous);
    onPendingChange(loaded.pending);
  }, [onPendingChange]);
  const refresh = useCallback(async () => apply(await loadView(database)), [database, apply]);

  useEffect(() => {
    let current = true;
    void loadView(database).then((loaded) => { if (current) apply(loaded); })
      .catch((caught) => { if (current) setError(errorMessage(caught)); });
    return () => { current = false; };
  }, [database, apply]);
  useEffect(() => {
    if (!running?.restTimer) return;
    const interval = window.setInterval(() => setClockTick((value) => value + 1), 1_000);
    return () => window.clearInterval(interval);
  }, [running?.restTimer]);

  async function action(work: () => Promise<unknown>, success: string) {
    setError(undefined); setMessage(undefined);
    try { await work(); setMessage(success); await refresh(); }
    catch (caught) { setError(errorMessage(caught)); }
  }

  async function saveSet(event: FormEvent<HTMLFormElement>, exerciseId: string, setId: string) {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    await action(() => saveLocalWorkoutSet(database, running!.id, exerciseId, setId, {
      weightKg: numberOrNull(data.get("weightKg")),
      repetitions: numberOrNull(data.get("repetitions")),
      rir: numberOrNull(data.get("rir")),
      notes: textOrNull(data.get("notes")),
    }, true), "Satz gespeichert.");
  }

  async function showDetail(workoutId: string) {
    setDetail(await readLocalWorkoutHistoryDetail(database, workoutId));
  }

  const activeTemplates = planning?.templates.filter((item) => !item.isArchived) ?? [];
  const selectableExercises = planning?.exercises.filter((item) => !item.isArchived) ?? [];
  const remaining = restTimerRemainingSeconds(running?.restTimer ?? null);

  return (
    <section id="workout" className="space-y-6">
      {error && <p role="alert" className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
      {message && <p role="status" className="rounded-xl bg-emerald-500/12 p-3 text-sm text-emerald-800 dark:text-emerald-300">{message}</p>}
      {!running ? <div className="rounded-2xl border bg-card p-5 sm:p-6">
        <h2 className="text-lg font-semibold">Workout starten</h2>
        <p className="mt-2 text-sm text-muted-foreground">Vorgeschlagen: {planning?.nextTemplateId ? activeTemplates.find((item) => item.id === planning.nextTemplateId)?.name : "Keine Rotation eingerichtet"}</p>
        <div className="mt-4 flex flex-wrap gap-2">{activeTemplates.map((template) => <Button type="button" key={template.id} onClick={() => action(() => startLocalWorkout(database, template.id), `${template.name} gestartet.`)}>{template.name} starten</Button>)}</div>
      </div> : <div className="space-y-4 rounded-2xl border bg-card p-5 sm:p-6">
        <div className="flex flex-wrap items-start justify-between gap-3"><div><p className="text-sm text-muted-foreground">Laufendes Workout</p><h2 className="text-xl font-semibold">{running.templateNameSnapshot}</h2></div><div className="flex gap-2"><Button type="button" onClick={() => action(() => completeLocalWorkout(database, running.id), "Workout abgeschlossen.")}>Workout abschließen</Button><Button type="button" variant="destructive" onClick={() => { if (window.confirm("Workout wirklich abbrechen? Gespeicherte Sätze zählen dann nicht.")) void action(() => discardLocalWorkout(database, running.id), "Workout abgebrochen."); }}>Abbrechen</Button></div></div>
        {running.restTimer && <div className="flex flex-wrap items-center gap-2 rounded-xl border border-amber-500/20 bg-amber-500/12 p-3 text-amber-800 dark:text-amber-300"><strong className="mr-auto">Pause: {formatTimer(remaining ?? 0)}</strong><Button size="sm" type="button" variant="outline" onClick={() => action(() => extendLocalRestTimer(database, running.id), "Timer verlängert.")}>+30 Sekunden</Button><Button size="sm" type="button" variant="outline" onClick={() => action(() => restartLocalRestTimer(database, running.id), "Timer neu gestartet.")}>Neustart</Button><Button size="sm" type="button" variant="outline" onClick={() => action(() => skipLocalRestTimer(database, running.id), "Timer übersprungen.")}>Überspringen</Button></div>}
        <div className="flex gap-2"><select aria-label="Übung zum Workout hinzufügen" className={inputClass} defaultValue="" onChange={(event) => { if (event.target.value) void action(() => addLocalWorkoutExercise(database, running.id, event.target.value), "Übung hinzugefügt."); event.target.value = ""; }}><option value="">Übung hinzufügen</option>{selectableExercises.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></div>
        <ol className="space-y-4">{running.exercises.map((exercise, exerciseIndex) => <li className="rounded-xl border p-4" key={exercise.id}>
          <div className="flex flex-wrap items-center justify-between gap-2"><div><h3 className="font-semibold">{exerciseIndex + 1}. {exercise.exerciseNameSnapshot}</h3><p className="text-xs text-muted-foreground">Ziel {exercise.minimumRepetitions}–{exercise.maximumRepetitions} Wdh.{previous[exercise.id]?.sets[0] ? ` · Zuvor ${previous[exercise.id]!.sets[0]!.weightKg} kg × ${previous[exercise.id]!.sets[0]!.repetitions}` : " · Keine lokale vorherige Leistung"}</p></div><div className="flex gap-1"><Button size="sm" variant="outline" type="button" disabled={exerciseIndex === 0} onClick={() => action(() => moveLocalWorkoutExercise(database, running.id, exercise.id, exerciseIndex - 1), "Reihenfolge geändert.")}>↑</Button><Button size="sm" variant="outline" type="button" disabled={exerciseIndex === running.exercises.length - 1} onClick={() => action(() => moveLocalWorkoutExercise(database, running.id, exercise.id, exerciseIndex + 1), "Reihenfolge geändert.")}>↓</Button><Button size="sm" variant="outline" type="button" onClick={() => action(() => removeLocalWorkoutExercise(database, running.id, exercise.id), "Übung entfernt.")}>Entfernen</Button></div></div>
          <div className="mt-3 space-y-2">{exercise.sets.map((set, setIndex) => <form className="grid gap-2 rounded-lg bg-muted/40 p-3 sm:grid-cols-[3rem_repeat(4,1fr)_auto]" key={set.id} onSubmit={(event) => saveSet(event, exercise.id, set.id)}>
            <span className="self-center text-sm font-medium">#{setIndex + 1}</span><SetInput label={`${exercise.exerciseNameSnapshot} Satz ${setIndex + 1} Gewicht (kg)`} name="weightKg" defaultValue={set.weightKg} step="0.01" min="0" /><SetInput label={`${exercise.exerciseNameSnapshot} Satz ${setIndex + 1} Wiederholungen`} name="repetitions" defaultValue={set.repetitions} step="1" min="1" /><SetInput label={`${exercise.exerciseNameSnapshot} Satz ${setIndex + 1} RIR`} name="rir" defaultValue={set.rir} step="0.5" min="0" max="10" /><label><span className="sr-only">Notiz</span><input className={inputClass} name="notes" defaultValue={set.notes ?? ""} placeholder="Notiz" /></label><div className="flex gap-1"><Button size="sm" type="submit">{set.isCompleted ? "Aktualisieren" : "Satz fertig"}</Button><Button size="sm" variant="outline" type="button" onClick={() => action(() => removeLocalWorkoutSet(database, running.id, exercise.id, set.id), "Satz entfernt.")}>×</Button></div>
          </form>)}</div><Button className="mt-3" size="sm" variant="outline" type="button" onClick={() => action(() => addLocalWorkoutSet(database, running.id, exercise.id), "Satz hinzugefügt.")}>Satz hinzufügen</Button>
        </li>)}</ol>
      </div>}

      <div id="history" className="rounded-2xl border bg-card p-5 sm:p-6"><h2 className="text-lg font-semibold">Workout-Historie</h2><ul className="mt-4 space-y-2">{history.length === 0 ? <li className="text-sm text-muted-foreground">Noch kein abgeschlossenes Workout.</li> : history.map((workout) => <li className="flex items-center justify-between rounded-lg border p-3" key={workout.id}><div><p className="text-sm font-medium">{workout.templateNameSnapshot}</p><p className="text-xs text-muted-foreground">{new Date(workout.completedAtUtc!).toLocaleString("de-DE")} · {Math.round((new Date(workout.completedAtUtc!).getTime() - new Date(workout.startedAtUtc).getTime()) / 60_000)} Min.</p></div><Button type="button" size="sm" variant="outline" onClick={() => showDetail(workout.id)}>Details</Button></li>)}</ul>
        {detail && <div className="mt-4 rounded-xl bg-muted/50 p-4"><div className="flex justify-between"><h3 className="font-semibold">{detail.templateNameSnapshot}</h3><Button type="button" size="sm" variant="outline" onClick={() => setDetail(undefined)}>Schließen</Button></div>{detail.exercises.map((exercise) => <div className="mt-3" key={exercise.id}><p className="text-sm font-medium">{exercise.exerciseNameSnapshot}</p><p className="text-xs text-muted-foreground">{exercise.sets.filter((set) => set.isCompleted).map((set) => `${set.weightKg} kg × ${set.repetitions}`).join(" · ") || "Keine abgeschlossenen Sätze"}</p></div>)}</div>}
      </div>
    </section>
  );
}

async function loadView(database: AccountDatabase) {
  const [running, history, planning, pending] = await Promise.all([readRunningWorkout(database), readLocalWorkoutHistory(database), readTrainingPlanning(database), database.outbox.where("status").equals("pending").count()]);
  const previousEntries = running ? await Promise.all(running.exercises.map(async (exercise) => [exercise.id, exercise.sourceExerciseId ? await readLocalPreviousPerformance(database, exercise.sourceExerciseId, running.startedAtUtc) : undefined] as const)) : [];
  return { running, history, planning, pending, previous: Object.fromEntries(previousEntries) as Record<string, LocalPreviousPerformance | undefined> };
}
function SetInput({ label, defaultValue, ...props }: { label: string; defaultValue: number | null; name: string; step: string; min: string; max?: string }) { return <label><span className="sr-only">{label}</span><input aria-label={label} className={inputClass} type="number" defaultValue={defaultValue ?? ""} {...props} /></label>; }
function numberOrNull(value: FormDataEntryValue | null) { return value === null || String(value).trim() === "" ? null : Number(value); }
function textOrNull(value: FormDataEntryValue | null) { const text = String(value ?? "").trim(); return text || null; }
function formatTimer(seconds: number) { return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`; }
function errorMessage(error: unknown) { if (error instanceof WorkoutInputError) return Object.values(error.fields).join(" "); return error instanceof Error ? error.message : "Die Workout-Aktion ist fehlgeschlagen."; }
