"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { WorkspaceShell } from "@/components/layout/WorkspaceShell";
import { Button, ErrorNote, Field, inputStyle, Notice } from "@/components/ui/Form";
import { api, errorText, formatMoney, type ReadyItem, type ShopAuction } from "@/lib/api";
import { hasPermission, useSession } from "@/lib/session";

// SCR-SHP-006 Auctions, BR-13 Shop side
export default function AuctionsPage() {
  const session = useSession();
  const canCancelWithBids = hasPermission(session?.user, "auction.cancel_with_bids");

  const [auctions, setAuctions] = useState<ShopAuction[]>([]);
  const [ready, setReady] = useState<ReadyItem[]>([]);
  const [creating, setCreating] = useState(false);
  const [cancelling, setCancelling] = useState<ShopAuction | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);

  const reload = useCallback(() => setAttempt((n) => n + 1), []);

  useEffect(() => {
    let cancelled = false;
    Promise.all([api.shop.auctions(), api.shop.readyItems()])
      .then(([a, r]) => {
        if (cancelled) return;
        setAuctions(a);
        setReady(r);
      })
      .catch((e) => !cancelled && setError(errorText(e)));
    return () => {
      cancelled = true;
    };
  }, [attempt]);

  return (
    <WorkspaceShell screenId="SCR-SHP-006">
      <div className="mb-5 flex items-end justify-between gap-4">
        <div>
          <h1 className="font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>Auctions</h1>
          <p className="text-sm" style={{ color: "var(--text-secondary)" }}>
            Auction times run on PHILMART server time. A closed auction is history and can&apos;t be reopened.
          </p>
        </div>
        <Button type="button" wide={false} onClick={() => setCreating(true)} disabled={ready.length === 0}>
          New auction
        </Button>
      </div>

      <ErrorNote message={error} />
      {notice && <Notice>{notice}</Notice>}
      {ready.length === 0 && <Notice>No items are Ready to List, so there&apos;s nothing to auction right now.</Notice>}

      <div className="overflow-x-auto" style={{ background: "var(--surface-card)", border: "1px solid var(--border-subtle)" }}>
        <table className="w-full text-left text-sm">
          <thead style={{ background: "var(--surface-sunken)" }}>
            <tr className="text-xs" style={{ color: "var(--text-secondary)" }}>
              <th className="px-4 py-3">Reference</th>
              <th className="px-4 py-3">Item</th>
              <th className="px-4 py-3">State</th>
              <th className="px-4 py-3">Start</th>
              <th className="px-4 py-3">Current</th>
              <th className="px-4 py-3">Bids</th>
              <th className="px-4 py-3">Ends</th>
              <th className="px-4 py-3">Actions</th>
            </tr>
          </thead>
          <tbody>
            {auctions.map((a) => (
              <tr key={a.listingID} style={{ borderTop: "1px solid var(--border-subtle)", color: "var(--text-primary)" }}>
                <td className="px-4 py-3 font-mono text-xs">{a.reference}</td>
                <td className="px-4 py-3">
                  {a.state === "live" ? <Link href={`/item/${a.listingID}`} className="hover:underline">{a.title}</Link> : a.title}
                </td>
                <td className="px-4 py-3 text-xs">
                  <StateLabel state={a.state} />
                  {a.extensionCount > 0 && <span className="ml-1" style={{ color: "var(--text-muted)" }}>· extended {a.extensionCount}×</span>}
                </td>
                <td className="px-4 py-3">{formatMoney(a.startingPriceMinor)}</td>
                <td className="px-4 py-3">{formatMoney(a.soldPriceMinor ?? a.currentBidMinor)}</td>
                <td className="px-4 py-3">{a.bidCount}</td>
                <td className="px-4 py-3 text-xs">{new Date(a.endsAt).toLocaleString("en-ZA")}</td>
                <td className="px-4 py-3 text-xs">
                  {(a.state === "live" || a.state === "scheduled") && (a.bidCount === 0 || canCancelWithBids) && (
                    <button type="button" className="font-semibold hover:underline" style={{ color: "var(--accent-danger)" }} onClick={() => setCancelling(a)}>
                      Cancel
                    </button>
                  )}
                  {a.cancellationReason && <span style={{ color: "var(--text-muted)" }}>{a.cancellationReason}</span>}
                </td>
              </tr>
            ))}
            {auctions.length === 0 && (
              <tr>
                <td colSpan={8} className="px-4 py-6 text-center text-sm" style={{ color: "var(--text-muted)" }}>No auctions yet.</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {creating && (
        <CreateDialog
          items={ready}
          onClose={() => setCreating(false)}
          onSaved={() => {
            setCreating(false);
            setNotice("Auction scheduled. It goes live at its start time.");
            reload();
          }}
        />
      )}

      {cancelling && (
        <CancelDialog
          auction={cancelling}
          onClose={() => setCancelling(null)}
          onDone={() => {
            setCancelling(null);
            setNotice(cancelling.bidCount > 0 ? "Auction cancelled. Bidders have been notified and their bids kept on record." : "Auction cancelled.");
            reload();
          }}
        />
      )}
    </WorkspaceShell>
  );
}

function StateLabel({ state }: { state: string }) {
  const colour: Record<string, string> = {
    live: "var(--accent-live)",
    scheduled: "var(--accent-info)",
    sold: "var(--accent-auction)",
    cancelled: "var(--accent-danger)",
  };
  return (
    <span className="font-semibold capitalize" style={{ color: colour[state] ?? "var(--text-muted)" }}>
      {state}
    </span>
  );
}

function toLocalInput(d: Date) {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function CreateDialog({ items, onClose, onSaved }: { items: ReadyItem[]; onClose: () => void; onSaved: () => void }) {
  const [itemId, setItemId] = useState(items[0]?.itemID ?? "");
  const [start, setStart] = useState(() => toLocalInput(new Date(Date.now() + 10 * 60_000)));
  const [end, setEnd] = useState(() => toLocalInput(new Date(Date.now() + 7 * 86_400_000)));
  const [startingPrice, setStartingPrice] = useState("");
  const [reserve, setReserve] = useState("");
  const [increment, setIncrement] = useState("");
  const [softMinutes, setSoftMinutes] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const item = items.find((i) => i.itemID === itemId);
  const cents = (v: string) => Math.round(Number(v) * 100);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const soft = softMinutes ? Math.round(Number(softMinutes) * 60) : null;
      await api.shop.createAuction({
        itemID: itemId,
        startingPriceMinor: cents(startingPrice),
        reservePriceMinor: reserve ? cents(reserve) : null,
        bidIncrementMinor: cents(increment),
        startsAt: new Date(start).toISOString(),
        endsAt: new Date(end).toISOString(),
        softCloseSeconds: soft,
        softCloseExtensionSeconds: soft,
      });
      onSaved();
    } catch (err) {
      setError(errorText(err));
      setBusy(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto p-4" style={{ background: "rgb(15 23 42 / 0.5)" }} role="dialog" aria-modal="true">
      <form onSubmit={save} className="mt-10 w-full max-w-xl p-6" style={{ background: "var(--surface-card)", borderRadius: "var(--radius-card)" }}>
        <h2 className="mb-4 font-display text-2xl font-bold" style={{ color: "var(--text-primary)" }}>New auction</h2>
        <ErrorNote message={error} />

        <Field label="Item (Ready to List)" htmlFor="item">
          <select id="item" value={itemId} onChange={(e) => setItemId(e.target.value)} style={inputStyle}>
            {items.map((i) => (
              <option key={i.itemID} value={i.itemID}>{i.reference} — {i.title}</option>
            ))}
          </select>
        </Field>

        {item?.sellerMinimumPriceMinor && (
          <Notice>Seller Minimum Price {formatMoney(item.sellerMinimumPriceMinor)}. The reserve, or the starting price if there&apos;s no reserve, can&apos;t be lower (D062).</Notice>
        )}

        <div className="grid grid-cols-3 gap-4">
          <Field label="Starting price (R)" htmlFor="startPrice">
            <input id="startPrice" type="number" step="0.01" min="0" required value={startingPrice} onChange={(e) => setStartingPrice(e.target.value)} style={inputStyle} />
          </Field>
          <Field label="Reserve (R, optional)" htmlFor="reserve">
            <input id="reserve" type="number" step="0.01" min="0" value={reserve} onChange={(e) => setReserve(e.target.value)} style={inputStyle} />
          </Field>
          <Field label="Bid increment (R)" htmlFor="increment">
            <input id="increment" type="number" step="0.01" min="0.01" required value={increment} onChange={(e) => setIncrement(e.target.value)} style={inputStyle} />
          </Field>
        </div>

        <div className="grid grid-cols-2 gap-4">
          <Field label="Starts" htmlFor="starts" hint="Must be in the future.">
            <input id="starts" type="datetime-local" required value={start} onChange={(e) => setStart(e.target.value)} style={inputStyle} />
          </Field>
          <Field label="Ends" htmlFor="ends">
            <input id="ends" type="datetime-local" required value={end} onChange={(e) => setEnd(e.target.value)} style={inputStyle} />
          </Field>
        </div>

        <Field label="Soft close (minutes, optional)" htmlFor="soft" hint="A bid inside this window before the end pushes the end out by the same amount.">
          <input id="soft" type="number" min="1" value={softMinutes} onChange={(e) => setSoftMinutes(e.target.value)} style={inputStyle} />
        </Field>

        <div className="grid grid-cols-2 gap-4">
          <Button type="button" variant="secondary" onClick={onClose}>Cancel</Button>
          <Button disabled={busy || !itemId}>Schedule auction</Button>
        </div>
      </form>
    </div>
  );
}

function CancelDialog({ auction, onClose, onDone }: { auction: ShopAuction; onClose: () => void; onDone: () => void }) {
  const [reason, setReason] = useState("");
  const [missing, setMissing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const hasBids = auction.bidCount > 0;

  async function cancel(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await api.shop.cancelAuction(auction.listingID, reason, missing);
      onDone();
    } catch (err) {
      setError(errorText(err));
      setBusy(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto p-4" style={{ background: "rgb(15 23 42 / 0.5)" }} role="dialog" aria-modal="true">
      <form onSubmit={cancel} className="mt-10 w-full max-w-lg p-6" style={{ background: "var(--surface-card)", borderRadius: "var(--radius-card)" }}>
        <h2 className="mb-2 font-display text-2xl font-bold" style={{ color: "var(--text-primary)" }}>
          {hasBids ? "Cancel an auction with bids" : "Cancel auction"}
        </h2>
        <p className="mb-4 text-sm" style={{ color: "var(--text-secondary)" }}>
          {auction.reference} · {auction.title}
        </p>

        <ErrorNote message={error} />

        {hasBids && (
          <Notice>
            This auction has {auction.bidCount} {auction.bidCount === 1 ? "bid" : "bids"}. Cancelling is only for exceptional cases such as the item being missing or
            damaged. Every bid stays on record and the bidders are told (D016).
          </Notice>
        )}

        <Field label="Reason" htmlFor="reason">
          <textarea id="reason" required rows={3} value={reason} onChange={(e) => setReason(e.target.value)} style={inputStyle} />
        </Field>

        <label className="mb-5 flex items-center gap-2 text-sm" style={{ color: "var(--text-primary)" }}>
          <input type="checkbox" checked={missing} onChange={(e) => setMissing(e.target.checked)} />
          The item is missing or damaged
        </label>

        <div className="grid grid-cols-2 gap-4">
          <Button type="button" variant="secondary" onClick={onClose}>Keep the auction</Button>
          <Button variant="danger" disabled={busy || !reason.trim()}>Cancel auction</Button>
        </div>
      </form>
    </div>
  );
}
