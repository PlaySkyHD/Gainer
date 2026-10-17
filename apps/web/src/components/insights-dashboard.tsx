"use client";

import { useCallback, useEffect, useState } from "react";
import {
  CartesianGrid, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from "recharts";
import { Button } from "@/components/ui/button";
import { getDashboardInsights, type DashboardInsights } from "@/lib/api/client";
import type { AccountDatabase } from "@/lib/offline/database";

const dashboardCacheKey = "dashboard:30";

export function InsightsDashboard({ database, online }: { database: AccountDatabase; online: boolean }) {
  const [dashboard, setDashboard] = useState<DashboardInsights>();
  const [stale, setStale] = useState(false);
  const [error, setError] = useState<string>();

  const loadDashboard = useCallback(async () => {
    const cached = await database.analyticsCache.get(dashboardCacheKey);
    if (!online) {
      setDashboard(cached?.value as DashboardInsights | undefined);
      setStale(Boolean(cached));
      return;
    }
    try {
      const value = await getDashboardInsights(30);
      await database.analyticsCache.put({
        key: dashboardCacheKey, asOfRevision: Number(value.asOfRevision), value,
      });
      setDashboard(value); setStale(false); setError(undefined);
    } catch (caught) {
      setDashboard(cached?.value as DashboardInsights | undefined);
      setStale(Boolean(cached));
      setError(caught instanceof Error ? caught.message : "Insights konnten nicht geladen werden.");
    }
  }, [database, online]);

  useEffect(() => {
    const timer = window.setTimeout(() => void loadDashboard(), 0);
    return () => window.clearTimeout(timer);
  }, [loadDashboard]);
  return <section id="overview" className="space-y-5 rounded-2xl border bg-card p-5 sm:p-6">
    <div className="flex items-start justify-between gap-3"><div><h2 className="text-lg font-semibold">Fortschritt</h2><p className="text-sm text-muted-foreground">Deterministische Kennzahlen · Stand Revision {dashboard?.asOfRevision ?? "–"}</p></div><Button size="sm" variant="outline" disabled={!online} onClick={() => void loadDashboard()}>Aktualisieren</Button></div>
    {stale && <p className="rounded-xl bg-amber-500/12 p-3 text-sm text-amber-800 dark:text-amber-300">Offline gespeicherter Stand – möglicherweise veraltet.</p>}
    {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    {dashboard ? <>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Metric label="Aktuelles Gewicht" value={dashboard.latestWeight ? `${number(dashboard.latestWeight.weightKg)} kg` : "Keine Daten"} />
        <Metric label="7-Tage-Mittel" value={dashboard.sevenDayWeight.averageKg === null ? "Keine Daten" : `${number(dashboard.sevenDayWeight.averageKg)} kg`} />
        <Metric label="Trend pro Woche" value={dashboard.weight.trendKgPerWeek === null ? "Mind. 3 Messungen" : `${signed(dashboard.weight.trendKgPerWeek)} kg`} />
        <Metric label="Workouts diese Woche" value={String(dashboard.workoutsLast7Days)} />
        <Metric label="Kalorien Ø" value={average(dashboard.nutrition.caloriesKcal.value, "kcal")} />
        <Metric label="Protein Ø" value={average(dashboard.nutrition.proteinGrams.value, "g")} />
        <Metric label="Trainingsvolumen" value={`${number(dashboard.training.volumeKgRepetitions)} kg·Wdh.`} />
        <Metric label="Aktives Ziel" value={dashboard.activeGoal ? `${dashboard.activeGoal.kind}: ${number(dashboard.activeGoal.targetWeightKg)} kg` : "Kein Ziel"} />
      </div>
      <div className="h-64" aria-label="Gewichtsverlauf"><ResponsiveContainer width="100%" height="100%"><LineChart data={dashboard.weightSeries}><CartesianGrid strokeDasharray="3 3" /><XAxis dataKey="date" /><YAxis domain={["dataMin - 1", "dataMax + 1"]} unit=" kg" /><Tooltip /><Line type="monotone" dataKey="weightKg" name="Gewicht" stroke="var(--primary)" strokeWidth={2} dot /></LineChart></ResponsiveContainer></div>
    </> : <p className="text-sm text-muted-foreground">Noch keine synchronisierten Kennzahlen verfügbar.</p>}
  </section>;
}

function Metric({ label, value }: { label: string; value: string }) {
  return <div className="rounded-xl bg-muted/50 p-3"><p className="text-xs text-muted-foreground">{label}</p><p className="mt-1 font-semibold">{value}</p></div>;
}
function number(value: number | string) { return Number(value).toLocaleString("de-DE", { maximumFractionDigits: 2 }); }
function signed(value: number | string) { const parsed = Number(value); return `${parsed > 0 ? "+" : ""}${number(parsed)}`; }
function average(value: number | string | null, unit: string) { return value === null ? "Keine Daten" : `${number(value)} ${unit}`; }
