import Link from "next/link";
import { PublicFooter, PublicHeader } from "@/components/layout/PublicHeader";
import { HomeIcon, type HomeIconName } from "@/components/home/HomeIcons";

// Header "Open Your Shop / for Shops and Clubs". The online application form
// comes later; until then an application goes in through PHILMART Support.
const steps: { title: string; body: string }[] = [
  { title: "Apply", body: "Tell us about your Shop or Club. PHILMART reviews every application." },
  { title: "Set up", body: "Once approved you get access to set up your Shop: details, delivery methods and users." },
  { title: "Go live", body: "When your setup is complete your Shop goes live and you can list items for sale and auction." },
];

const offers: { icon: HomeIconName; title: string; body: string }[] = [
  { icon: "people", title: "One marketplace", body: "Collectors across South Africa browse every approved Shop and Club in one place." },
  { icon: "gavel", title: "Buy Now and auctions", body: "Sell at a fixed price or by auction, with soft close and automatic closing." },
  { icon: "shield", title: "You stay in control", body: "Buyers pay your Shop directly. PHILMART never holds the money." },
  { icon: "award", title: "Your own team", body: "Add your staff and give each one only the permissions they need." },
];

export default function OpenYourShopPage() {
  return (
    <div className="flex min-h-screen flex-col" style={{ background: "var(--surface-marketplace)" }}>
      <PublicHeader />

      <main className="flex-1">
        <section style={{ background: "var(--philmart-navy-deep)" }}>
          <div className="mx-auto max-w-[1400px] px-4 py-10">
            <h1 className="font-display text-4xl leading-tight">
              <span style={{ color: "#ffffff" }}>Open Your Shop</span>
              <br />
              <span style={{ color: "var(--philmart-gold)" }}>for Shops and Clubs</span>
            </h1>
            <p className="mt-4 max-w-2xl text-lg" style={{ color: "rgb(255 255 255 / 0.9)" }}>
              Sell to collectors across South Africa on PHILMART, South Africa&rsquo;s Philatelic Marketplace and Auction House.
            </p>
            <Link
              href="/support?category=shops"
              className="mt-6 inline-block px-7 py-3 text-sm font-bold uppercase tracking-wide"
              style={{ background: "var(--philmart-gold)", color: "var(--text-on-gold)", borderRadius: 4 }}
            >
              Apply to open a Shop
            </Link>
          </div>
        </section>

        <section className="mx-auto max-w-[1400px] px-4 py-10">
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            {offers.map((offer) => (
              <article
                key={offer.title}
                className="p-5"
                style={{ background: "var(--surface-card)", border: "1px solid var(--border-subtle)", borderRadius: "var(--radius-card)" }}
              >
                <span
                  className="flex h-12 w-12 items-center justify-center rounded-full"
                  style={{ background: "var(--philmart-gold)", color: "#ffffff" }}
                >
                  <HomeIcon name={offer.icon} size={24} />
                </span>
                <h2 className="mt-3 font-display text-lg font-semibold" style={{ color: "var(--text-primary)" }}>
                  {offer.title}
                </h2>
                <p className="mt-1 text-sm leading-relaxed" style={{ color: "var(--text-secondary)" }}>
                  {offer.body}
                </p>
              </article>
            ))}
          </div>

          <h2 className="mt-12 font-display text-2xl font-bold" style={{ color: "var(--text-primary)" }}>
            How it works
          </h2>
          <ol className="mt-4 grid gap-4 md:grid-cols-3">
            {steps.map((step, index) => (
              <li
                key={step.title}
                className="flex gap-4 p-5"
                style={{ background: "var(--surface-card)", border: "1px solid var(--border-subtle)", borderRadius: "var(--radius-card)" }}
              >
                <span
                  className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-sm font-bold"
                  style={{ background: "var(--philmart-navy)", color: "var(--text-inverse)" }}
                >
                  {index + 1}
                </span>
                <span>
                  <span className="block font-display text-lg font-semibold" style={{ color: "var(--text-primary)" }}>
                    {step.title}
                  </span>
                  <span className="mt-1 block text-sm" style={{ color: "var(--text-secondary)" }}>
                    {step.body}
                  </span>
                </span>
              </li>
            ))}
          </ol>

          <p className="mt-8 text-sm" style={{ color: "var(--text-secondary)" }}>
            Ready to apply, or have a question first?{" "}
            <Link href="/support?category=shops" className="font-semibold hover:underline" style={{ color: "var(--accent-info)" }}>
              Contact PHILMART
            </Link>{" "}
            and choose &ldquo;Opening a Shop&rdquo;. Already set up?{" "}
            <Link href="/workspace/login" className="font-semibold hover:underline" style={{ color: "var(--accent-info)" }}>
              Sign in to your Shop workspace
            </Link>
            .
          </p>
        </section>
      </main>

      <PublicFooter />
    </div>
  );
}
