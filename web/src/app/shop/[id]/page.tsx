"use client";

import { useParams, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState } from "react";
import { PublicFooter, PublicHeader } from "@/components/layout/PublicHeader";
import { ItemCard, ItemRow } from "@/components/marketplace/ItemCard";
import { Pagination } from "@/components/marketplace/Pagination";
import { ErrorNote, Notice } from "@/components/ui/Form";
import { api, errorText, type MarketplaceItem, type PagedResult, type ShopProfile } from "@/lib/api";

type ViewMode = "grid" | "list";

// Grid 5x2 per the approved SCR-PUB-011, the list view shows the same page
const PAGE_SIZE = 10;

// useSearchParams needs a Suspense boundary or the static build bails out
export default function StorefrontPage() {
  return (
    <Suspense>
      <Storefront />
    </Suspense>
  );
}

// SCR-PUB-011 Storefront. BR-02-R05: profile plus live listings only.
function Storefront() {
  const { id } = useParams<{ id: string }>();
  const params = useSearchParams();
  const urlPage = Number(params.get("page"));

  // V41-MKT-04: page and view are kept in the url, so Back from an item lands here again
  const [page, setPage] = useState(Number.isInteger(urlPage) && urlPage > 1 ? urlPage : 1);
  const [view, setView] = useState<ViewMode>(params.get("view") === "list" ? "list" : "grid");
  const [profile, setProfile] = useState<ShopProfile | null>(null);
  const [data, setData] = useState<PagedResult<MarketplaceItem> | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    api.marketplace
      .shop(id)
      .then((p) => !cancelled && setProfile(p))
      .catch((e) => !cancelled && setError(errorText(e, "This Shop couldn't be found.")));
    return () => {
      cancelled = true;
    };
  }, [id]);

  useEffect(() => {
    let cancelled = false;
    api.marketplace
      .storefront(id, page, PAGE_SIZE)
      .then((res) => !cancelled && setData(res))
      .catch((e) => !cancelled && setError(errorText(e)));
    return () => {
      cancelled = true;
    };
  }, [id, page]);

  useEffect(() => {
    const out = new URLSearchParams();
    if (page > 1) out.set("page", String(page));
    if (view !== "grid") out.set("view", view);
    const search = out.toString();
    if (search === window.location.search.replace(/^\?/, "")) return;
    window.history.replaceState(window.history.state, "", search ? `?${search}` : window.location.pathname);
  }, [page, view]);

  return (
    <div className="flex min-h-screen flex-col" style={{ background: "var(--surface-marketplace)" }}>
      <PublicHeader />
      <main className="mx-auto w-full max-w-[1400px] flex-1 px-4 py-8">
        <ErrorNote message={error} />

        {profile && (
          <>
            <h1 className="font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>{profile.name}</h1>
            <p className="mb-2 text-xs" style={{ color: "var(--text-muted)" }}>Approved PHILMART Shop / Club · {profile.reference}</p>
            {profile.blurb && <p className="mb-4 max-w-3xl text-sm" style={{ color: "var(--text-secondary)" }}>{profile.blurb}</p>}

            {/* D032 */}
            {!profile.active && <Notice>This Shop isn&apos;t trading at the moment.</Notice>}

            {data && data.totalCount > 0 && (
              <div className="mb-4 mt-6 flex flex-wrap items-center justify-between gap-3">
                <p className="text-sm" style={{ color: "var(--text-secondary)" }}>
                  {data.totalCount.toLocaleString()} {data.totalCount === 1 ? "Item" : "Items"} listed
                </p>
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
            )}

            {data && view === "grid" && (
              <div className="grid grid-cols-2 gap-4 md:grid-cols-3 xl:grid-cols-5">
                {data.items.map((item) => (
                  <ItemCard key={item.listingID} item={item} />
                ))}
              </div>
            )}

            {data && view === "list" && (
              <div className="flex flex-col gap-3">
                {data.items.map((item) => (
                  <ItemRow key={item.listingID} item={item} />
                ))}
              </div>
            )}

            {data && data.totalPages > 1 && <Pagination page={data.page} totalPages={data.totalPages} onPage={setPage} />}

            {profile.active && data?.totalCount === 0 && <Notice>Nothing listed right now.</Notice>}
          </>
        )}
      </main>
      <PublicFooter screenId="SCR-PUB-011" />
    </div>
  );
}
