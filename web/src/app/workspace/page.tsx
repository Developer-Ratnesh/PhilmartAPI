"use client";

import Link from "next/link";
import { useCallback, useEffect, useState, type ReactNode } from "react";
import { WorkspaceShell } from "@/components/layout/WorkspaceShell";
import { ErrorNote } from "@/components/ui/Form";
import { api, errorText, formatMoney, type ShopDashboard } from "@/lib/api";
import { hasPermission, useSession } from "@/lib/session";

const when = (iso: string | null) =>
  iso ? new Date(iso).toLocaleString("en-ZA", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "";

// SCR-SHP-002. Every Shop user lands here; each card shows only when the
// user's permissions cover it, and the API leaves the rest out.
export default function WorkspaceDashboard() {
  const session = useSession();
  const user = session?.user;
  const isShopUser = user?.actorKind === "Shop_User";
  const [data, setData] = useState<ShopDashboard | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(() => {
    setBusy(true);
    return api.shop
      .dashboard()
      .then((d) => {
        setData(d);
        setError(null);
      })
      .catch((e) => setError(errorText(e)))
      .finally(() => setBusy(false));
  }, []);

  useEffect(() => {
    if (!isShopUser) return;
    let cancelled = false;
    api.shop
      .dashboard()
      .then((d) => !cancelled && setData(d))
      .catch((e) => !cancelled && setError(errorText(e)));
    return () => {
      cancelled = true;
    };
  }, [isShopUser]);

  const performance: { label: string; value: ReactNode; colour: string }[] = [];
  if (data?.readyToList != null) performance.push({ label: "Ready to List", value: data.readyToList, colour: "var(--accent-info)" });
  if (data?.activeFixedPrice != null) performance.push({ label: "Active Fixed Price Items", value: data.activeFixedPrice, colour: "var(--accent-live)" });
  if (data?.activeAuctions != null) performance.push({ label: "Active Auction Items", value: data.activeAuctions, colour: "var(--accent-auction)" });
  if (data?.scheduledAuctions != null) performance.push({ label: "Scheduled Auctions", value: data.scheduledAuctions, colour: "var(--accent-scheduled)" });
  if (data?.itemsSoldThisYear != null) performance.push({ label: "Items Sold — This Year", value: data.itemsSoldThisYear, colour: "var(--accent-attention)" });
  if (data?.salesValueThisYearMinor != null)
    performance.push({ label: "Sales Value — This Year", value: formatMoney(data.salesValueThisYearMinor), colour: "var(--price-fixed)" });

  const canAuctions = hasPermission(user, "auction.manage");
  const canUsers = hasPermission(user, "shop.users.view");
  const nothingToShow = data !== null && performance.length === 0 && data.auctions === null && data.activeUsers === null;

  return (
    <WorkspaceShell screenId="SCR-SHP-002">
      <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>
            Dashboard
          </h1>
          {data && (
            <p className="mt-1 text-sm" style={{ color: "var(--text-secondary)" }}>
              {data.shopName}
            </p>
          )}
        </div>
        <div className="flex items-center gap-4 text-xs" style={{ color: "var(--text-muted)" }}>
          <button
            type="button"
            onClick={load}
            disabled={busy}
            className="px-4 py-2 text-sm font-semibold disabled:opacity-50"
            style={{ border: "1px solid var(--border-default)", borderRadius: 4, background: "var(--surface-card)", color: "var(--accent-info)" }}
          >
            Refresh
          </button>
          {data && <span>Last updated: {new Date(data.asAt).toLocaleTimeString("en-ZA", { hour: "2-digit", minute: "2-digit" })}</span>}
        </div>
      </div>

      <ErrorNote message={error} />

      {!data && !error && <p className="text-sm" style={{ color: "var(--text-muted)" }}>Loading…</p>}

      {nothingToShow && (
        <Card title="Welcome">
          <p className="text-sm" style={{ color: "var(--text-secondary)" }}>
            Your account doesn&apos;t have access to any workspace sections yet. Ask your Shop Administrator to give you the permissions you need.
          </p>
        </Card>
      )}

      <div className="grid gap-6 xl:grid-cols-2">
        {performance.length > 0 && (
          <Card title="Shop Performance">
            <ul>
              {performance.map((row) => (
                <li
                  key={row.label}
                  className="flex items-center justify-between py-3"
                  style={{ borderBottom: "1px solid var(--border-subtle)" }}
                >
                  <span className="text-sm" style={{ color: "var(--text-primary)" }}>{row.label}</span>
                  <span className="font-display text-2xl font-bold tabular-nums" style={{ color: row.colour }}>{row.value}</span>
                </li>
              ))}
            </ul>
          </Card>
        )}

        {data?.auctions && (
          <Card
            title="Auctions Overview"
            action={canAuctions ? <Link href="/workspace/auctions" className="text-sm font-semibold hover:underline" style={{ color: "var(--accent-info)" }}>View all auctions</Link> : null}
          >
            {data.auctions.length === 0 ? (
              <p className="text-sm" style={{ color: "var(--text-muted)" }}>No live or scheduled auctions.</p>
            ) : (
              <ul>
                {data.auctions.map((a) => (
                  <li key={a.listingID} className="flex items-center gap-3 py-3" style={{ borderBottom: "1px solid var(--border-subtle)" }}>
                    <span
                      className="w-24 shrink-0 px-2 py-1 text-center text-[11px] font-bold uppercase"
                      style={{
                        borderRadius: 3,
                        background: a.state === "live" ? "var(--accent-live-bg)" : "var(--accent-scheduled-bg)",
                        color: a.state === "live" ? "var(--accent-live)" : "var(--accent-scheduled)",
                      }}
                    >
                      {a.state}
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-sm font-semibold" style={{ color: "var(--text-primary)" }}>{a.title}</span>
                      <span className="block text-xs" style={{ color: "var(--text-muted)" }}>
                        {a.reference} · {a.state === "live" ? `Closes ${when(a.endsAt)}` : `Opens ${when(a.startsAt)}`}
                      </span>
                    </span>
                    <span className="shrink-0 text-right">
                      <span className="block text-sm font-bold tabular-nums" style={{ color: "var(--text-primary)" }}>
                        {a.currentBidMinor != null ? formatMoney(a.currentBidMinor) : "—"}
                      </span>
                      <span className="block text-xs" style={{ color: "var(--text-muted)" }}>
                        {a.bidCount} {a.bidCount === 1 ? "bid" : "bids"}
                      </span>
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        )}

        {data?.activeUsers != null && (
          <Card
            title="Users"
            action={canUsers ? <Link href="/workspace/users" className="text-sm font-semibold hover:underline" style={{ color: "var(--accent-info)" }}>Users &amp; Permissions</Link> : null}
          >
            <div className="grid grid-cols-2 gap-4">
              <Stat label="Active users" value={data.activeUsers} />
              <Stat label="Invitations not yet accepted" value={data.pendingInvitations ?? 0} />
            </div>
          </Card>
        )}
      </div>
    </WorkspaceShell>
  );
}

function Card({ title, action, children }: { title: string; action?: ReactNode; children: ReactNode }) {
  return (
    <section
      // min-w-0: a long auction title truncates instead of widening the page on a phone
      className="min-w-0 p-5"
      style={{ background: "var(--surface-card)", border: "1px solid var(--border-subtle)", borderRadius: "var(--radius-card)", boxShadow: "var(--shadow-card)" }}
    >
      <div className="mb-2 flex items-center justify-between gap-3">
        <h2 className="font-display text-lg font-semibold" style={{ color: "var(--text-primary)" }}>{title}</h2>
        {action}
      </div>
      {children}
    </section>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="p-4" style={{ background: "var(--surface-sunken)", borderRadius: 4 }}>
      <p className="font-display text-3xl font-bold tabular-nums" style={{ color: "var(--text-primary)" }}>{value}</p>
      <p className="mt-1 text-xs" style={{ color: "var(--text-secondary)" }}>{label}</p>
    </div>
  );
}
