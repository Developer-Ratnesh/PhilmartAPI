"use client";

import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { PublicFooter, PublicHeader } from "@/components/layout/PublicHeader";
import { ItemCard } from "@/components/marketplace/ItemCard";
import { ErrorNote, Notice } from "@/components/ui/Form";
import { api, errorText, type MarketplaceItem, type ShopProfile } from "@/lib/api";

// SCR-PUB-011 Storefront. BR-02-R05: profile plus live listings only.
export default function StorefrontPage() {
  const { id } = useParams<{ id: string }>();
  const [profile, setProfile] = useState<ShopProfile | null>(null);
  const [items, setItems] = useState<MarketplaceItem[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    Promise.all([api.marketplace.shop(id), api.marketplace.storefront(id, 1, 50)])
      .then(([p, page]) => {
        if (cancelled) return;
        setProfile(p);
        setItems(page.items);
      })
      .catch((e) => !cancelled && setError(errorText(e, "This Shop couldn't be found.")));
    return () => {
      cancelled = true;
    };
  }, [id]);

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

            <div className="mt-6 grid grid-cols-2 gap-4 md:grid-cols-3 xl:grid-cols-5">
              {items.map((item) => (
                <ItemCard key={item.listingID} item={item} />
              ))}
            </div>

            {profile.active && items.length === 0 && <Notice>Nothing listed right now.</Notice>}
          </>
        )}
      </main>
      <PublicFooter screenId="SCR-PUB-011" />
    </div>
  );
}
