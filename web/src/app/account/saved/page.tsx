"use client";

import { useEffect, useState } from "react";
import { BuyerListRow } from "@/components/account/BuyerListRow";
import { BuyerOnly, Pager } from "@/components/account/BuyerOnly";
import { AccountShell } from "@/components/layout/AccountShell";
import { ErrorNote, inputStyle } from "@/components/ui/Form";
import { api, errorText, type BuyerListItem, type PagedResult } from "@/lib/api";
import { useSession } from "@/lib/session";

// SCR-PUB-009
export default function SavedItemsPage() {
  const session = useSession();
  const isBuyer = session?.user.actorKind === "Buy_Buyer";
  const [search, setSearch] = useState("");
  const [applied, setApplied] = useState("");
  const [page, setPage] = useState(1);
  const [data, setData] = useState<PagedResult<BuyerListItem> | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [version, setVersion] = useState(0);

  useEffect(() => {
    if (!isBuyer) return;
    let cancelled = false;
    api.account
      .saved(applied, page)
      .then((d) => !cancelled && setData(d))
      .catch((e) => !cancelled && setError(errorText(e)));
    return () => {
      cancelled = true;
    };
  }, [isBuyer, applied, page, version]);

  async function remove(listingId: string) {
    try {
      await api.account.removeSaved(listingId);
      setVersion((v) => v + 1);
    } catch (e) {
      setError(errorText(e));
    }
  }

  return (
    <AccountShell screenId="SCR-PUB-009">
      <h1 className="font-display text-4xl font-bold" style={{ color: "var(--philmart-navy)" }}>Saved Items</h1>
      <p className="mb-6 text-xs" style={{ color: "var(--text-secondary)" }}>
        Items you have saved for later. Live price, bid and availability information is shown.
      </p>

      <BuyerOnly>
        <form
          className="mb-4 flex flex-wrap items-center gap-3"
          onSubmit={(e) => {
            e.preventDefault();
            setPage(1);
            setApplied(search.trim());
          }}
        >
          <input
            aria-label="Search saved items"
            placeholder="Search Short Title or Item Number"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={{ ...inputStyle, maxWidth: 600 }}
          />
          <button type="submit" className="px-6 py-2.5 text-sm font-bold text-white" style={{ background: "var(--philmart-navy-deep)", borderRadius: 4 }}>
            Search
          </button>
          {data && (
            <span className="ml-auto text-xs" style={{ color: "var(--text-secondary)" }}>
              {data.totalCount} {data.totalCount === 1 ? "item" : "items"} saved · newest first
            </span>
          )}
        </form>

        <ErrorNote message={error} />

        <div className="flex flex-col gap-2">
          {data?.items.map((item) => (
            <BuyerListRow key={item.listingID} item={item} atLabel="Saved date" showTime={false} onRemove={() => remove(item.listingID)} />
          ))}
        </div>

        {data && data.totalCount === 0 && (
          <p className="text-sm" style={{ color: "var(--text-secondary)" }}>
            {applied ? "Nothing you've saved matches that search." : "You haven't saved anything yet. Use Save on any item to keep it here."}
          </p>
        )}

        {data && <Pager data={data} onPage={setPage} />}
      </BuyerOnly>
    </AccountShell>
  );
}
