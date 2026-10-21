"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { BuyerOnly } from "@/components/account/BuyerOnly";
import { AccountShell } from "@/components/layout/AccountShell";
import { Button, ErrorNote, Notice, Panel } from "@/components/ui/Form";
import { api, errorText, type LegalAcceptance, type LegalDocument } from "@/lib/api";
import { updateUser, useSession } from "@/lib/session";

const CONTEXT: Record<LegalAcceptance["context"], string> = {
  registration: "Registration",
  buy_now: "Buy Now",
  confirm_bid: "Bid",
  shop_setup: "Shop setup",
};

const when = (iso: string) =>
  new Date(iso).toLocaleString("en-ZA", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });

// The legal document versions this buyer accepted (checklist L.8). BR-01-R09:
// when a document is superseded it has to be accepted again before the next
// purchase or bid; the old acceptance stays and a new one is added (BR-01-R05).
export default function AcceptedTermsPage() {
  const session = useSession();
  const isBuyer = session?.user.actorKind === "Buy_Buyer";
  const pending = session?.user.pendingAcceptances ?? [];
  const [history, setHistory] = useState<LegalAcceptance[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [version, setVersion] = useState(0);

  useEffect(() => {
    if (!isBuyer) return;
    let cancelled = false;
    api.account
      .legal()
      .then((h) => !cancelled && setHistory(h))
      .catch((e) => !cancelled && setError(errorText(e)));
    return () => {
      cancelled = true;
    };
  }, [isBuyer, version]);

  const registration = (history ?? []).filter((h) => h.context === "registration");
  const commitments = (history ?? []).filter((h) => h.context !== "registration");

  return (
    <AccountShell screenId="SCR-PUB-006">
      <BuyerOnly>
        <h1 className="font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>
          Accepted Terms
        </h1>
        <p className="mb-6 mt-1 text-sm" style={{ color: "var(--text-secondary)" }}>
          The versions of the PHILMART documents you accepted, and when. You can read the current versions on the{" "}
          <Link href="/terms" className="font-semibold hover:underline" style={{ color: "var(--accent-info)" }}>
            Terms &amp; Conditions
          </Link>{" "}
          page.
        </p>

        <ErrorNote message={error} />

        {pending.length > 0 && <Renewal pending={pending} onDone={() => setVersion((v) => v + 1)} />}

        <Panel>
          <h2 className="mb-3 font-display text-xl font-semibold" style={{ color: "var(--text-primary)" }}>
            Account documents
          </h2>
          {history === null ? (
            <p className="text-sm" style={{ color: "var(--text-muted)" }}>Loading…</p>
          ) : registration.length === 0 ? (
            <p className="text-sm" style={{ color: "var(--text-muted)" }}>You haven&apos;t accepted any documents yet.</p>
          ) : (
            <AcceptanceTable rows={registration} />
          )}
        </Panel>

        {commitments.length > 0 && (
          <div className="mt-6">
            <Panel>
              <h2 className="mb-1 font-display text-xl font-semibold" style={{ color: "var(--text-primary)" }}>
                Purchase and bid commitments
              </h2>
              <p className="mb-3 text-xs" style={{ color: "var(--text-muted)" }}>
                The commitment wording you confirmed with each Buy Now and bid.
              </p>
              <AcceptanceTable rows={commitments} />
            </Panel>
          </div>
        )}
      </BuyerOnly>
    </AccountShell>
  );
}

function AcceptanceTable({ rows }: { rows: LegalAcceptance[] }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-left text-sm">
        <thead>
          <tr className="text-xs" style={{ color: "var(--text-secondary)", borderBottom: "1px solid var(--border-default)" }}>
            <th className="py-2 pr-4 font-semibold">Document</th>
            <th className="py-2 pr-4 font-semibold">Version</th>
            <th className="py-2 pr-4 font-semibold">Accepted at</th>
            <th className="py-2 pr-4 font-semibold">With</th>
            <th className="py-2 font-semibold">Status</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <tr key={i} style={{ borderBottom: "1px solid var(--border-subtle)", color: "var(--text-primary)" }}>
              <td className="py-2.5 pr-4">
                {row.documentName}
                {row.acceptanceMode === "acknowledge" && (
                  <span className="ml-1 text-xs" style={{ color: "var(--text-muted)" }}>(acknowledged)</span>
                )}
              </td>
              <td className="py-2.5 pr-4 font-mono text-xs">{row.version}</td>
              <td className="py-2.5 pr-4 whitespace-nowrap">{when(row.acceptedAt)}</td>
              <td className="py-2.5 pr-4">{CONTEXT[row.context] ?? row.context}</td>
              <td className="py-2.5">
                <span
                  className="px-2 py-0.5 text-[11px] font-semibold"
                  style={{
                    borderRadius: 3,
                    background: row.isCurrent ? "var(--accent-live-bg)" : "var(--surface-sunken)",
                    color: row.isCurrent ? "var(--accent-live)" : "var(--text-muted)",
                  }}
                >
                  {row.isCurrent ? "Current" : "Superseded"}
                </span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Renewal({ pending, onDone }: { pending: string[]; onDone: () => void }) {
  const [docs, setDocs] = useState<LegalDocument[]>([]);
  const [ticked, setTicked] = useState<Record<string, boolean>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    api.register
      .legal()
      .then((d) => !cancelled && setDocs(d))
      .catch((e) => !cancelled && setError(errorText(e)));
    return () => {
      cancelled = true;
    };
  }, []);

  async function accept() {
    setBusy(true);
    setError(null);
    try {
      await api.register.accept(docs.map((d) => d.versionID));
      updateUser(await api.auth.me());
      onDone();
    } catch (e) {
      setError(errorText(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mb-6">
      <Panel>
        <h2 className="mb-1 font-display text-xl font-semibold" style={{ color: "var(--accent-attention)" }}>
          Updated documents to accept
        </h2>
        <p className="mb-4 text-sm" style={{ color: "var(--text-secondary)" }}>
          Some documents have changed since you accepted them. Please review the current versions before your next purchase or bid.
        </p>
        <ErrorNote message={error} />

        {docs.map((d) => (
          <div key={d.versionID} className="mb-4">
            <h3 className="font-display text-base font-semibold" style={{ color: "var(--text-primary)" }}>
              {d.name} <span className="text-xs font-normal" style={{ color: "var(--text-muted)" }}>version {d.version}</span>
              {pending.includes(d.code) && (
                <span className="ml-2 text-xs font-bold" style={{ color: "var(--accent-attention)" }}>Updated</span>
              )}
            </h3>
            <div
              className="my-2 max-h-40 overflow-y-auto whitespace-pre-wrap p-3 text-xs"
              style={{ border: "1px solid var(--border-subtle)", borderRadius: 4, color: "var(--text-secondary)" }}
            >
              {d.body}
            </div>
            <label className="flex items-center gap-2 text-sm" style={{ color: "var(--text-primary)" }}>
              <input type="checkbox" checked={!!ticked[d.versionID]} onChange={(e) => setTicked((t) => ({ ...t, [d.versionID]: e.target.checked }))} />
              {d.acceptanceMode === "acknowledge" ? `I acknowledge the ${d.name}` : `I accept the ${d.name}`}
            </label>
          </div>
        ))}

        {docs.length > 0 && (
          <Button type="button" onClick={accept} disabled={busy || !docs.every((d) => ticked[d.versionID])} wide={false}>
            Accept the current terms
          </Button>
        )}
        {docs.length === 0 && !error && <Notice>Loading the current documents…</Notice>}
      </Panel>
    </div>
  );
}
