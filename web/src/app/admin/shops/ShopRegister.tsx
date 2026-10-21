"use client";

import { useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Card } from "@/components/ui/Card";
import { Badge } from "@/components/ui/Badge";
import {
  api,
  formatMoney,
  type AdminShop,
  type AdminShopQuery,
  type PagedResult,
  type ShopStatus,
} from "@/lib/api";
import { SHOP_STATUS_LABEL, SHOP_STATUS_TONE, adminErrorMessage, formatDate } from "@/lib/admin";

const PAGE_SIZE = 25;

const STATUSES = Object.keys(SHOP_STATUS_LABEL) as ShopStatus[];

// BR-21-R02
export function ShopRegister() {
  const params = useSearchParams();

  const [filter, setFilter] = useState<AdminShopQuery>(() => ({
    query: params.get("query") ?? "",
    status: toStatus(params.get("status")),
    overdueOnly: params.get("overdueOnly") === "true",
    page: 1,
    pageSize: PAGE_SIZE,
  }));
  const [search, setSearch] = useState(filter.query ?? "");
  const [data, setData] = useState<PagedResult<AdminShop> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [changing, setChanging] = useState<AdminShop | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [version, setVersion] = useState(0);

  useEffect(() => {
    let cancelled = false;

    api.admin
      .shops(filter)
      .then((res) => {
        if (cancelled) return;
        setData(res);
        setError(null);
      })
      .catch((e: unknown) => {
        if (cancelled) return;
        setError(adminErrorMessage(e, "Could not load the Shop register."));
      });

    return () => {
      cancelled = true;
    };
  }, [filter, version]);

  // any filter change goes back to page 1
  function update(change: Partial<AdminShopQuery>) {
    setFilter((f) => ({ ...f, ...change, page: change.page ?? 1 }));
  }

  return (
    <div className="flex flex-col gap-4">
      {notice && (
        <p className="px-3 py-2 text-sm" style={{ border: "1px solid var(--border-subtle)", borderRadius: 4, background: "var(--surface-card)", color: "var(--text-primary)" }}>
          {notice}
        </p>
      )}

      {changing && (
        <StatusDialog
          shop={changing}
          onClose={() => setChanging(null)}
          onDone={(message) => {
            setChanging(null);
            setNotice(message);
            setVersion((v) => v + 1);
          }}
        />
      )}

      <form
        className="flex flex-wrap items-end gap-3"
        onSubmit={(e) => {
          e.preventDefault();
          update({ query: search.trim() });
        }}
      >
        <label className="flex min-w-0 flex-1 basis-60 flex-col gap-1 text-xs font-semibold" style={{ color: "var(--text-secondary)" }}>
          Search
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Trading name, legal name or reference"
            style={inputStyle}
          />
        </label>

        <label className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--text-secondary)" }}>
          Status
          <select
            value={filter.status ?? ""}
            onChange={(e) => update({ status: toStatus(e.target.value) })}
            style={inputStyle}
          >
            <option value="">All statuses</option>
            {STATUSES.map((s) => (
              <option key={s} value={s}>
                {SHOP_STATUS_LABEL[s]}
              </option>
            ))}
          </select>
        </label>

        <label className="flex items-center gap-2 pb-2 text-sm" style={{ color: "var(--text-secondary)" }}>
          <input
            type="checkbox"
            checked={filter.overdueOnly ?? false}
            onChange={(e) => update({ overdueOnly: e.target.checked })}
          />
          Overdue fees only
        </label>

        <button
          type="submit"
          className="px-4 py-2 text-sm font-bold"
          style={{ background: "var(--philmart-navy-deep)", color: "#ffffff", borderRadius: 4 }}
        >
          Search
        </button>
      </form>

      {error ? (
        <Card>
          <p className="text-sm" style={{ color: "var(--accent-danger)" }}>
            {error}
          </p>
        </Card>
      ) : !data ? (
        <p className="text-sm" style={{ color: "var(--text-muted)" }}>
          Loading…
        </p>
      ) : data.items.length === 0 ? (
        <Card>
          <p className="text-sm" style={{ color: "var(--text-secondary)" }}>
            No Shops match these filters.
          </p>
        </Card>
      ) : (
        <>
          <div
            className="overflow-x-auto"
            style={{
              background: "var(--surface-card)",
              border: "1px solid var(--border-subtle)",
              borderRadius: "var(--radius-card)",
            }}
          >
            <table className="w-full min-w-[900px] text-left text-sm">
              <thead>
                <tr style={{ background: "var(--surface-sunken)", color: "var(--text-secondary)" }}>
                  <Th>Shop</Th>
                  <Th>Status</Th>
                  <Th>Activated</Th>
                  <Th>Deactivated</Th>
                  <Th>Reactivated</Th>
                  <Th right>Live listings</Th>
                  <Th right>Fees outstanding</Th>
                  <Th right>Overdue</Th>
                  <Th>Actions</Th>
                </tr>
              </thead>
              <tbody>
                {data.items.map((shop) => (
                  <tr key={shop.id} style={{ borderTop: "1px solid var(--border-subtle)" }}>
                    <Td>
                      <div className="font-semibold" style={{ color: "var(--text-primary)" }}>
                        {shop.tradingName}
                      </div>
                      <div className="font-mono text-xs" style={{ color: "var(--text-muted)" }}>
                        {shop.reference}
                        {shop.legalEntityName ? ` · ${shop.legalEntityName}` : ""}
                      </div>
                    </Td>
                    <Td>
                      <Badge tone={SHOP_STATUS_TONE[shop.status]}>
                        {SHOP_STATUS_LABEL[shop.status]}
                      </Badge>
                    </Td>
                    <Td>{formatDate(shop.activatedAt)}</Td>
                    <Td>
                      {formatDate(shop.deactivatedAt)}
                      {shop.status === "deactivated" && shop.deactivationReason && (
                        <div className="max-w-[240px] text-xs" style={{ color: "var(--text-muted)" }}>
                          {shop.deactivationReason}
                        </div>
                      )}
                    </Td>
                    <Td>{formatDate(shop.reactivatedAt)}</Td>
                    <Td right>{shop.liveListingCount}</Td>
                    <Td right>{formatMoney(shop.feesOutstandingMinor)}</Td>
                    <Td right>
                      {shop.hasOverdueFees ? (
                        <span className="font-semibold" style={{ color: "var(--accent-danger)" }}>
                          {formatMoney(shop.feesOverdueMinor)}
                        </span>
                      ) : (
                        "—"
                      )}
                    </Td>
                    <Td>
                      {(shop.status === "active" || shop.status === "deactivated") && (
                        <button
                          type="button"
                          className="text-xs font-semibold hover:underline"
                          style={{ color: shop.status === "active" ? "var(--accent-danger)" : "var(--accent-live)" }}
                          onClick={() => {
                            setNotice(null);
                            setChanging(shop);
                          }}
                        >
                          {shop.status === "active" ? "Deactivate" : "Reactivate"}
                        </button>
                      )}
                    </Td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="flex items-center justify-between text-sm" style={{ color: "var(--text-secondary)" }}>
            <span>
              {data.totalCount} {data.totalCount === 1 ? "Shop" : "Shops"} · page {data.page} of{" "}
              {Math.max(data.totalPages, 1)}
            </span>
            <div className="flex gap-2">
              <PageButton disabled={!data.hasPrevious} onClick={() => update({ page: data.page - 1 })}>
                Previous
              </PageButton>
              <PageButton disabled={!data.hasNext} onClick={() => update({ page: data.page + 1 })}>
                Next
              </PageButton>
            </div>
          </div>
        </>
      )}
    </div>
  );
}

// D031: deactivating is a deliberate admin act with a recorded reason. D032:
// auctions that already have bids still run to the end.
function StatusDialog({ shop, onClose, onDone }: { shop: AdminShop; onClose: () => void; onDone: (message: string) => void }) {
  const deactivate = shop.status === "active";
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      if (deactivate) await api.admin.deactivateShop(shop.id, reason);
      else await api.admin.reactivateShop(shop.id, reason);
      onDone(`${shop.tradingName} has been ${deactivate ? "deactivated" : "reactivated"}.`);
    } catch (err) {
      setError(adminErrorMessage(err, "That didn't work. Please try again."));
      setBusy(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto p-4" style={{ background: "rgb(15 23 42 / 0.5)" }} role="dialog" aria-modal="true">
      <form onSubmit={submit} className="mt-16 w-full max-w-lg p-6" style={{ background: "var(--surface-card)", borderRadius: "var(--radius-card)" }}>
        <h2 className="font-display text-xl font-bold" style={{ color: "var(--text-primary)" }}>
          {deactivate ? "Deactivate" : "Reactivate"} {shop.tradingName}
        </h2>
        <p className="mb-4 mt-1 text-xs" style={{ color: "var(--text-secondary)" }}>
          {deactivate
            ? "The Shop stops taking new Buy Now purchases and bids straight away. Auctions that already have bids run to their end. The reason is kept in the audit history."
            : "The Shop can sell again straight away. The reason is kept in the audit history."}
        </p>

        {error && (
          <p role="alert" className="mb-3 px-3 py-2 text-sm" style={{ color: "var(--accent-danger)", border: "1px solid var(--accent-danger)", borderRadius: 4 }}>
            {error}
          </p>
        )}

        <label className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--text-secondary)" }}>
          Reason *
          <textarea required rows={3} maxLength={1000} value={reason} onChange={(e) => setReason(e.target.value)} style={inputStyle} />
        </label>

        <div className="mt-5 flex justify-end gap-3">
          <button type="button" onClick={onClose} className="px-4 py-2 text-sm font-semibold" style={{ border: "1px solid var(--border-default)", borderRadius: 4, color: "var(--text-primary)" }}>
            Cancel
          </button>
          <button
            type="submit"
            disabled={busy || reason.trim().length === 0}
            className="px-4 py-2 text-sm font-bold disabled:opacity-40"
            style={{ background: deactivate ? "var(--accent-danger)" : "var(--philmart-navy-deep)", color: "#ffffff", borderRadius: 4 }}
          >
            {deactivate ? "Deactivate Shop" : "Reactivate Shop"}
          </button>
        </div>
      </form>
    </div>
  );
}

function toStatus(value: string | null): ShopStatus | "" {
  return value && (STATUSES as string[]).includes(value) ? (value as ShopStatus) : "";
}

const inputStyle: React.CSSProperties = {
  padding: "0.5rem 0.75rem",
  background: "var(--surface-card)",
  border: "1px solid var(--border-default)",
  borderRadius: 4,
  color: "var(--text-primary)",
  fontWeight: 400,
};

function Th({ children, right = false }: { children: React.ReactNode; right?: boolean }) {
  return (
    <th className={`px-4 py-3 text-xs font-semibold ${right ? "text-right" : ""}`}>{children}</th>
  );
}

function Td({ children, right = false }: { children: React.ReactNode; right?: boolean }) {
  return (
    <td
      className={`px-4 py-3 align-top ${right ? "text-right tabular-nums" : ""}`}
      style={{ color: "var(--text-secondary)" }}
    >
      {children}
    </td>
  );
}

function PageButton({
  children,
  disabled,
  onClick,
}: {
  children: React.ReactNode;
  disabled: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className="px-3 py-1.5 text-sm font-semibold disabled:opacity-40"
      style={{ border: "1px solid var(--border-default)", borderRadius: 4, color: "var(--text-primary)" }}
    >
      {children}
    </button>
  );
}
