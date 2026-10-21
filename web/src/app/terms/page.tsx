"use client";

import { useEffect, useState } from "react";
import { PublicFooter, PublicHeader } from "@/components/layout/PublicHeader";
import { ErrorNote } from "@/components/ui/Form";
import { api, errorText, type LegalDocument } from "@/lib/api";

// Footer "Terms & Conditions". The current published buyer documents, the
// same versions registration asks people to accept.
export default function TermsPage() {
  const [docs, setDocs] = useState<LegalDocument[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    api.legal
      .current()
      .then((d) => !cancelled && setDocs(d))
      .catch((e) => !cancelled && setError(errorText(e)));
    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <div className="flex min-h-screen flex-col" style={{ background: "var(--surface-marketplace)" }}>
      <PublicHeader />

      <main className="mx-auto w-full max-w-4xl flex-1 px-4 py-10">
        <h1 className="font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>
          Terms &amp; Conditions
        </h1>
        <p className="mb-6 mt-1 text-sm" style={{ color: "var(--text-secondary)" }}>
          The documents that apply when you use PHILMART to buy or bid.
        </p>

        <ErrorNote message={error} />

        {docs && docs.length > 1 && (
          <nav aria-label="Documents" className="mb-6 flex flex-wrap gap-2">
            {docs.map((d) => (
              <a
                key={d.code}
                href={`#${d.code}`}
                className="px-4 py-2 text-sm font-semibold hover:opacity-90"
                style={{ background: "var(--surface-card)", border: "1px solid var(--border-default)", borderRadius: 4, color: "var(--text-primary)" }}
              >
                {d.name}
              </a>
            ))}
          </nav>
        )}

        {docs === null && !error && <p className="text-sm" style={{ color: "var(--text-muted)" }}>Loading…</p>}
        {docs?.length === 0 && (
          <p className="text-sm" style={{ color: "var(--text-muted)" }}>The documents haven&apos;t been published yet.</p>
        )}

        {docs?.map((d) => (
          <section
            key={d.code}
            id={d.code}
            className="mb-6 scroll-mt-6 p-6"
            style={{ background: "var(--surface-card)", border: "1px solid var(--border-subtle)", borderRadius: "var(--radius-card)" }}
          >
            <h2 className="font-display text-xl font-semibold" style={{ color: "var(--text-primary)" }}>
              {d.name}
            </h2>
            <p className="mb-4 text-xs" style={{ color: "var(--text-muted)" }}>
              Version {d.version}
            </p>
            <div className="whitespace-pre-wrap text-sm leading-relaxed" style={{ color: "var(--text-secondary)" }}>
              {d.body}
            </div>
          </section>
        ))}
      </main>

      <PublicFooter />
    </div>
  );
}
