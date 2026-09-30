import Link from "next/link";
import { PublicHeader, PublicFooter } from "@/components/layout/PublicHeader";

export default function HomePage() {
  return (
    <div className="flex min-h-screen flex-col" style={{ background: "var(--surface-marketplace)" }}>
      <PublicHeader />

      <main className="flex-1">
        <section
          className="relative overflow-hidden"
          style={{ background: "var(--philmart-navy-deep)" }}
        >
          <div className="mx-auto grid max-w-[1400px] gap-8 px-4 py-14 lg:grid-cols-2 lg:items-center">
            <div>
              <h1 className="font-display text-4xl leading-tight lg:text-5xl">
                <span style={{ color: "#ffffff" }}>Welcome to</span>
                <br />
                <span style={{ color: "var(--philmart-gold)" }}>
                  South Africa&rsquo;s Philatelic Marketplace and Auction House
                </span>
              </h1>

              <div
                className="my-5 h-px w-24"
                style={{ background: "var(--philmart-gold)" }}
                aria-hidden
              />

              <p className="max-w-md text-base" style={{ color: "rgb(255 255 255 / 0.85)" }}>
                Buy or bid on philatelic items from approved{" "}
                <span style={{ color: "var(--philmart-gold)" }}>Shops and Clubs</span> across
                South Africa.
              </p>

              <Link
                href="/marketplace"
                className="mt-7 inline-block px-7 py-3 text-sm font-bold uppercase tracking-wide"
                style={{
                  background: "var(--philmart-gold)",
                  color: "var(--text-on-gold)",
                  borderRadius: 4,
                }}
              >
                Browse Marketplace
              </Link>
            </div>

            <div
              className="hidden aspect-[4/3] lg:block"
              style={{
                background:
                  "linear-gradient(135deg, rgb(255 255 255 / 0.06), rgb(255 255 255 / 0.02))",
                borderRadius: "var(--radius-card)",
              }}
              aria-hidden
            />
          </div>
        </section>

        <section className="mx-auto max-w-[1400px] px-4 py-12">
          <h2
            className="text-center font-display text-2xl font-bold"
            style={{ color: "var(--text-primary)" }}
          >
            How PHILMART Works
          </h2>
          <div
            className="mx-auto mt-3 mb-8 h-px max-w-3xl"
            style={{ background: "var(--philmart-gold)" }}
            aria-hidden
          />

          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {[
              {
                n: 1,
                title: "Browse",
                body: "Explore items from approved Shops and Clubs.",
              },
              {
                n: 2,
                title: "Buy or Bid",
                body: "Buy or bid on items in our Marketplace or Auctions.",
              },
              {
                n: 3,
                title: "Choose Delivery Option",
                body: "Select your preferred delivery option with the Shop.",
              },
              {
                // we never hold buyer money, they pay the shop direct
                n: 4,
                title: "Arrange Payment Directly with the Shop",
                body: "Arrange payment directly with the Shop.",
              },
            ].map((step) => (
              <article
                key={step.n}
                className="p-5"
                style={{
                  background: "var(--surface-card)",
                  border: "1px solid var(--border-subtle)",
                  borderRadius: "var(--radius-card)",
                }}
              >
                <span
                  className="flex h-9 w-9 items-center justify-center rounded-full font-display text-sm font-bold"
                  style={{
                    background: "var(--philmart-navy)",
                    color: "var(--text-inverse)",
                  }}
                >
                  {step.n}
                </span>
                <h3
                  className="mt-3 font-display text-base font-semibold"
                  style={{ color: "var(--text-primary)" }}
                >
                  {step.title}
                </h3>
                <p className="mt-1.5 text-sm leading-relaxed" style={{ color: "var(--text-secondary)" }}>
                  {step.body}
                </p>
              </article>
            ))}
          </div>

          <div className="mt-4 grid gap-4 md:grid-cols-2">
            <Panel
              title="Recently Listed"
              body="Discover the latest items added by our Shops and Clubs."
              cta="View Recently Listed"
              href="/marketplace?sort=newest"
              tone="live"
            />
            <Panel
              title="Auctions Ending Soon"
              body="Find auctions closing soon and place your bids."
              cta="View Auctions Ending Soon"
              href="/marketplace?sellingMethod=auction&sort=ending"
              tone="auction"
            />
          </div>
        </section>

        <section
          className="px-4 py-6"
          style={{ borderTop: "1px solid var(--border-subtle)" }}
        >
          <div
            className="mx-auto flex max-w-[1400px] flex-wrap items-center justify-center gap-x-10 gap-y-3 text-sm font-medium"
            style={{ color: "var(--text-primary)" }}
          >
            <span>Approved Shops &amp; Clubs</span>
            <span aria-hidden style={{ color: "var(--philmart-gold)" }}>
              •
            </span>
            <span>One Philatelic Marketplace</span>
            <span aria-hidden style={{ color: "var(--philmart-gold)" }}>
              •
            </span>
            <span>Buy or Bid with Confidence</span>
          </div>
        </section>
      </main>

      <PublicFooter screenId="SCR-PUB-001" />
    </div>
  );
}

function Panel({
  title,
  body,
  cta,
  href,
  tone,
}: {
  title: string;
  body: string;
  cta: string;
  href: string;
  tone: "live" | "auction";
}) {
  const colour = tone === "live" ? "var(--accent-live)" : "var(--accent-auction)";
  const background = tone === "live" ? "var(--accent-live-bg)" : "var(--accent-auction-bg)";

  return (
    <article className="p-5" style={{ background, borderRadius: "var(--radius-card)" }}>
      <h3 className="font-display text-lg font-bold" style={{ color: colour }}>
        {title}
      </h3>
      <p className="mt-1 text-sm" style={{ color: "var(--text-secondary)" }}>
        {body}
      </p>
      <Link
        href={href}
        className="mt-4 inline-block px-4 py-2 text-xs font-bold uppercase tracking-wide"
        style={{ background: colour, color: "#ffffff", borderRadius: 3 }}
      >
        {cta}
      </Link>
    </article>
  );
}
