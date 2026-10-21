"use client";

import { useCallback, useEffect, useState } from "react";
import { Button, ErrorNote, Field, inputStyle, Notice, Panel } from "@/components/ui/Form";
import { errorText, restrictionsApi, type BuyerRestriction } from "@/lib/api";

const when = (iso: string) =>
  new Date(iso).toLocaleString("en-ZA", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });

// D044/D045. A restricted buyer can't Buy Now or bid (with this Shop, or anywhere
// for a PHILMART restriction). What they've already bought or bid on carries on.
export function RestrictionsPanel({ platform }: { platform: boolean }) {
  const [calls] = useState(() => restrictionsApi(platform ? "/api/admin/restrictions" : "/api/shop/restrictions"));
  const [rows, setRows] = useState<BuyerRestriction[] | null>(null);
  const [email, setEmail] = useState("");
  const [reason, setReason] = useState("");
  const [lifting, setLifting] = useState<BuyerRestriction | null>(null);
  const [liftReason, setLiftReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const load = useCallback(() => {
    calls
      .list()
      .then(setRows)
      .catch((e) => setError(errorText(e)));
  }, [calls]);

  useEffect(load, [load]);

  async function restrict(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      const r = await calls.restrict(email.trim(), reason.trim());
      setNotice(`${r.buyerEmail} is now restricted.`);
      setEmail("");
      setReason("");
      load();
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  async function lift() {
    if (!lifting) return;
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      await calls.lift(lifting.id, liftReason.trim());
      setNotice(`The restriction on ${lifting.buyerEmail} has been lifted.`);
      setLifting(null);
      setLiftReason("");
      load();
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex flex-col gap-6">
      <ErrorNote message={error} />
      {notice && <Notice>{notice}</Notice>}

      <Panel>
        <h2 className="mb-1 font-display text-xl font-semibold" style={{ color: "var(--text-primary)" }}>
          Restrict a buyer
        </h2>
        <p className="mb-4 text-sm" style={{ color: "var(--text-secondary)" }}>
          {platform
            ? "A PHILMART restriction stops new purchases and bids at every Shop. Only PHILMART can lift it."
            : "The buyer can't Buy Now or bid with your Shop until you lift it. Purchases and bids already made carry on."}
        </p>
        <form onSubmit={restrict} className="grid gap-3 md:grid-cols-[1fr_2fr_auto] md:items-end">
          <Field label="Buyer's email" htmlFor="restrict-email">
            <input id="restrict-email" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} style={inputStyle} />
          </Field>
          <Field label="Reason (required, recorded)" htmlFor="restrict-reason">
            <input id="restrict-reason" required maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)} style={inputStyle} />
          </Field>
          <div className="mb-4">
            <Button disabled={busy || !email.trim() || !reason.trim()} wide={false} variant="danger">Restrict</Button>
          </div>
        </form>
      </Panel>

      <Panel>
        <h2 className="mb-3 font-display text-xl font-semibold" style={{ color: "var(--text-primary)" }}>
          Restrictions
        </h2>
        {rows === null ? (
          <p className="text-sm" style={{ color: "var(--text-muted)" }}>Loading…</p>
        ) : rows.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--text-muted)" }}>No buyers have been restricted.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead>
                <tr className="text-xs" style={{ color: "var(--text-secondary)", borderBottom: "1px solid var(--border-default)" }}>
                  <th className="py-2 pr-4 font-semibold">Buyer</th>
                  {platform && <th className="py-2 pr-4 font-semibold">Scope</th>}
                  <th className="py-2 pr-4 font-semibold">Reason</th>
                  <th className="py-2 pr-4 font-semibold">Restricted</th>
                  <th className="py-2 pr-4 font-semibold">Status</th>
                  <th className="py-2" />
                </tr>
              </thead>
              <tbody>
                {rows.map((r) => (
                  <tr key={r.id} style={{ borderBottom: "1px solid var(--border-subtle)", color: "var(--text-primary)" }}>
                    <td className="py-2.5 pr-4">
                      {r.buyerName ?? r.buyerEmail}
                      {r.buyerName && <span className="block text-xs" style={{ color: "var(--text-muted)" }}>{r.buyerEmail}</span>}
                    </td>
                    {platform && <td className="py-2.5 pr-4">{r.scope === "platform" ? "PHILMART (all Shops)" : r.shopName}</td>}
                    <td className="py-2.5 pr-4">{r.reason}</td>
                    <td className="whitespace-nowrap py-2.5 pr-4">{when(r.imposedAt)}</td>
                    <td className="py-2.5 pr-4">
                      {r.liftedAt ? (
                        <span className="text-xs" style={{ color: "var(--text-muted)" }}>
                          Lifted {when(r.liftedAt)}
                          {r.liftReason && <span className="block">{r.liftReason}</span>}
                        </span>
                      ) : (
                        <span className="px-2 py-0.5 text-[11px] font-semibold" style={{ borderRadius: 3, background: "var(--accent-attention-bg, var(--surface-sunken))", color: "var(--accent-attention)" }}>
                          Active
                        </span>
                      )}
                    </td>
                    <td className="py-2.5 text-right">
                      {r.canLift && (
                        <button type="button" className="text-xs font-semibold hover:underline" style={{ color: "var(--accent-info)" }} onClick={() => setLifting(r)}>
                          Lift
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Panel>

      {lifting && (
        <div className="fixed inset-0 z-50 flex items-start justify-center p-4" style={{ background: "rgb(15 23 42 / 0.5)" }} role="dialog" aria-modal="true">
          <div className="mt-20 w-full max-w-lg p-6" style={{ background: "var(--surface-card)", borderRadius: "var(--radius-card)" }}>
            <h2 className="mb-2 font-display text-xl font-bold" style={{ color: "var(--text-primary)" }}>Lift restriction</h2>
            <p className="mb-4 text-sm" style={{ color: "var(--text-secondary)" }}>{lifting.buyerEmail} will be able to buy and bid again.</p>
            <Field label="Reason (required, recorded)" htmlFor="lift-reason">
              <input id="lift-reason" autoFocus maxLength={1000} value={liftReason} onChange={(e) => setLiftReason(e.target.value)} style={inputStyle} />
            </Field>
            <div className="grid grid-cols-2 gap-4">
              <Button type="button" variant="secondary" onClick={() => setLifting(null)}>Cancel</Button>
              <Button type="button" onClick={lift} disabled={busy || !liftReason.trim()}>Lift restriction</Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
