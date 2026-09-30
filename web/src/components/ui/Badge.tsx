import type { ReactNode } from "react";

type BadgeTone =
  | "buyNow"
  | "auction"
  | "live"
  | "scheduled"
  | "attention"
  | "info"
  | "danger"
  | "neutral";

const TONE_STYLE: Record<BadgeTone, React.CSSProperties> = {
  // navy for buy now, gold for auction. it's how buyers tell them apart
  buyNow: {
    background: "var(--philmart-navy)",
    color: "var(--text-inverse)",
  },
  auction: {
    background: "var(--philmart-gold)",
    color: "var(--text-on-gold)",
  },
  live: {
    background: "var(--accent-live-bg)",
    color: "var(--accent-live)",
    border: "1px solid var(--accent-live)",
  },
  scheduled: {
    background: "var(--accent-scheduled-bg)",
    color: "var(--accent-scheduled)",
    border: "1px solid var(--accent-scheduled)",
  },
  attention: {
    background: "var(--accent-attention-bg)",
    color: "var(--accent-attention)",
  },
  info: {
    background: "var(--accent-info-bg)",
    color: "var(--accent-info)",
  },
  danger: {
    background: "var(--accent-danger-bg)",
    color: "var(--accent-danger)",
  },
  neutral: {
    background: "var(--surface-sunken)",
    color: "var(--text-secondary)",
  },
};

export function Badge({
  tone = "neutral",
  children,
}: {
  tone?: BadgeTone;
  children: ReactNode;
}) {
  return (
    <span
      className="inline-flex items-center px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide"
      style={{ ...TONE_STYLE[tone], borderRadius: "var(--radius-badge)" }}
    >
      {children}
    </span>
  );
}

export function ListingTypeBadge({ listingType }: { listingType: string }) {
  return listingType === "auction" ? (
    <Badge tone="auction">Auction</Badge>
  ) : (
    <Badge tone="buyNow">Buy Now</Badge>
  );
}
