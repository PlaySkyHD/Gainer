"use client";

import { type FormEvent, useState } from "react";
import { Button } from "@/components/ui/button";
import { askCoach, type CoachAnswer } from "@/lib/api/client";

export function CoachPanel({ online }: { online: boolean }) {
  const [answer, setAnswer] = useState<CoachAnswer>();
  const [lastQuestion, setLastQuestion] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const question = String(new FormData(event.currentTarget).get("question") ?? "").trim();
    if (question) await request(question);
  }

  async function request(question: string) {
    setBusy(true); setError(undefined); setLastQuestion(question);
    try { setAnswer(await askCoach(question)); }
    catch (caught) { setError(caught instanceof Error ? caught.message : "Der Coach ist vorübergehend nicht verfügbar."); }
    finally { setBusy(false); }
  }

  return <section id="coach" className="rounded-2xl border bg-card p-6">
    <h2 className="text-lg font-semibold">AI Progress Coach</h2>
    <p className="mt-2 text-sm text-muted-foreground">Der Coach liest ausschließlich freigegebene, serverberechnete Fortschrittsfakten und verändert keine Daten.</p>
    {!online && <p role="status" className="mt-4 rounded-xl bg-amber-500/12 p-3 text-sm text-amber-800 dark:text-amber-300">Der Coach ist offline nicht verfügbar. Tracking und Verlauf funktionieren weiter.</p>}
    <form className="mt-4 flex flex-col gap-3 sm:flex-row" onSubmit={submit}>
      <label className="flex-1"><span className="sr-only">Frage an den Coach</span><textarea className="min-h-24 w-full rounded-lg border bg-background p-3 text-sm" maxLength={1000} name="question" placeholder="Wie entwickelt sich mein Fortschritt?" required /></label>
      <Button className="sm:self-end" type="submit" disabled={!online || busy}>{busy ? "Fakten werden geprüft …" : "Fragen"}</Button>
    </form>
    {error && <div className="mt-4 rounded-lg bg-destructive/10 p-3 text-sm text-destructive" role="alert"><p>{error}</p><Button className="mt-2" size="sm" variant="outline" disabled={!online || busy} onClick={() => void request(lastQuestion)}>Erneut versuchen</Button></div>}
    {answer && <div className="mt-5 space-y-4">
      <div><h3 className="font-semibold">Zusammenfassung</h3><p className="mt-1 text-sm">{answer.summary}</p></div>
      {answer.observations.length > 0 && <div><h3 className="text-sm font-semibold">Beobachtungen</h3><ul className="mt-2 list-disc space-y-1 pl-5 text-sm">{answer.observations.map((item, index) => <li key={index}>{item.text}</li>)}</ul></div>}
      {answer.facts.length > 0 && <div><h3 className="text-sm font-semibold">Verwendete Evidenz</h3><div className="mt-2 grid gap-2 sm:grid-cols-2">{answer.facts.map((fact) => <div className="rounded-lg border p-3 text-sm" key={fact.factId}><p className="text-xs text-muted-foreground">{fact.label} · {fact.period}</p><p className="mt-1 font-medium">{fact.numericValue === null ? fact.textValue : `${format(fact.numericValue)}${fact.unit ? ` ${fact.unit}` : ""}`}</p>{fact.algorithmVersion && <p className="mt-1 text-xs text-muted-foreground">{fact.algorithmVersion}</p>}</div>)}</div></div>}
      {answer.dataGaps.length > 0 && <div><h3 className="text-sm font-semibold">Datenlücken</h3><ul className="mt-2 list-disc space-y-1 pl-5 text-sm">{answer.dataGaps.map((item) => <li key={item}>{item}</li>)}</ul></div>}
      {answer.suggestions.length > 0 && <div><h3 className="text-sm font-semibold">Nächste Schritte</h3><ul className="mt-2 list-disc space-y-1 pl-5 text-sm">{answer.suggestions.map((item) => <li key={item}>{item}</li>)}</ul></div>}
    </div>}
  </section>;
}

function format(value: number | string) { return Number(value).toLocaleString("de-DE", { maximumFractionDigits: 2 }); }
