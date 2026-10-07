"use client";

import { useEffect, useState } from "react";
import { BuyerListRow } from "@/components/account/BuyerListRow";
import { BuyerOnly, Pager } from "@/components/account/BuyerOnly";
import { AccountShell } from "@/components/layout/AccountShell";
import { ErrorNote } from "@/components/ui/Form";
import { api, errorText, type BuyerListItem, type PagedResult } from "@/lib/api";
import { useSession } from "@/lib/session";

// SCR-PUB-008
export default function RecentlyViewedPage() {
  const session = useSession();
  const isBuyer = session?.user.actorKind === "Buy_Buyer";
  const [page, setPage] = useState(1);
  const [data, setData] = useState<PagedResult<BuyerListItem> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [version, setVersion] = useState(0);

  useEffect(() => {
    if (!isBuyer) return;
    let cancelled = false;
    api.account
      .recent(page)
      .then((d) => !cancelled && setData(d))
      .catch((e) => !cancelled && setError(errorText(e)));
    return () => {
      cancelled = true;
    };
  }, [isBuyer, page, version]);

  async function remove(listingId: string) {
    try {
      await api.account.removeRecent(listingId);
      setVersion((v) => v + 1);
    } catch (e) {
      setError(errorText(e));
    }
  }

  return (
    <AccountShell screenId="SCR-PUB-008">
      <h1 className="font-display text-4xl font-bold" style={{ color: "var(--philmart-navy)" }}>Recently Viewed Items</h1>
      <p className="mb-6 text-xs" style={{ color: "var(--text-secondary)" }}>
        Items you viewed most recently. Price, bid and availability information is shown live.
      </p>

      <BuyerOnly>
        <ErrorNote message={error} />

        <p className="mb-2 text-right text-[11px]" style={{ color: "var(--text-muted)" }}>Most recently viewed first</p>

        <div className="flex flex-col gap-2">
          {data?.items.map((item) => (
            <BuyerListRow key={item.listingID} item={item} atLabel="Last viewed" showTime onRemove={() => remove(item.listingID)} />
          ))}
        </div>

        {data && data.totalCount === 0 && (
          <p className="text-sm" style={{ color: "var(--text-secondary)" }}>Items you look at in the marketplace will show up here.</p>
        )}

        {data && <Pager data={data} onPage={setPage} />}
      </BuyerOnly>
    </AccountShell>
  );
}
