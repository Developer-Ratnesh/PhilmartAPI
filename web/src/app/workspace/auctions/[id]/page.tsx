"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { WorkspaceShell } from "@/components/layout/WorkspaceShell";
import { CancelAuctionDialog } from "@/components/workspace/CancelAuctionDialog";
import { ErrorNote, Notice } from "@/components/ui/Form";
import { api, errorText, formatMoney, type AuctionManagement } from "@/lib/api";
import { hasPermission, useSession } from "@/lib/session";

type Tab = "overview" | "bids" | "activity";

const when = (iso: string) => new Date(iso).toLocaleString("en-ZA");

// SCR-SHP-006.1 Auction Management, BR-13 Shop side. Everything on it comes
// from the server, the same rows the Auctions list and the item page use.
export default function AuctionManagementPage() {
  const { id } = useParams<{ id: string }>();
  const session = useSession();
  const canCancelWithBids = hasPermission(session?.user, "auction.cancel_with_bids");

  const [auction, setAuction] = useState<AuctionManagement | null>(null);
  const [tab, setTab] = useState<Tab>("overview");
  const [cancelling, setCancelling] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);

  const reload = useCallback(() => setAttempt((n) => n + 1), []);

  useEffect(() => {
    let cancelled = false;
    api.shop
      .auction(id)
      .then((a) => !cancelled && setAuction(a))
      .catch((e) => !cancelled && setError(errorText(e, "This auction couldn't be found.")));
    return () => {
      cancelled = true;
    };
  }, [id, attempt]);

  // a live auction keeps moving, so look again every 15 seconds
  const live = auction?.state === "live" || auction?.state === "scheduled";
  useEffect(() => {
    if (!live) return;
    const t = setInterval(reload, 15_000);
    return () => clearInterval(t);
  }, [live, reload]);

  const open = auction !== null && (auction.state === "live" || auction.state === "scheduled");
  const hasBids = (auction?.bidCount ?? 0) > 0;

  return (
    <WorkspaceShell screenId="SCR-SHP-006.1">
      <h1 className="font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>Auction Management</h1>
      <Link href="/workspace/auctions" className="mb-5 inline-block text-sm hover:underline" style={{ color: "var(--accent-info)" }}>
        ‹ Back to Auctions
      </Link>

      <ErrorNote message={error} />
      {notice && <Notice>{notice}</Notice>}

      {auction && (
        <>
          <section
            className="mb-6 grid grid-cols-2 gap-x-6 gap-y-4 p-4 text-sm md:grid-cols-4"
            style={{ background: "var(--surface-card)", border: "1px solid var(--border-subtle)" }}
          >
            <Fact label="Item" value={`${auction.reference} · ${auction.title} · ${auction.itemReference}`} />
            <Fact label="Auction type" value="Standalone" />
            <Fact label="Auction event" value="—" />
            <Fact label="Status" value={<StateLabel state={auction.state} />} />
            <Fact label="Governance" value="Standalone Shop auction" />
            <Fact label="Relationship" value="No Auction Event" />
            <Fact label="Timing / rules" value={open ? "PHILMART server time" : "Closed · read-only"} />
            <Fact label="Seller" value={auction.sellerName ?? "Shop stock"} />
          </section>

          <div className="mb-5 flex flex-wrap items-start justify-between gap-3">
            <div className="flex flex-wrap gap-2" role="tablist">
              {(["overview", "bids", "activity"] as Tab[]).map((t) => (
                <button
                  key={t}
                  type="button"
                  role="tab"
                  aria-selected={tab === t}
                  onClick={() => setTab(t)}
                  className="min-w-28 px-5 py-2.5 text-sm font-semibold capitalize"
                  style={{
                    background: tab === t ? "var(--philmart-navy-deep)" : "var(--surface-card)",
                    color: tab === t ? "#ffffff" : "var(--philmart-navy-ink)",
                    border: "1px solid var(--border-default)",
                    borderRadius: 4,
                  }}
                >
                  {t === "bids" ? `Bids (${auction.bidCount})` : t}
                </button>
              ))}
            </div>

            <div className="flex flex-wrap gap-2">
              {auction.state === "live" && (
                <Link
                  href={`/item/${auction.listingID}`}
                  className="px-5 py-2.5 text-sm font-semibold"
                  style={{ border: "1px solid var(--border-default)", borderRadius: 4, color: "var(--accent-info)", background: "var(--surface-card)" }}
                >
                  View Item
                </Link>
              )}
              {open && !hasBids && (
                <ActionButton onClick={() => setCancelling(true)}>Cancel auction</ActionButton>
              )}
              {open && hasBids && canCancelWithBids && (
                <ActionButton onClick={() => setCancelling(true)}>Report Missing / Damaged</ActionButton>
              )}
            </div>
          </div>

          {open && hasBids && (
            <p className="-mt-3 mb-4 text-right text-xs" style={{ color: "var(--text-muted)" }}>
              Missing / Damaged: Shop Administrator only. Ordinary cancellation isn&apos;t available once there is a valid bid.
            </p>
          )}

          {tab === "overview" && <Overview auction={auction} onBids={() => setTab("bids")} />}
          {tab === "bids" && <Bids auction={auction} />}
          {tab === "activity" && <Activity auction={auction} />}
        </>
      )}

      {cancelling && auction && (
        <CancelAuctionDialog
          auction={auction}
          onClose={() => setCancelling(false)}
          onStale={(message) => {
            setCancelling(false);
            setError(message);
            reload();
          }}
          onDone={() => {
            setCancelling(false);
            setNotice(hasBids ? "Auction cancelled. Bidders have been notified and their bids kept on record." : "Auction cancelled.");
            reload();
          }}
        />
      )}
    </WorkspaceShell>
  );
}

function Overview({ auction, onBids }: { auction: AuctionManagement; onBids: () => void }) {
  const bidState =
    auction.state === "sold"
      ? "Sold to the highest bidder"
      : auction.state === "cancelled"
        ? "Cancelled"
        : auction.bidCount > 0
          ? "Valid bid received"
          : "No bids yet";

  return (
    <div className="grid gap-5 lg:grid-cols-2">
      <Card title="Auction Details">
        <Row label="Auction opening price" value={formatMoney(auction.startingPriceMinor)} />
        <Row label="Reserve" value={auction.reservePriceMinor === null ? "No reserve" : formatMoney(auction.reservePriceMinor)} />
        <Row label="Bid increment" value={formatMoney(auction.bidIncrementMinor)} />
        <Row label="Auction starts" value={when(auction.startsAt)} />
        <Row
          label="Auction ends"
          value={when(auction.endsAt) + (auction.extensionCount > 0 ? ` (extended ${auction.extensionCount}× by soft close)` : "")}
        />
        <Row label="Auction event" value="—" />
        {auction.cancellationReason && <Row label="Cancellation reason" value={auction.cancellationReason} />}
        <p className="mt-4 text-xs" style={{ color: "var(--text-muted)" }}>
          A live auction is read-only. Ordinary cancellation is unavailable after a valid bid. Missing / Damaged remains the controlled Shop
          Administrator exception (D016).
        </p>
      </Card>

      <Card title="Bidding Snapshot">
        <Row
          label={auction.state === "sold" ? "Sold price" : "Current bid"}
          value={
            <span className="font-semibold" style={{ color: "var(--accent-info)" }}>
              {formatMoney(auction.soldPriceMinor ?? auction.currentBidMinor)}
            </span>
          }
        />
        <Row label="Bid state" value={bidState} />
        <Row label="Bids" value={String(auction.bidCount)} />
        <Row label="Bidder details" value="Not shown in this view" />
        <button type="button" onClick={onBids} className="mt-4 w-full p-4 text-left text-xs hover:underline" style={{ background: "var(--surface-sunken)", color: "var(--text-secondary)" }}>
          Bid details are available on the Bids tab.
        </button>
      </Card>
    </div>
  );
}

function Bids({ auction }: { auction: AuctionManagement }) {
  if (auction.bids.length === 0) return <Notice>No bids on this auction.</Notice>;

  return (
    <div className="overflow-x-auto" style={{ background: "var(--surface-card)", border: "1px solid var(--border-subtle)" }}>
      <table className="w-full text-left text-sm">
        <thead style={{ background: "var(--surface-sunken)" }}>
          <tr className="text-xs" style={{ color: "var(--text-secondary)" }}>
            <th className="px-4 py-3">Rank</th>
            <th className="px-4 py-3">Bidder</th>
            <th className="px-4 py-3">Amount</th>
            <th className="px-4 py-3">Placed (server time)</th>
            <th className="px-4 py-3">Bid no.</th>
            <th className="px-4 py-3">Status</th>
          </tr>
        </thead>
        <tbody>
          {auction.bids.map((b) => (
            <tr key={b.sequenceNo} style={{ borderTop: "1px solid var(--border-subtle)", color: "var(--text-primary)" }}>
              <td className="px-4 py-3">{b.rank}</td>
              <td className="px-4 py-3">{b.bidder}</td>
              <td className="px-4 py-3 font-semibold">{formatMoney(b.amountMinor)}</td>
              <td className="px-4 py-3 text-xs">{when(b.placedAt)}</td>
              <td className="px-4 py-3 text-xs">{b.sequenceNo}</td>
              <td className="px-4 py-3 text-xs">
                {b.winning ? "Winning bid" : b.leading ? "Leading" : "Outbid"}
                {b.extendedClose && <span style={{ color: "var(--text-muted)" }}> · extended the close</span>}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Activity({ auction }: { auction: AuctionManagement }) {
  if (auction.activity.length === 0) return <Notice>Nothing has happened on this auction yet.</Notice>;

  return (
    <ol style={{ background: "var(--surface-card)", border: "1px solid var(--border-subtle)" }}>
      {auction.activity.map((a, i) => (
        <li key={i} className="flex flex-wrap gap-x-6 gap-y-1 px-4 py-3 text-sm" style={{ borderTop: i === 0 ? "none" : "1px solid var(--border-subtle)" }}>
          <span className="w-44 shrink-0 text-xs" style={{ color: "var(--text-muted)" }}>{when(a.at)}</span>
          <span style={{ color: "var(--text-primary)" }}>
            {a.description}
            {a.reason && <span style={{ color: "var(--text-secondary)" }}> Reason: {a.reason}</span>}
          </span>
        </li>
      ))}
    </ol>
  );
}

function Fact({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <div className="text-[10px] font-semibold uppercase tracking-wide" style={{ color: "var(--text-muted)" }}>{label}</div>
      <div className="mt-1 text-xs" style={{ color: "var(--text-primary)" }}>{value}</div>
    </div>
  );
}

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="p-6" style={{ background: "var(--surface-card)", border: "1px solid var(--border-subtle)", borderRadius: "var(--radius-card)" }}>
      <h2 className="mb-4 text-base font-bold" style={{ color: "var(--text-primary)" }}>{title}</h2>
      {children}
    </section>
  );
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="grid grid-cols-2 gap-4 py-3 text-sm" style={{ borderBottom: "1px solid var(--border-subtle)" }}>
      <span className="text-xs" style={{ color: "var(--text-secondary)" }}>{label}</span>
      <span style={{ color: "var(--text-primary)" }}>{value}</span>
    </div>
  );
}

function ActionButton({ onClick, children }: { onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="px-5 py-2.5 text-sm font-semibold"
      style={{ border: "1px solid var(--border-default)", borderRadius: 4, color: "var(--accent-danger)", background: "var(--surface-card)" }}
    >
      {children}
    </button>
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
