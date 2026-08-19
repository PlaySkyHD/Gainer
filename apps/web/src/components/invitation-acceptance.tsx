"use client";

import { type FormEvent, useState } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { UserRoundCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { acceptInvitation } from "@/lib/api/client";

const inputClass = "h-11 w-full rounded-xl border bg-secondary px-3 text-sm shadow-xs outline-none focus-visible:border-primary focus-visible:ring-3 focus-visible:ring-primary/20";

export function InvitationAcceptance() {
  const token = useSearchParams().get("token") ?? "";
  const [busy, setBusy] = useState(false);
  const [success, setSuccess] = useState(false);
  const [error, setError] = useState<string>();

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setBusy(true); setError(undefined);
    try {
      await acceptInvitation(token, String(new FormData(event.currentTarget).get("password")));
      setSuccess(true);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Die Einladung konnte nicht angenommen werden.");
    } finally { setBusy(false); }
  }

  return (
    <main className="app-shell grid min-h-dvh place-items-center p-5 sm:p-8">
      <section className="app-glass w-full max-w-sm space-y-6 rounded-[2rem] border p-7 sm:p-8">
        <div className="flex size-14 items-center justify-center rounded-2xl bg-primary text-primary-foreground shadow-lg shadow-primary/20"><UserRoundCheck className="size-7" aria-hidden="true" /></div>
        <div><p className="text-sm font-semibold text-primary">Gainer</p><h1 className="mt-2 text-3xl font-bold">Einladung annehmen</h1><p className="mt-2 text-sm leading-6 text-muted-foreground">Lege dein persönliches Passwort für den privaten Bereich fest.</p></div>
        {success ? (
          <div className="space-y-4"><p role="status">Dein Konto ist aktiviert.</p><Link className="text-sm font-medium underline underline-offset-4" href="/">Zur Anmeldung</Link></div>
        ) : (
          <form className="space-y-5" onSubmit={submit}>
            <label className="block space-y-2 text-sm font-medium"><span>Neues Passwort</span><input className={inputClass} name="password" type="password" autoComplete="new-password" minLength={12} required /></label>
            {!token && <p role="alert" className="text-sm text-destructive">Der Einladungslink ist unvollständig.</p>}
            {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
            <Button className="w-full" size="lg" type="submit" disabled={busy || !token}>Konto aktivieren</Button>
          </form>
        )}
      </section>
    </main>
  );
}
