import Link from "next/link";
import { Badge } from "@/components/ui/Badge";
import { formatMoney, type BuyerListItem } from "@/lib/api";

const STATUS: Record<BuyerListItem["status"], { label: string; tone: "live" | "neutral" }> = {
  available: { label: "Available", tone: "live" },
  auction_open: { label: "Auction Open", tone: "live" },
  auction_closed: { label: "Auction Closed", tone: "neutral" },
  sold: { label: "Sold", tone: "neutral" },
  unavailable: { label: "Unavailable", tone: "neutral" },
};

// one row on Saved Items or Recently Viewed, same layout on both screens
export function BuyerListRow({
  item,
  atLabel,
  showTime,
  onRemove,
}: {
  item: BuyerListItem;
  atLabel: string;
  showTime: boolean;
  onRemove: () => void;
}) {
  const auction = item.listingType === "auction";
  const status = STATUS[item.status];

  return (
    <div
      className="grid items-center gap-4 p-4 md:grid-cols-[72px_2fr_1fr_1fr_1.2fr_auto]"
      style={{
        background: "var(--surface-card)",
        border: "1px solid var(--border-subtle)",
        borderRadius: "var(--radius-card)",
      }}
    >
      <div
        className="flex h-16 w-16 items-center justify-center overflow-hidden text-[10px] font-semibold"
        style={{ background: "var(--surface-card-warm)", border: "1px solid var(--border-subtle)", color: "var(--text-muted)" }}
      >
        {item.primaryImageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={item.primaryImageUrl} alt="" className="h-full w-full object-cover" />
        ) : (
          "STAMP"
        )}
      </div>

      <div className="min-w-0">
        <Link href={`/item/${item.listingID}`} className="font-display text-lg hover:underline" style={{ color: "var(--philmart-navy)" }}>
          {item.title ?? "Item no longer listed"}
        </Link>
        {item.itemNumber && (
          <p className="text-[11px]" style={{ color: "var(--text-muted)" }}>Item Number {item.itemNumber}</p>
        )}
        {item.shopID && (
          <>
            <p className="mt-2 text-[10px] font-semibold uppercase" style={{ color: "var(--text-muted)" }}>Shop</p>
            <Link href={`/shop/${item.shopID}`} className="text-xs font-semibold hover:underline" style={{ color: "var(--philmart-navy)" }}>
              {item.shopName}
            </Link>
          </>
        )}
      </div>

      <Cell label="Selling method" value={auction ? "Auction" : "Buy Now"} />

      <Cell
        label={auction ? "Current bid" : "Item price"}
        value={formatMoney(auction ? item.currentBidMinor : item.priceMinor)}
      />

      <div>
        <p className="mb-1 text-[10px] font-semibold uppercase" style={{ color: "var(--text-muted)" }}>Current status</p>
        <Badge tone={status.tone}>{status.label}</Badge>
        <p className="mt-2 text-[10px] font-semibold uppercase" style={{ color: "var(--text-muted)" }}>{atLabel}</p>
        <p className="text-xs" style={{ color: "var(--text-secondary)" }}>{formatAt(item.at, showTime)}</p>
      </div>

      <button type="button" onClick={onRemove} className="justify-self-end text-xs font-semibold hover:underline" style={{ color: "var(--philmart-navy)" }}>
        Remove
      </button>
    </div>
  );
}

function Cell({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="mb-1 text-[10px] font-semibold uppercase" style={{ color: "var(--text-muted)" }}>{label}</p>
      <p className="text-sm font-semibold" style={{ color: "var(--text-primary)" }}>{value}</p>
    </div>
  );
}

// the screens show South African time
function formatAt(at: string, withTime: boolean) {
  const options: Intl.DateTimeFormatOptions = { timeZone: "Africa/Johannesburg", day: "numeric", month: "long", year: "numeric" };
  if (withTime) {
    options.hour = "2-digit";
    options.minute = "2-digit";
  }
  return new Date(at).toLocaleString("en-ZA", options);
}
