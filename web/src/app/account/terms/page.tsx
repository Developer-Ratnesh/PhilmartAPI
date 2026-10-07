"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { PublicFooter, PublicHeader } from "@/components/layout/PublicHeader";
import { Button, ErrorNote, Notice, Panel } from "@/components/ui/Form";
import { api, errorText, type LegalDocument } from "@/lib/api";
import { updateUser, useSession } from "@/lib/session";

// BR-01-R09: a superseded document has to be accepted again before the next
// purchase or bid. The old acceptance stays, this adds a new one (BR-01-R05).
export default function RenewTermsPage() {
  const session = useSession();
  const [docs, setDocs] = useState<LegalDocument[]>([]);
  const [ticked, setTicked] = useState<Record<string, boolean>>({});
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const pending = session?.user.pendingAcceptances ?? [];

  useEffect(() => {
    if (!session) return;
    let cancelled = false;
    api.register
      .legal()
      .then((d) => !cancelled && setDocs(d))
      .catch((e) => !cancelled && setError(errorText(e)));
    return () => {
      cancelled = true;
    };
  }, [session]);

  async function accept() {
    setBusy(true);
    setError(null);
    try {
      await api.register.accept(docs.map((d) => d.versionID));
      updateUser(await api.auth.me());
      setDone(true);
    } catch (e) {
      setError(errorText(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex min-h-screen flex-col" style={{ background: "var(--surface-marketplace)" }}>
      <PublicHeader />
      <main className="mx-auto w-full max-w-2xl flex-1 px-4 py-10">
        <h1 className="mb-6 font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>
          Updated terms
        </h1>

        <Panel>
          <ErrorNote message={error} />

          {!session && (
            <Notice>
              <Link href="/login" className="font-semibold hover:underline">Sign in</Link> to review the terms.
            </Notice>
          )}

          {done ? (
            <>
              <Notice>Thanks, you&apos;re all set to buy and bid again.</Notice>
              <Link href="/marketplace"><Button type="button">Back to the marketplace</Button></Link>
            </>
          ) : (
            session && (
              <>
                <p className="mb-4 text-sm" style={{ color: "var(--text-secondary)" }}>
                  {pending.length > 0
                    ? "Some of our documents have changed since you last accepted them. Please review the current versions."
                    : "You've accepted everything that's current."}
                </p>

                {docs.map((d) => (
                  <div key={d.versionID} className="mb-4">
                    <h2 className="font-display text-base font-semibold" style={{ color: "var(--text-primary)" }}>
                      {d.name} <span className="text-xs font-normal" style={{ color: "var(--text-muted)" }}>version {d.version}</span>
                      {pending.includes(d.code) && (
                        <span className="ml-2 text-xs font-bold" style={{ color: "var(--accent-attention)" }}>Updated</span>
                      )}
                    </h2>
                    <div className="my-2 max-h-40 overflow-y-auto whitespace-pre-wrap p-3 text-xs" style={{ border: "1px solid var(--border-subtle)", borderRadius: 4, color: "var(--text-secondary)" }}>
                      {d.body}
                    </div>
                    <label className="flex items-center gap-2 text-sm" style={{ color: "var(--text-primary)" }}>
                      <input type="checkbox" checked={!!ticked[d.versionID]} onChange={(e) => setTicked((t) => ({ ...t, [d.versionID]: e.target.checked }))} />
                      {d.acceptanceMode === "acknowledge" ? `I acknowledge the ${d.name}` : `I accept the ${d.name}`}
                    </label>
                  </div>
                ))}

                {pending.length > 0 && (
                  <Button type="button" onClick={accept} disabled={busy || !docs.every((d) => ticked[d.versionID])}>
                    Accept the current terms
                  </Button>
                )}
              </>
            )
          )}
        </Panel>
      </main>
      <PublicFooter />
    </div>
  );
}
