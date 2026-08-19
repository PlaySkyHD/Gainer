"use client";

import { type FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import type { AccountDatabase } from "@/lib/offline/database";
import {
  archiveLocalCustomExercise,
  archiveLocalTemplate,
  createLocalCustomExercise,
  type ExerciseValues,
  type LocalTemplateItem,
  readTrainingPlanning,
  saveLocalRotation,
  saveLocalTemplate,
  TrainingPlanningInputError,
  updateLocalCustomExercise,
} from "@/lib/offline/training-planning";

type View = Awaited<ReturnType<typeof readTrainingPlanning>>;
const inputClass = "h-11 w-full rounded-xl border bg-background px-3 text-sm outline-none";

export function TrainingPlanningPanel({
  database,
  onPendingChange,
}: {
  database: AccountDatabase;
  onPendingChange: (count: number) => void;
}) {
  const [view, setView] = useState<View>();
  const [search, setSearch] = useState("");
  const [muscleGroup, setMuscleGroup] = useState("");
  const [equipment, setEquipment] = useState("");
  const [draftItems, setDraftItems] = useState<LocalTemplateItem[]>([]);
  const [rotationIds, setRotationIds] = useState<string[]>([]);
  const [error, setError] = useState<string>();
  const [message, setMessage] = useState<string>();

  const refresh = useCallback(async () => {
    const loaded = await readTrainingPlanning(database);
    setView(loaded);
    setRotationIds(loaded.rotation?.entries.map((entry) => entry.templateId) ?? []);
    onPendingChange(await database.outbox.where("status").equals("pending").count());
  }, [database, onPendingChange]);

  useEffect(() => {
    let current = true;
    void Promise.all([
      readTrainingPlanning(database),
      database.outbox.where("status").equals("pending").count(),
    ]).then(([loaded, pending]) => {
      if (!current) return;
      setView(loaded);
      setRotationIds(loaded.rotation?.entries.map((entry) => entry.templateId) ?? []);
      onPendingChange(pending);
    }).catch((caught) => { if (current) setError(errorMessage(caught)); });
    return () => { current = false; };
  }, [database, onPendingChange]);

  const visibleExercises = useMemo(() => view?.exercises.filter((exercise) =>
    !exercise.isArchived &&
    (!search || exercise.name.toLocaleLowerCase().includes(search.toLocaleLowerCase())) &&
    (!muscleGroup || exercise.muscleGroup === muscleGroup) &&
    (!equipment || exercise.equipment === equipment)) ?? [], [view, search, muscleGroup, equipment]);
  const selectableExercises = view?.exercises.filter((exercise) => !exercise.isArchived) ?? [];
  const activeTemplates = view?.templates.filter((template) => !template.isArchived) ?? [];

  async function createExercise(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); clearFeedback();
    const form = event.currentTarget;
    const data = new FormData(form);
    try {
      await createLocalCustomExercise(database, exerciseValues(data));
      form.reset(); setMessage("Eigene Übung lokal gespeichert."); await refresh();
    } catch (caught) { setError(errorMessage(caught)); }
  }

  async function renameExercise(exerciseId: string, current: ExerciseValues) {
    const name = window.prompt("Neuer Name der eigenen Übung", current.name);
    if (name === null) return;
    clearFeedback();
    try { await updateLocalCustomExercise(database, exerciseId, { ...current, name }); setMessage("Übung aktualisiert."); await refresh(); }
    catch (caught) { setError(errorMessage(caught)); }
  }

  async function archiveExercise(exerciseId: string) {
    if (!window.confirm("Eigene Übung archivieren? Vorhandene Templates behalten ihre Referenz.")) return;
    clearFeedback();
    try { await archiveLocalCustomExercise(database, exerciseId); setMessage("Übung archiviert."); await refresh(); }
    catch (caught) { setError(errorMessage(caught)); }
  }

  function addDraftExercise(exerciseId: string) {
    if (!exerciseId) return;
    setDraftItems((items) => [...items, {
      id: crypto.randomUUID(), exerciseId, plannedSets: 3,
      minimumRepetitions: 8, maximumRepetitions: 12,
      targetRir: null, restSeconds: 120, notes: null,
    }]);
  }

  async function saveTemplate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); clearFeedback();
    const form = event.currentTarget;
    try {
      await saveLocalTemplate(database, { name: String(new FormData(form).get("templateName")), items: draftItems });
      form.reset(); setDraftItems([]); setMessage("Template lokal gespeichert."); await refresh();
    } catch (caught) { setError(errorMessage(caught)); }
  }

  async function archiveTemplate(templateId: string) {
    if (!window.confirm("Template archivieren? Es wird in der Rotation übersprungen.")) return;
    clearFeedback();
    try { await archiveLocalTemplate(database, templateId); setMessage("Template archiviert."); await refresh(); }
    catch (caught) { setError(errorMessage(caught)); }
  }

  async function persistRotation() {
    clearFeedback();
    try { await saveLocalRotation(database, rotationIds); setMessage("Rotation lokal gespeichert."); await refresh(); }
    catch (caught) { setError(errorMessage(caught)); }
  }

  function clearFeedback() { setError(undefined); setMessage(undefined); }
  const exerciseName = (id: string) => view?.exercises.find((item) => item.id === id)?.name ?? "Archivierte Übung";
  const templateName = (id: string) => view?.templates.find((item) => item.id === id)?.name ?? "Archiviertes Template";

  return (
    <section id="training" className="space-y-6">
      {error && <p role="alert" className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">{error}</p>}
      {message && <p role="status" className="rounded-xl bg-emerald-500/12 p-3 text-sm text-emerald-800 dark:text-emerald-300">{message}</p>}

      <div className="rounded-2xl border bg-card p-5 sm:p-6">
        <h2 className="text-lg font-semibold">Übungsbibliothek</h2>
        <div className="mt-4 grid gap-3 sm:grid-cols-3">
          <label className="text-sm"><span className="sr-only">Übungen suchen</span><input className={inputClass} value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Nach Name suchen" /></label>
          <Filter label="Muskelgruppe" value={muscleGroup} values={unique(view?.exercises.map((item) => item.muscleGroup))} onChange={setMuscleGroup} />
          <Filter label="Equipment" value={equipment} values={unique(view?.exercises.map((item) => item.equipment))} onChange={setEquipment} />
        </div>
        <ul className="mt-4 grid gap-2 sm:grid-cols-2">
          {visibleExercises.map((exercise) => <li className="flex items-center justify-between gap-2 rounded-lg border p-3" key={exercise.id}>
            <div><p className="text-sm font-medium">{exercise.name}</p><p className="text-xs text-muted-foreground">{[exercise.muscleGroup, exercise.equipment, exercise.isCustom ? "Eigene Übung" : "Basiskatalog"].filter(Boolean).join(" · ")}</p></div>
            {exercise.isCustom && <div className="flex gap-1"><Button type="button" size="sm" variant="outline" onClick={() => renameExercise(exercise.id, exercise)}>Bearbeiten</Button><Button type="button" size="sm" variant="outline" onClick={() => archiveExercise(exercise.id)}>Archivieren</Button></div>}
          </li>)}
        </ul>
        <form className="mt-6 grid gap-3 sm:grid-cols-3" onSubmit={createExercise}>
          <Field label="Name der eigenen Übung"><input className={inputClass} name="name" required /></Field>
          <Field label="Muskelgruppe"><input className={inputClass} name="muscleGroup" /></Field>
          <Field label="Equipment"><input className={inputClass} name="equipment" /></Field>
          <Field label="Zielmuskel"><input className={inputClass} name="targetMuscle" /></Field>
          <Field label="Beschreibung"><input className={inputClass} name="description" /></Field>
          <Button className="self-end" type="submit">Eigene Übung anlegen</Button>
        </form>
      </div>

      <div className="rounded-2xl border bg-card p-5 sm:p-6">
        <h2 className="text-lg font-semibold">Trainings-Templates</h2>
        <form className="mt-4 space-y-4" onSubmit={saveTemplate}>
          <div className="grid gap-3 sm:grid-cols-[1fr_1fr_auto]">
            <Field label="Template-Name"><input className={inputClass} name="templateName" required /></Field>
            <Field label="Übung hinzufügen"><select className={inputClass} defaultValue="" onChange={(event) => { addDraftExercise(event.target.value); event.target.value = ""; }}><option value="">Bitte wählen</option>{selectableExercises.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></Field>
            <Button className="self-end" type="submit">Template speichern</Button>
          </div>
          <ol className="space-y-3">
            {draftItems.map((item, index) => <li className="rounded-xl border p-3" key={item.id}>
              <div className="flex items-center justify-between gap-2"><p className="text-sm font-medium">{index + 1}. {exerciseName(item.exerciseId)}</p><div className="flex gap-1"><Button type="button" size="sm" variant="outline" disabled={index === 0} onClick={() => setDraftItems(move(draftItems, index, index - 1))}>↑</Button><Button type="button" size="sm" variant="outline" disabled={index === draftItems.length - 1} onClick={() => setDraftItems(move(draftItems, index, index + 1))}>↓</Button><Button type="button" size="sm" variant="outline" onClick={() => setDraftItems(draftItems.filter((entry) => entry.id !== item.id))}>Entfernen</Button></div></div>
              <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-5">
                <NumberField label="Sätze" value={item.plannedSets} min={1} onChange={(value) => patchDraft(setDraftItems, item.id, { plannedSets: value ?? 0 })} />
                <NumberField label="Min. Wdh." value={item.minimumRepetitions} min={1} onChange={(value) => patchDraft(setDraftItems, item.id, { minimumRepetitions: value ?? 0 })} />
                <NumberField label="Max. Wdh." value={item.maximumRepetitions} min={1} onChange={(value) => patchDraft(setDraftItems, item.id, { maximumRepetitions: value ?? 0 })} />
                <NumberField label="RIR" value={item.targetRir ?? ""} min={0} max={10} step={0.5} onChange={(value) => patchDraft(setDraftItems, item.id, { targetRir: value })} nullable />
                <NumberField label="Pause (s)" value={item.restSeconds ?? ""} min={0} onChange={(value) => patchDraft(setDraftItems, item.id, { restSeconds: value })} nullable />
              </div>
            </li>)}
          </ol>
        </form>
        <ul className="mt-6 space-y-2">{view?.templates.map((template) => <li className="flex items-center justify-between rounded-lg border p-3" key={template.id}><div><p className="text-sm font-medium">{template.name}</p><p className="text-xs text-muted-foreground">{template.items.length} Übungen{template.isArchived ? " · Archiviert" : ""}</p></div>{!template.isArchived && <Button type="button" size="sm" variant="outline" onClick={() => archiveTemplate(template.id)}>Archivieren</Button>}</li>)}</ul>
      </div>

      <div className="rounded-2xl border bg-card p-5 sm:p-6">
        <h2 className="text-lg font-semibold">Workout-Rotation</h2>
        <p className="mt-2 text-sm">Nächstes Template: <strong>{view?.nextTemplateId ? templateName(view.nextTemplateId) : "Noch keines"}</strong></p>
        <div className="mt-4 flex gap-2"><select aria-label="Template zur Rotation hinzufügen" className={inputClass} defaultValue="" onChange={(event) => { if (event.target.value && !rotationIds.includes(event.target.value)) setRotationIds([...rotationIds, event.target.value]); event.target.value = ""; }}><option value="">Template hinzufügen</option>{activeTemplates.filter((item) => !rotationIds.includes(item.id)).map((item) => <option value={item.id} key={item.id}>{item.name}</option>)}</select><Button type="button" onClick={persistRotation}>Rotation speichern</Button></div>
        <ol className="mt-3 space-y-2">{rotationIds.map((id, index) => <li className="flex items-center justify-between rounded-lg border p-3" key={id}><span className="text-sm">{index + 1}. {templateName(id)}</span><div className="flex gap-1"><Button type="button" size="sm" variant="outline" disabled={index === 0} onClick={() => setRotationIds(move(rotationIds, index, index - 1))}>↑</Button><Button type="button" size="sm" variant="outline" disabled={index === rotationIds.length - 1} onClick={() => setRotationIds(move(rotationIds, index, index + 1))}>↓</Button><Button type="button" size="sm" variant="outline" onClick={() => setRotationIds(rotationIds.filter((item) => item !== id))}>Entfernen</Button></div></li>)}</ol>
      </div>
    </section>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) { return <label className="block space-y-2 text-sm font-medium"><span>{label}</span>{children}</label>; }
function Filter({ label, value, values, onChange }: { label: string; value: string; values: string[]; onChange: (value: string) => void }) { return <label className="text-sm"><span className="sr-only">{label}</span><select aria-label={label} className={inputClass} value={value} onChange={(event) => onChange(event.target.value)}><option value="">Alle: {label}</option>{values.map((item) => <option key={item}>{item}</option>)}</select></label>; }
function NumberField({ label, value, onChange, nullable = false, ...input }: { label: string; value: number | ""; onChange: (value: number | null) => void; nullable?: boolean; min?: number; max?: number; step?: number }) { return <Field label={label}><input className={inputClass} type="number" value={value} onChange={(event) => onChange(nullable && !event.target.value ? null : Number(event.target.value))} {...input} /></Field>; }
function patchDraft(setter: React.Dispatch<React.SetStateAction<LocalTemplateItem[]>>, id: string, patch: Partial<LocalTemplateItem>) { setter((items) => items.map((item) => item.id === id ? { ...item, ...patch } : item)); }
function move<T>(items: T[], from: number, to: number): T[] { const copy = [...items]; const [item] = copy.splice(from, 1); if (item !== undefined) copy.splice(to, 0, item); return copy; }
function unique(values: (string | null | undefined)[] | undefined): string[] { return [...new Set(values?.filter((value): value is string => Boolean(value)) ?? [])].sort(); }
function optional(data: FormData, name: string) { const value = String(data.get(name) ?? "").trim(); return value || null; }
function exerciseValues(data: FormData): ExerciseValues { return { name: String(data.get("name") ?? ""), description: optional(data, "description"), targetMuscle: optional(data, "targetMuscle"), muscleGroup: optional(data, "muscleGroup"), equipment: optional(data, "equipment") }; }
function errorMessage(error: unknown) { if (error instanceof TrainingPlanningInputError) return Object.values(error.fields).join(" "); return error instanceof Error ? error.message : "Lokales Speichern ist fehlgeschlagen."; }
