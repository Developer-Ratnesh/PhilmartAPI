"use client";

import { useState } from "react";
import { Button, ErrorNote, Field, inputStyle, Notice } from "@/components/ui/Form";
import { api, ApiError, errorText, type ShopAuction } from "@/lib/api";

// SCR-SHP-005.5B1 / 005.5C: ordinary cancellation of a no-bid auction, or the
// controlled exception for one with bids (D016). Used by the Auctions list and
// by Auction Management.
export function CancelAuctionDialog({
  auction,
  onClose,
  onStale,
  onDone,
}: {
  auction: Pick<ShopAuction, "listingID" | "reference" | "title" | "bidCount">;
  onClose: () => void;
  onStale: (message: string) => void;
  onDone: () => void;
}) {
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
      await api.shop.cancelAuction(auction.listingID, reason, missing, auction.bidCount);
      onDone();
    } catch (err) {
      // a bid came in while the dialog was open: show the fresh list instead
      if (err instanceof ApiError && err.status === 409) {
        onStale(err.message);
        return;
      }
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
