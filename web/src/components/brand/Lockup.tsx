import Image from "next/image";
import Link from "next/link";

// The brand rules say use this exact image and never redraw it (BRAND-SHELL-001).
const LOCKUP = "/brand/philmart-lockup.png";

// Asset is 2172x724. Heights below keep that ratio so nothing squashes.
const sizes = {
  sm: { w: 180, h: 60 },
  md: { w: 255, h: 85 },
  lg: { w: 330, h: 110 },
};

type Props = {
  size?: keyof typeof sizes;
  href?: string | null;
  priority?: boolean;
};

export function Lockup({ size = "md", href = "/", priority = false }: Props) {
  const { w, h } = sizes[size];

  const img = (
    <Image
      src={LOCKUP}
      alt="PHILMART, South Africa's Philatelic Marketplace and Auction House"
      width={w}
      height={h}
      priority={priority}
      style={{ height: "auto", width: w }}
    />
  );

  if (!href) {
    return img;
  }

  return (
    <Link href={href} className="inline-flex items-center" aria-label="PHILMART home">
      {img}
    </Link>
  );
}
