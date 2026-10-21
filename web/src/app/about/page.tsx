import Link from "next/link";
import type { Metadata } from "next";
import { PublicHeader, PublicFooter } from "@/components/layout/PublicHeader";

export const metadata: Metadata = {
  title: "About PHILMART",
  description: "South Africa's philatelic marketplace and auction house for approved Shops and Clubs.",
};

// no screen ID in the D076 matrix for this page. Wording follows BRD section 5
export default function AboutPage() {
  return (
    <div className="flex min-h-screen flex-col" style={{ background: "var(--surface-marketplace)" }}>
      <PublicHeader />

      <main className="flex-1">
        <section style={{ background: "var(--philmart-navy-deep)" }}>
          <div className="mx-auto max-w-[1400px] px-4 py-14">
            <p className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--philmart-gold)" }}>
              About PHILMART
            </p>
            <h1 className="mt-3 max-w-3xl font-display text-4xl leading-tight lg:text-5xl" style={{ color: "#ffffff" }}>
              One marketplace for South Africa&rsquo;s stamp dealers, clubs and collectors
            </h1>
            <div className="my-5 h-px w-24" style={{ background: "var(--philmart-gold)" }} aria-hidden />
            <p className="max-w-2xl text-base leading-relaxed" style={{ color: "rgb(255 255 255 / 0.85)" }}>
              PHILMART brings philatelic items from approved Shops and Clubs together in one place. Collectors can
              browse, buy at a fixed price or bid at auction, while each Shop keeps running its own business: its
              stock, its invoices and its relationship with its buyers.
            </p>
          </div>
        </section>

        <section className="mx-auto max-w-[1400px] px-4 py-12">
          <SectionHeading>Who does what</SectionHeading>

          <div className="grid gap-4 md:grid-cols-3">
            {[
              {
                title: "PHILMART",
                role: "Runs the platform",
                body: "Reviews and approves Shop applications, maintains the marketplace and its reference data, and charges Shops a platform fee. PHILMART does not trade items itself.",
              },
              {
                title: "Shops and Clubs",
                role: "Sell on the platform",
                body: "Independent dealers and clubs list their items, run their own auctions, issue invoices, record payments and dispatch or arrange collection.",
              },
              {
                title: "Buyers",
                role: "Buy and bid",
                body: "Registered collectors buy or bid on items, choose a delivery option and pay the Shop directly. Each buyer sees only their own account, orders and queries.",
              },
            ].map((party) => (
              <article
                key={party.title}
                className="p-6"
                style={{
                  background: "var(--surface-card)",
                  border: "1px solid var(--border-subtle)",
                  borderRadius: "var(--radius-card)",
                }}
              >
                <p className="text-[11px] font-bold uppercase tracking-wide" style={{ color: "var(--philmart-gold)" }}>
                  {party.role}
                </p>
                <h3 className="mt-1 font-display text-xl font-bold" style={{ color: "var(--text-primary)" }}>
                  {party.title}
                </h3>
                <p className="mt-2 text-sm leading-relaxed" style={{ color: "var(--text-secondary)" }}>
                  {party.body}
                </p>
              </article>
            ))}
          </div>

          <div
            className="mt-10 grid gap-6 p-6 md:grid-cols-[1fr_2fr] md:p-8"
            style={{ background: "var(--accent-live-bg)", borderRadius: "var(--radius-card)" }}
          >
            <h2 className="font-display text-2xl font-bold" style={{ color: "var(--accent-live)" }}>
              Your money goes straight to the Shop
            </h2>
            <div className="text-sm leading-relaxed" style={{ color: "var(--text-secondary)" }}>
              <p>
                PHILMART never holds buyer money. There is no wallet or payment gateway, and we do not store your
                card or bank details.
              </p>
              <p className="mt-3">
                When you buy or win an item, the Shop sends you an invoice and you pay the Shop directly. The Shop
                then records your payment on PHILMART and arranges delivery or collection.
              </p>
            </div>
          </div>

          <SectionHeading className="mt-12">What we stand for</SectionHeading>

          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {[
              {
                title: "Approved sellers",
                body: "Every Shop and Club applies to PHILMART and is reviewed before it can trade.",
              },
              {
                title: "Fair auctions",
                body: "Auction timing runs on our server clock, not on anyone's device, so every bidder plays by the same rules.",
              },
              {
                title: "Private shop data",
                body: "Each Shop sees only its own stock, buyers and records. No Shop can see another Shop's business.",
              },
              {
                title: "A record you can trust",
                body: "Important events are kept in an audit trail and are never silently changed or deleted.",
              },
            ].map((value) => (
              <article
                key={value.title}
                className="p-5"
                style={{
                  background: "var(--surface-card)",
                  border: "1px solid var(--border-subtle)",
                  borderTop: "3px solid var(--philmart-gold)",
                  borderRadius: "var(--radius-card)",
                }}
              >
                <h3 className="font-display text-base font-semibold" style={{ color: "var(--text-primary)" }}>
                  {value.title}
                </h3>
                <p className="mt-1.5 text-sm leading-relaxed" style={{ color: "var(--text-secondary)" }}>
                  {value.body}
                </p>
              </article>
            ))}
          </div>

          <div
            className="mt-12 flex flex-wrap items-center justify-between gap-4 p-6 md:p-8"
            style={{ background: "var(--philmart-navy)", borderRadius: "var(--radius-card)" }}
          >
            <div>
              <h2 className="font-display text-2xl font-bold" style={{ color: "#ffffff" }}>
                Ready to start collecting?
              </h2>
              <p className="mt-1 text-sm" style={{ color: "rgb(255 255 255 / 0.8)" }}>
                Browse the marketplace, or get in touch if you have a question.
              </p>
            </div>
            <div className="flex flex-wrap gap-3">
              <Link
                href="/marketplace"
                className="px-6 py-3 text-sm font-bold uppercase tracking-wide"
                style={{ background: "var(--philmart-gold)", color: "var(--text-on-gold)", borderRadius: 4 }}
              >
                Browse Marketplace
              </Link>
              <Link
                href="/support"
                className="px-6 py-3 text-sm font-bold uppercase tracking-wide"
                style={{ border: "1px solid rgb(255 255 255 / 0.5)", color: "#ffffff", borderRadius: 4 }}
              >
                Contact Us
              </Link>
            </div>
          </div>
        </section>
      </main>

      <PublicFooter />
    </div>
  );
}

function SectionHeading({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return (
    <>
      <h2 className={`text-center font-display text-2xl font-bold ${className}`} style={{ color: "var(--text-primary)" }}>
        {children}
      </h2>
      <div className="mx-auto mt-3 mb-8 h-px max-w-3xl" style={{ background: "var(--philmart-gold)" }} aria-hidden />
    </>
  );
}
