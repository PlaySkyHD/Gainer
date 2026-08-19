import { Suspense } from "react";
import { InvitationAcceptance } from "@/components/invitation-acceptance";

export default function AcceptInvitationPage() {
  return <Suspense fallback={<main className="grid min-h-dvh place-items-center p-6">Einladung wird geladen …</main>}><InvitationAcceptance /></Suspense>;
}
