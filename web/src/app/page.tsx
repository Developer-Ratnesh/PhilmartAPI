import Image from "next/image";
import Link from "next/link";
import { PublicHeader, PublicFooter } from "@/components/layout/PublicHeader";
import { HomeListings } from "@/components/home/HomeListings";
import { HomeIcon, type HomeIconName } from "@/components/home/HomeIcons";

const steps: { n: number; title: string; body: string; icon: HomeIconName }[] = [
  { n: 1, title: "Browse", body: "Explore items from approved Shops and Clubs.", icon: "search" },
  { n: 2, title: "Buy or Bid", body: "Buy or bid on items in our Marketplace or Auctions.", icon: "cart" },
  { n: 3, title: "Choose Delivery Option", body: "Select your preferred delivery option with the Shop.", icon: "truck" },
  // we never hold buyer money, they pay the shop direct
  { n: 4, title: "Arrange Payment Directly with the Shop", body: "Arrange payment directly with the Shop.", icon: "people" },
];

const promos: {
  title: string;
  body: string;
  cta: string;
  href: string;
  icon: HomeIconName;
  colour: string;
  background: string;
}[] = [
  {
    title: "Recently Listed",
    body: "Discover the latest items added by our Shops and Clubs.",
    cta: "View Recently Listed",
    href: "/marketplace?sort=newest",
    icon: "calendar",
    colour: "var(--accent-live)",
    background: "var(--accent-live-bg)",
  },
  {
    title: "Auctions Ending Soon",
    body: "Find auctions closing soon and place your bids.",
    cta: "View Auctions Ending Soon",
    href: "/marketplace?sellingMethod=auction&sort=ending",
    icon: "gavel",
    colour: "var(--accent-auction)",
    background: "var(--accent-auction-bg)",
  },
];

const trust: { label: string; icon: HomeIconName }[] = [
  { label: "Approved Shops & Clubs", icon: "shield" },
  { label: "One Philatelic Marketplace", icon: "people" },
  { label: "Buy or Bid with Confidence", icon: "award" },
];

export default function HomePage() {
  return (
    <div className="flex min-h-screen flex-col" style={{ background: "var(--surface-marketplace)" }}>
      <PublicHeader />

      <main className="flex-1">
        <section className="relative overflow-hidden" style={{ background: "var(--philmart-navy-deep)" }}>
          {/* hero photo from the approved SCR-PUB-001 design (BRAND-ASSET-002) */}
          <div className="relative aspect-[976/429] w-full lg:absolute lg:inset-y-0 lg:right-0 lg:aspect-auto lg:w-[60%]">
            <Image
              src="/brand/home-hero.jpg"
              alt="Cape of Good Hope triangular stamp held with stamp tongs"
              fill
              priority
              sizes="(min-width: 1024px) 60vw, 100vw"
              className="object-cover object-left"
            />
            <div
              className="absolute inset-0 hidden lg:block"
              style={{ background: "linear-gradient(90deg, var(--philmart-navy-deep) 0%, transparent 14%)" }}
              aria-hidden
            />
          </div>

          <div className="relative mx-auto max-w-[1400px] px-4 py-8 lg:py-10">
            <div className="lg:w-[44%]">
              <h1 className="font-display text-3xl leading-tight lg:text-[2.6rem]">
                <span style={{ color: "#ffffff" }}>Welcome to</span>
                <br />
                <span style={{ color: "var(--philmart-gold)" }}>
                  South Africa&rsquo;s Philatelic Marketplace and Auction House
                </span>
              </h1>

              <div className="my-4 h-0.5 w-24" style={{ background: "var(--philmart-gold)" }} aria-hidden />

              <p className="max-w-md text-base lg:text-lg" style={{ color: "rgb(255 255 255 / 0.9)" }}>
                Buy or bid on philatelic items from approved{" "}
                <span style={{ color: "var(--philmart-gold)" }}>Shops and Clubs</span> across South Africa.
              </p>

              <Link
                href="/marketplace"
                className="mt-5 inline-block px-7 py-3 text-sm font-bold uppercase tracking-wide"
                style={{ background: "var(--philmart-gold)", color: "var(--text-on-gold)", borderRadius: 4 }}
              >
                Browse Marketplace
              </Link>
            </div>
          </div>
        </section>

        <section className="mx-auto max-w-[1400px] px-4 py-10">
          <div className="flex items-center gap-6">
            <span className="h-px flex-1" style={{ background: "var(--philmart-gold)" }} aria-hidden />
            <h2 className="text-center font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>
              How PHILMART Works
            </h2>
            <span className="h-px flex-1" style={{ background: "var(--philmart-gold)" }} aria-hidden />
          </div>

          <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {steps.map((step) => (
              <article
                key={step.n}
                className="flex gap-4 p-4"
                style={{
                  background: "var(--surface-card)",
                  border: "1px solid var(--border-subtle)",
                  borderRadius: "var(--radius-card)",
                  boxShadow: "var(--shadow-card)",
                }}
              >
                <span
                  className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full"
                  style={{ background: "var(--philmart-gold)", color: "#ffffff" }}
                >
                  <HomeIcon name={step.icon} size={28} />
                </span>
                <div>
                  <h3
                    className="flex items-start gap-2 font-display text-lg font-semibold leading-snug"
                    style={{ color: "var(--text-primary)" }}
                  >
                    <span
                      className="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full font-sans text-xs font-bold"
                      style={{ background: "var(--philmart-navy)", color: "var(--text-inverse)" }}
                    >
                      {step.n}
                    </span>
                    {step.title}
                  </h3>
                  <p className="mt-1.5 text-sm leading-relaxed" style={{ color: "var(--text-secondary)" }}>
                    {step.body}
                  </p>
                </div>
              </article>
            ))}
          </div>

          <div className="mt-4 grid gap-4 md:grid-cols-2">
            {promos.map((promo) => (
              <article
                key={promo.title}
                className="flex items-center gap-6 p-5"
                style={{
                  background: promo.background,
                  border: "1px solid var(--border-subtle)",
                  borderRadius: "var(--radius-card)",
                }}
              >
                <span
                  className="flex h-20 w-20 shrink-0 items-center justify-center rounded-full"
                  style={{ background: "var(--surface-card)", color: promo.colour, boxShadow: "var(--shadow-raised)" }}
                >
                  <HomeIcon name={promo.icon} size={38} />
                </span>
                <div>
                  <h2 className="font-display text-2xl font-semibold" style={{ color: promo.colour }}>
                    {promo.title}
                  </h2>
                  <p className="mt-1 text-sm" style={{ color: "var(--text-primary)" }}>
                    {promo.body}
                  </p>
                  <Link
                    href={promo.href}
                    className="mt-3 inline-block px-5 py-1.5 text-sm font-medium uppercase tracking-wide"
                    style={{ background: promo.colour, color: "var(--text-inverse)", borderRadius: 3 }}
                  >
                    {promo.cta}
                  </Link>
                </div>
              </article>
            ))}
          </div>

          <HomeListings />
        </section>

        <section
          className="px-4 py-5"
          style={{ background: "var(--surface-sunken)", borderTop: "1px solid var(--border-subtle)" }}
        >
          <div
            className="mx-auto flex max-w-[1400px] flex-wrap items-center justify-center gap-x-12 gap-y-3 font-display text-base"
            style={{ color: "var(--text-primary)" }}
          >
            {trust.map((entry, index) => (
              <span key={entry.label} className="flex items-center gap-12">
                {index > 0 && (
                  <span
                    className="hidden h-2.5 w-2.5 rounded-full sm:inline-block"
                    style={{ background: "var(--philmart-gold)" }}
                    aria-hidden
                  />
                )}
                <span className="flex items-center gap-3">
                  <HomeIcon name={entry.icon} size={28} />
                  {entry.label}
                </span>
              </span>
            ))}
          </div>
        </section>
      </main>

      <PublicFooter screenId="SCR-PUB-001" />
    </div>
  );
}
