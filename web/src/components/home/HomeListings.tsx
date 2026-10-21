"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { ItemCard } from "@/components/marketplace/ItemCard";
import { api, type MarketplaceItem, type PagedResult } from "@/lib/api";

type HomeData = {
  recent: PagedResult<MarketplaceItem>;
  ending: PagedResult<MarketplaceItem>;
};

// public marketplace data only, the browse endpoint needs no login
export function HomeListings() {
  const [data, setData] = useState<HomeData | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let cancelled = false;

    Promise.all([
      api.marketplace.browse({ sort: "newest", pageSize: 5 }),
      api.marketplace.browse({ sellingMethod: "auction", sort: "ending", pageSize: 5 }),
    ])
      .then(([recent, ending]) => {
        if (!cancelled) setData({ recent, ending });
      })
      .catch(() => {
        if (!cancelled) setFailed(true);
      });

    return () => {
      cancelled = true;
    };
  }, []);

  // the rest of the home page still works without the API, so just drop this section
  if (failed) return null;

  return (
    <>
      <Strip
        title="Recently Listed"
        intro="The latest items added by our Shops and Clubs."
        href="/marketplace?sort=newest"
        cta="View all"
        tone="live"
        items={data?.recent.items}
        empty="No items have been listed yet."
      />

      <Strip
        title="Auctions Ending Soon"
        intro="Auctions closing soon. Place your bid before time runs out."
        href="/marketplace?sellingMethod=auction&sort=ending"
        cta="View all auctions"
        tone="auction"
        items={data?.ending.items}
        empty="There are no open auctions right now."
      />
    </>
  );
}

function Strip({
  title,
  intro,
  href,
  cta,
  tone,
  items,
  empty,
}: {
  title: string;
  intro: string;
  href: string;
  cta: string;
  tone: "live" | "auction";
  items: MarketplaceItem[] | undefined;
  empty: string;
}) {
  const colour = tone === "live" ? "var(--accent-live)" : "var(--accent-auction)";

  return (
    <section className="mt-10">
      <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="font-display text-xl font-bold" style={{ color: colour }}>
            {title}
          </h2>
          <p className="mt-0.5 text-sm" style={{ color: "var(--text-secondary)" }}>
            {intro}
          </p>
        </div>
        <Link
          href={href}
          className="px-4 py-2 text-xs font-bold uppercase tracking-wide"
          style={{ background: colour, color: "#ffffff", borderRadius: 3 }}
        >
          {cta}
        </Link>
      </div>

      {items === undefined ? (
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
          {Array.from({ length: 5 }).map((_, index) => (
            <div
              key={index}
              className="animate-pulse"
              style={{ background: "var(--surface-sunken)", borderRadius: "var(--radius-card)", height: 280 }}
            />
          ))}
        </div>
      ) : items.length === 0 ? (
        <p
          className="p-6 text-center text-sm"
          style={{
            background: "var(--surface-card)",
            border: "1px dashed var(--border-default)",
            borderRadius: "var(--radius-card)",
            color: "var(--text-muted)",
          }}
        >
          {empty}
        </p>
      ) : (
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
          {items.map((item) => (
            <ItemCard key={item.listingID} item={item} />
          ))}
        </div>
      )}
    </section>
  );
}
