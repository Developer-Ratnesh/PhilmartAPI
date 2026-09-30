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
  }, [filter]);

  // any filter change goes back to page 1
  function update(change: Partial<AdminShopQuery>) {
    setFilter((f) => ({ ...f, ...change, page: change.page ?? 1 }));
  }

  return (
    <div className="flex flex-col gap-4">
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
