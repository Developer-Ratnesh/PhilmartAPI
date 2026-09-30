import Link from "next/link";
import { ListingTypeBadge } from "@/components/ui/Badge";
import { formatMoney, formatTimeLeft, type MarketplaceItem } from "@/lib/api";

export function ItemCard({ item }: { item: MarketplaceItem }) {
  const isAuction = item.listingType === "auction";
  const timeLeft = formatTimeLeft(item.endsAt);

  return (
    <Link
      href={`/item/${item.listingID}`}
      className="group flex flex-col overflow-hidden transition-shadow hover:shadow-md focus-visible:shadow-md"
      style={{
        background: "var(--surface-card-warm)",
        border: "1px solid var(--border-subtle)",
        borderRadius: "var(--radius-card)",
      }}
    >
      <div
        className="relative aspect-[4/3] overflow-hidden"
        style={{ background: "var(--surface-sunken)" }}
      >
        {item.primaryImageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={item.primaryImageUrl}
            alt={item.title}
            loading="lazy"
            className="h-full w-full object-contain transition-transform duration-200 group-hover:scale-[1.02]"
          />
        ) : (
          <div
            className="flex h-full w-full items-center justify-center text-xs"
            style={{ color: "var(--text-muted)" }}
          >
            No image
          </div>
        )}

        <span className="absolute left-2 top-2">
          <ListingTypeBadge listingType={item.listingType} />
        </span>

        {item.imageCount > 1 && (
          <span
            className="absolute right-2 top-2 flex h-6 w-6 items-center justify-center rounded-full text-[11px] font-semibold"
            style={{
              background: "var(--philmart-navy)",
              color: "var(--text-inverse)",
            }}
            aria-label={`${item.imageCount} images`}
          >
            {item.imageCount}
          </span>
        )}
      </div>

      <div className="flex flex-1 flex-col gap-1.5 p-3">
        <h3
          className="font-display text-sm font-semibold leading-snug"
          style={{ color: "var(--text-primary)" }}
        >
          {item.title}
        </h3>

        <p className="text-xs" style={{ color: "var(--accent-info)" }}>
          {item.shopName}
        </p>

        <p className="text-[11px] leading-relaxed" style={{ color: "var(--text-muted)" }}>
          {[item.areaCountry, item.type].filter(Boolean).join(" • ")}
          {item.theme && (
            <>
              <br />
              Theme: {item.theme}
            </>
          )}
        </p>

        <div className="mt-auto flex items-end justify-between gap-2 pt-2">
          {isAuction ? (
            <div>
              <span className="text-[11px]" style={{ color: "var(--text-muted)" }}>
                Current Bid:{" "}
              </span>
              <span
                className="font-display text-sm font-bold"
                style={{ color: "var(--price-bid)" }}
              >
                {formatMoney(item.currentBidMinor ?? 0)}
              </span>
            </div>
          ) : (
            <span
              className="font-display text-base font-bold"
              style={{ color: "var(--price-fixed)" }}
            >
              {formatMoney(item.priceMinor)}
            </span>
          )}

          {isAuction && timeLeft && (
            <span
              className="whitespace-nowrap text-[11px] tabular-nums"
              style={{ color: "var(--text-muted)" }}
            >
              {timeLeft}
            </span>
          )}
        </div>
      </div>
    </Link>
  );
}

// same data as the card, just laid out differently
export function ItemRow({ item }: { item: MarketplaceItem }) {
  const isAuction = item.listingType === "auction";
  const timeLeft = formatTimeLeft(item.endsAt);

  return (
    <Link
      href={`/item/${item.listingID}`}
      className="flex gap-4 p-3 transition-colors"
      style={{
        background: "var(--surface-card-warm)",
        border: "1px solid var(--border-subtle)",
        borderRadius: "var(--radius-card)",
      }}
    >
      <div
        className="relative h-24 w-32 shrink-0 overflow-hidden rounded"
        style={{ background: "var(--surface-sunken)" }}
      >
        {item.primaryImageUrl && (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={item.primaryImageUrl}
            alt={item.title}
            loading="lazy"
            className="h-full w-full object-contain"
          />
        )}
        <span className="absolute left-1 top-1">
          <ListingTypeBadge listingType={item.listingType} />
        </span>
      </div>

      <div className="flex min-w-0 flex-1 flex-col gap-1">
        <h3
          className="font-display text-sm font-semibold"
          style={{ color: "var(--text-primary)" }}
        >
          {item.title}
        </h3>
        <p className="text-xs" style={{ color: "var(--accent-info)" }}>
          {item.shopName}
        </p>
        <p className="text-[11px]" style={{ color: "var(--text-muted)" }}>
          {[item.areaCountry, item.type, item.theme].filter(Boolean).join(" • ")}
        </p>
      </div>

      <div className="flex shrink-0 flex-col items-end justify-center gap-1">
        {isAuction ? (
          <>
            <span
              className="font-display text-base font-bold"
              style={{ color: "var(--price-bid)" }}
            >
              {formatMoney(item.currentBidMinor ?? 0)}
            </span>
            {timeLeft && (
              <span className="text-[11px] tabular-nums" style={{ color: "var(--text-muted)" }}>
                {timeLeft}
              </span>
            )}
          </>
        ) : (
          <span
            className="font-display text-base font-bold"
            style={{ color: "var(--price-fixed)" }}
          >
            {formatMoney(item.priceMinor)}
          </span>
        )}
      </div>
    </Link>
  );
}
