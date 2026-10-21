"use client";

import { Suspense, useEffect, useState, useCallback } from "react";
import { useSearchParams } from "next/navigation";
import { PublicHeader, PublicFooter } from "@/components/layout/PublicHeader";
import { ItemCard, ItemRow } from "@/components/marketplace/ItemCard";
import {
  api,
  type ClassificationOption,
  type MarketplaceItem,
  type MarketplaceQuery,
  type PagedResult,
} from "@/lib/api";

type ViewMode = "grid" | "list";

// every filter can come in on the url, e.g. a link to one shop's items
const FILTER_KEYS = [
  "query",
  "sellingMethod",
  "areaCountryId",
  "typeId",
  "subtypeId",
  "formatId",
  "stampStateId",
  "themeId",
  "shopId",
  "sort",
] as const;

// links like /marketplace?sellingMethod=auction&sort=ending start pre-filtered.
// useSearchParams needs a Suspense boundary or the static build bails out
export default function MarketplacePage() {
  return (
    <Suspense>
      <MarketplaceFromUrl />
    </Suspense>
  );
}

function MarketplaceFromUrl() {
  const params = useSearchParams();
  const initial: MarketplaceQuery = { page: 1, pageSize: 10 };
  for (const key of FILTER_KEYS) {
    const value = params.get(key);
    if (value) initial[key] = value;
  }

  // remount when the url changes, e.g. clicking Auctions in the header while already here
  return <Marketplace key={params.toString()} initial={initial} />;
}

// the view toggle only changes how we render data.items, never the request
function Marketplace({ initial }: { initial: MarketplaceQuery }) {
  const [view, setView] = useState<ViewMode>("grid");
  const [filter, setFilter] = useState<MarketplaceQuery>(initial);
  const [searchText, setSearchText] = useState(initial.query ?? "");
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
              aria-label="Search the marketplace"
              placeholder="Search by item title or description..."
              value={searchText}
              onChange={(e) => setSearchText(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") update({ query: searchText.trim() || undefined });
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
              onClick={() => {
                // same text again just refreshes the results
                if ((searchText.trim() || undefined) === filter.query) reload();
                else update({ query: searchText.trim() || undefined });
              }}
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

        <FilterBar
          filter={filter}
          onChange={update}
          onClear={() => {
            setSearchText("");
            setLoading(true);
            setFilter({ page: 1, pageSize: filter.pageSize, sort: filter.sort });
          }}
        />

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

type FilterOptions = {
  areas: { id: string; label: string }[];
  types: ClassificationOption[];
  formats: ClassificationOption[];
  stampStates: ClassificationOption[];
  themes: ClassificationOption[];
  shops: ClassificationOption[];
};

// regions first with their countries indented under them, so picking a
// region (which also matches its countries) reads naturally
function areaTree(all: ClassificationOption[]) {
  const children = new Map<string | null, ClassificationOption[]>();
  for (const area of all) {
    const parent = area.parentID ?? null;
    children.set(parent, [...(children.get(parent) ?? []), area]);
  }

  const out: { id: string; label: string }[] = [];
  const walk = (parent: string | null, depth: number) => {
    for (const area of children.get(parent) ?? []) {
      out.push({ id: area.id, label: "   ".repeat(depth) + area.name });
      walk(area.id, depth + 1);
    }
  };
  walk(null, 0);
  return out;
}

const selectStyle = {
  background: "var(--surface-card)",
  border: "1px solid var(--border-default)",
  borderRadius: 4,
  color: "var(--text-primary)",
};

function FilterBar({
  filter,
  onChange,
  onClear,
}: {
  filter: MarketplaceQuery;
  onChange: (patch: Partial<MarketplaceQuery>) => void;
  onClear: () => void;
}) {
  const [options, setOptions] = useState<FilterOptions | null>(null);
  const [subtypes, setSubtypes] = useState<ClassificationOption[]>([]);

  useEffect(() => {
    let cancelled = false;
    Promise.all([
      api.marketplace.areaCountries(),
      api.marketplace.types(),
      api.marketplace.formats(),
      api.marketplace.stampStates(),
      api.marketplace.themes(),
      api.marketplace.shops(),
    ])
      .then(([areas, types, formats, stampStates, themes, shops]) => {
        if (!cancelled) setOptions({ areas: areaTree(areas), types, formats, stampStates, themes, shops });
      })
      // the filters just stay empty, browsing still works
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    const load = filter.typeId ? api.marketplace.subtypes(filter.typeId) : Promise.resolve([]);
    load.then((s) => !cancelled && setSubtypes(s)).catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [filter.typeId]);

  const active = FILTER_KEYS.some((key) => key !== "sort" && filter[key]);

  const pick = (label: string, value: string | undefined, list: { id: string; label: string }[], set: (v: string | undefined) => void, disabled = false) => (
    <Field label={label}>
      <select
        value={value ?? ""}
        disabled={disabled || !options}
        onChange={(e) => set(e.target.value || undefined)}
        className="w-full px-2 py-1.5 text-sm disabled:opacity-50"
        style={selectStyle}
      >
        <option value="">All</option>
        {list.map((o) => (
          <option key={o.id} value={o.id}>
            {o.label}
          </option>
        ))}
      </select>
    </Field>
  );

  const named = (list: ClassificationOption[] | undefined) => (list ?? []).map((o) => ({ id: o.id, label: o.name }));

  return (
    <div
      className="mb-5 p-4"
      style={{
        background: "var(--surface-card)",
        border: "1px solid var(--border-subtle)",
        borderRadius: "var(--radius-card)",
      }}
    >
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4 lg:grid-cols-8">
        <Field label="Selling Method">
          <select
            value={filter.sellingMethod ?? ""}
            onChange={(e) => onChange({ sellingMethod: e.target.value || undefined })}
            className="w-full px-2 py-1.5 text-sm"
            style={selectStyle}
          >
            <option value="">All</option>
            <option value="fixed_price">Buy Now</option>
            <option value="auction">Auction</option>
          </select>
        </Field>

        {pick("Area / Country", filter.areaCountryId, options?.areas ?? [], (v) => onChange({ areaCountryId: v }))}
        {/* subtype belongs to a type, so changing type clears it */}
        {pick("Type", filter.typeId, named(options?.types), (v) => onChange({ typeId: v, subtypeId: undefined }))}
        {pick("Subtype", filter.subtypeId, named(subtypes), (v) => onChange({ subtypeId: v }), !filter.typeId)}
        {pick("Format", filter.formatId, named(options?.formats), (v) => onChange({ formatId: v }))}
        {pick("Stamp State", filter.stampStateId, named(options?.stampStates), (v) => onChange({ stampStateId: v }))}
        {pick("Theme", filter.themeId, named(options?.themes), (v) => onChange({ themeId: v }))}
        {pick("Shop", filter.shopId, named(options?.shops), (v) => onChange({ shopId: v }))}
      </div>

      {active && (
        <div className="mt-3 flex justify-end">
          <button
            type="button"
            onClick={onClear}
            className="text-xs font-semibold hover:underline"
            style={{ color: "var(--accent-info)" }}
          >
            Clear filters
          </button>
        </div>
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
    <nav className="mt-8 flex flex-wrap justify-center gap-1" aria-label="Pagination">
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
