"use client";

import { useEffect, useState, useCallback } from "react";
import { PublicHeader, PublicFooter } from "@/components/layout/PublicHeader";
import { ItemCard, ItemRow } from "@/components/marketplace/ItemCard";
import {
  api,
  type MarketplaceItem,
  type MarketplaceQuery,
  type PagedResult,
} from "@/lib/api";

type ViewMode = "grid" | "list";

// the view toggle only changes how we render data.items, never the request
export default function MarketplacePage() {
  const [view, setView] = useState<ViewMode>("grid");
  const [filter, setFilter] = useState<MarketplaceQuery>({ page: 1, pageSize: 10 });
  const [data, setData] = useState<PagedResult<MarketplaceItem> | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // bumping this refetches with the same filter, the retry button uses it
  const [attempt, setAttempt] = useState(0);
  const reload = useCallback(() => {
    setLoading(true);
    setAttempt((n) => n + 1);
  }, []);

  useEffect(() => {
    let cancelled = false;

    // only set state in the callbacks, React 19 complains if the effect sets it directly
    api.marketplace
      .browse(filter)
      .then((res) => {
        if (cancelled) return;
        setData(res);
        setError(null);
      })
      .catch((e: unknown) => {
        if (cancelled) return;
        setError(e instanceof Error ? e.message : "Could not load the marketplace.");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [filter, attempt]);

  const update = (patch: Partial<MarketplaceQuery>) => {
    setLoading(true);
    setFilter((current) => ({ ...current, ...patch, page: patch.page ?? 1 }));
  };

  return (
    <div className="flex min-h-screen flex-col" style={{ background: "var(--surface-marketplace)" }}>
      <PublicHeader />

      <main className="mx-auto w-full max-w-[1400px] flex-1 px-4 py-6">
        <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 className="font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>
              Marketplace
            </h1>
            <p className="mt-1 text-sm" style={{ color: "var(--text-secondary)" }}>
              Browse Buy Now and Auction Items together.
            </p>
          </div>

          <div className="flex w-full max-w-xl gap-2">
            <input
              type="search"
              placeholder="Search by item title or description..."
              defaultValue={filter.query ?? ""}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  update({ query: (e.target as HTMLInputElement).value });
                }
              }}
              className="flex-1 px-4 py-2.5 text-sm"
              style={{
                background: "var(--surface-card)",
                border: "1px solid var(--border-default)",
                borderRadius: "var(--radius-card)",
                color: "var(--text-primary)",
              }}
            />
            <button
              type="button"
              onClick={reload}
              className="px-6 py-2.5 text-sm font-semibold"
              style={{
                background: "var(--philmart-navy)",
                color: "var(--text-inverse)",
                borderRadius: "var(--radius-card)",
              }}
            >
              Search
            </button>
          </div>
        </div>

        <FilterBar filter={filter} onChange={update} />

        <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
          <p className="text-sm" style={{ color: "var(--text-secondary)" }}>
            {loading ? "Loading…" : `${data?.totalCount.toLocaleString() ?? 0} Items found`}
          </p>

          <div className="flex items-center gap-3">
            <label className="flex items-center gap-2 text-sm" style={{ color: "var(--text-secondary)" }}>
              Sort by:
              <select
                value={filter.sort ?? "newest"}
                onChange={(e) => update({ sort: e.target.value })}
                className="px-3 py-1.5 text-sm"
                style={{
                  background: "var(--surface-card)",
                  border: "1px solid var(--border-default)",
                  borderRadius: 4,
                  color: "var(--text-primary)",
                }}
              >
                <option value="newest">Newest Listed</option>
                <option value="price_asc">Price: low to high</option>
                <option value="price_desc">Price: high to low</option>
                <option value="ending">Ending soonest</option>
              </select>
            </label>

            <div
              className="flex overflow-hidden"
              role="group"
              aria-label="View mode"
              style={{ border: "1px solid var(--border-default)", borderRadius: 4 }}
            >
              {(["grid", "list"] as ViewMode[]).map((mode) => (
                <button
                  key={mode}
                  type="button"
                  onClick={() => setView(mode)}
                  aria-pressed={view === mode}
                  className="px-4 py-1.5 text-sm font-medium capitalize"
                  style={{
                    background: view === mode ? "var(--philmart-navy)" : "var(--surface-card)",
                    color: view === mode ? "var(--text-inverse)" : "var(--text-secondary)",
                  }}
                >
                  {mode} View
                </button>
              ))}
            </div>
          </div>
        </div>

        {error && (
          <div
            className="mb-4 p-4 text-sm"
            style={{
              background: "var(--accent-danger-bg)",
              color: "var(--accent-danger)",
              borderRadius: "var(--radius-card)",
            }}
          >
            {error}
          </div>
        )}

        {loading ? (
          <SkeletonGrid />
        ) : view === "grid" ? (
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
            {data?.items.map((item) => (
              <ItemCard key={item.listingID} item={item} />
            ))}
          </div>
        ) : (
          <div className="flex flex-col gap-3">
            {data?.items.map((item) => (
              <ItemRow key={item.listingID} item={item} />
            ))}
          </div>
        )}

        {data && data.totalPages > 1 && (
          <Pagination
            page={data.page}
            totalPages={data.totalPages}
            onPage={(page) => update({ page })}
          />
        )}
      </main>

      <PublicFooter screenId={view === "grid" ? "SCR-PUB-002A" : "SCR-PUB-002B"} />
    </div>
  );
}

function FilterBar({
  filter,
  onChange,
}: {
  filter: MarketplaceQuery;
  onChange: (patch: Partial<MarketplaceQuery>) => void;
}) {
  return (
    <div
      className="mb-5 grid grid-cols-2 gap-3 p-4 md:grid-cols-4 lg:grid-cols-8"
      style={{
        background: "var(--surface-card)",
        border: "1px solid var(--border-subtle)",
        borderRadius: "var(--radius-card)",
      }}
    >
      <Field label="Selling Method">
        <select
          value={filter.sellingMethod ?? "All"}
          onChange={(e) => onChange({ sellingMethod: e.target.value })}
          className="w-full px-2 py-1.5 text-sm"
          style={{
            background: "var(--surface-card)",
            border: "1px solid var(--border-default)",
            borderRadius: 4,
            color: "var(--text-primary)",
          }}
        >
          <option value="All">All</option>
          <option value="fixed_price">Buy Now</option>
          <option value="auction">Auction</option>
        </select>
      </Field>

      {/* subtype, format and stamp state cascade off type */}
      {["Area / Country", "Type", "Subtype", "Format", "Stamp State", "Theme", "Shop"].map(
        (label) => (
          <Field key={label} label={label}>
            <select
              disabled
              className="w-full px-2 py-1.5 text-sm"
              style={{
                background: "var(--surface-sunken)",
                border: "1px solid var(--border-subtle)",
                borderRadius: 4,
                color: "var(--text-muted)",
              }}
            >
              <option>Select one or more...</option>
            </select>
          </Field>
        ),
      )}
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="flex flex-col gap-1">
      <span className="text-[11px] font-semibold" style={{ color: "var(--text-secondary)" }}>
        {label}
      </span>
      {children}
    </label>
  );
}

function SkeletonGrid() {
  return (
    <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5">
      {Array.from({ length: 10 }).map((_, index) => (
        <div
          key={index}
          className="animate-pulse"
          style={{
            background: "var(--surface-sunken)",
            borderRadius: "var(--radius-card)",
            height: 280,
          }}
        />
      ))}
    </div>
  );
}

function Pagination({
  page,
  totalPages,
  onPage,
}: {
  page: number;
  totalPages: number;
  onPage: (page: number) => void;
}) {
  const window = 5;
  const start = Math.max(1, Math.min(page - 2, totalPages - window + 1));
  const pages = Array.from({ length: Math.min(window, totalPages) }, (_, i) => start + i);

  const button = (label: string, target: number, disabled = false, active = false) => (
    <button
      key={`${label}-${target}`}
      type="button"
      disabled={disabled}
      onClick={() => onPage(target)}
      className="min-w-9 px-3 py-1.5 text-sm font-medium disabled:opacity-40"
      style={{
        background: active ? "var(--philmart-navy)" : "var(--surface-card)",
        color: active ? "var(--text-inverse)" : "var(--text-secondary)",
        border: "1px solid var(--border-default)",
        borderRadius: 4,
      }}
    >
      {label}
    </button>
  );

  return (
    <nav className="mt-8 flex justify-center gap-1" aria-label="Pagination">
      {button("«", 1, page === 1)}
      {button("‹", page - 1, page === 1)}
      {pages.map((p) => button(String(p), p, false, p === page))}
      {totalPages > start + window - 1 && (
        <span className="px-2 py-1.5 text-sm" style={{ color: "var(--text-muted)" }}>
          …
        </span>
      )}
      {totalPages > start + window - 1 && button(String(totalPages), totalPages)}
      {button("›", page + 1, page === totalPages)}
      {button("»", totalPages, page === totalPages)}
    </nav>
  );
}
