"use client";

import Link from "next/link";
import { useEffect, useState, type ReactNode } from "react";
import { AccountShell } from "@/components/layout/AccountShell";
import { PublicFooter, PublicHeader } from "@/components/layout/PublicHeader";
import { Button, ErrorNote, Field, inputStyle, Panel } from "@/components/ui/Form";
import { api, errorText, type SupportCategory, type SupportReceipt } from "@/lib/api";
import { useSession } from "@/lib/session";

// SCR-PUB-015, BR-02-R07. Goes to PHILMART. Questions about an item go to the Shop instead.
export default function SupportPage() {
  const session = useSession();
  const isBuyer = session?.user.actorKind === "Buy_Buyer";
  const [categories, setCategories] = useState<SupportCategory[]>([]);
  const [receipt, setReceipt] = useState<SupportReceipt | null>(null);

  useEffect(() => {
    let cancelled = false;
    api.support
      .categories()
      .then((c) => !cancelled && setCategories(c))
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);

  const body = receipt ? <Confirmation receipt={receipt} isBuyer={isBuyer} /> : <SupportForm categories={categories} isBuyer={isBuyer} onSent={setReceipt} />;

  if (isBuyer) {
    return <AccountShell screenId="SCR-PUB-015">{body}</AccountShell>;
  }

  return (
    <div className="flex min-h-screen flex-col" style={{ background: "var(--surface-marketplace)" }}>
      <PublicHeader />
      <main className="mx-auto w-full max-w-4xl flex-1 px-4 py-8">{body}</main>
      <PublicFooter screenId="SCR-PUB-015" />
    </div>
  );
}

function SupportForm({
  categories,
  isBuyer,
  onSent,
}: {
  categories: SupportCategory[];
  isBuyer: boolean;
  onSent: (receipt: SupportReceipt) => void;
}) {
  const [category, setCategory] = useState("");
  const [subject, setSubject] = useState("");
  const [related, setRelated] = useState("");
  const [message, setMessage] = useState("");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      onSent(
        await api.support.submit({
          category,
          subject,
          relatedReference: related || undefined,
          message,
          contactName: isBuyer ? undefined : name,
          contactEmail: isBuyer ? undefined : email,
        }),
      );
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Heading title="PHILMART Support" intro="Contact PHILMART about a general support matter.">
      <p
        className="mb-6 px-4 py-3 text-xs"
        style={{ background: "var(--surface-card)", border: "1px solid var(--border-subtle)", borderRadius: 4, color: "var(--text-secondary)" }}
      >
        For Shop-specific item questions, ask the Shop. Support requests do not pause payment, invoice, delivery or auction deadlines.
      </p>

      <ErrorNote message={error} />

      <form onSubmit={submit}>
        {!isBuyer && (
          <div className="grid gap-x-4 md:grid-cols-2">
            <Field label="Your name *" htmlFor="name">
              <input id="name" required value={name} onChange={(e) => setName(e.target.value)} style={inputStyle} maxLength={200} />
            </Field>
            <Field label="Email address *" htmlFor="email" hint="We'll reply to this address.">
              <input id="email" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} style={inputStyle} maxLength={256} />
            </Field>
          </div>
        )}

        <Field label="Category *" htmlFor="category">
          <select id="category" required value={category} onChange={(e) => setCategory(e.target.value)} style={{ ...inputStyle, maxWidth: 370 }}>
            <option value="">Select category</option>
            {categories.map((c) => (
              <option key={c.value} value={c.value}>{c.label}</option>
            ))}
          </select>
        </Field>

        <Field label="Subject *" htmlFor="subject">
          <input id="subject" required value={subject} onChange={(e) => setSubject(e.target.value)} style={{ ...inputStyle, maxWidth: 780 }} maxLength={400} />
        </Field>

        <Field label="PHILMART No. / Invoice No. (optional)" htmlFor="related">
          <input id="related" placeholder="Optional" value={related} onChange={(e) => setRelated(e.target.value)} style={{ ...inputStyle, maxWidth: 530 }} maxLength={60} />
        </Field>

        <Field label="Message *" htmlFor="message">
          <textarea id="message" required rows={6} value={message} onChange={(e) => setMessage(e.target.value)} style={inputStyle} maxLength={4000} />
        </Field>

        <div className="flex items-center justify-between">
          <Link href={isBuyer ? "/account/saved" : "/"} className="text-xs font-semibold hover:underline" style={{ color: "var(--philmart-navy)" }}>
            Cancel
          </Link>
          <Button disabled={busy} wide={false}>{busy ? "Sending…" : "Submit Request"}</Button>
        </div>

        <p className="mt-6 text-[11px]" style={{ color: "var(--text-muted)" }}>
          Submitted requests are authoritative PHILMART support records. Confirmation is timestamped in SAST.
        </p>
      </form>
    </Heading>
  );
}

function Confirmation({ receipt, isBuyer }: { receipt: SupportReceipt; isBuyer: boolean }) {
  const submitted = new Date(receipt.submittedAt).toLocaleString("en-ZA", {
    timeZone: "Africa/Johannesburg",
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });

  return (
    <Heading title="PHILMART Support">
      <Panel>
        <div className="flex gap-5">
          <span
            className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-lg text-white"
            style={{ background: "var(--accent-live)" }}
            aria-hidden
          >
            ✓
          </span>
          <div>
            <h2 className="font-display text-2xl font-bold" style={{ color: "var(--philmart-navy)" }}>Support request submitted</h2>
            <p className="mt-2 text-sm font-bold" style={{ color: "var(--philmart-navy)" }}>Reference: {receipt.reference}</p>
            <p className="mt-1 text-xs" style={{ color: "var(--text-secondary)" }}>Submitted: {submitted} SAST</p>
            <p className="mt-4 text-sm" style={{ color: "var(--text-secondary)" }}>PHILMART has received your support request.</p>
            <p className="mt-1 text-[11px]" style={{ color: "var(--text-muted)" }}>
              Any email notification is a copy. This support record remains authoritative.
            </p>
            <div className="mt-5">
              <Link href={isBuyer ? "/account/saved" : "/marketplace"}>
                <Button type="button" wide={false}>{isBuyer ? "Return to My Account" : "Back to the marketplace"}</Button>
              </Link>
            </div>
          </div>
        </div>
      </Panel>
    </Heading>
  );
}

function Heading({ title, intro, children }: { title: string; intro?: string; children: ReactNode }) {
  return (
    <>
      <h1 className="font-display text-4xl font-bold" style={{ color: "var(--philmart-navy)" }}>{title}</h1>
      {intro && <p className="mb-6 mt-1 text-sm" style={{ color: "var(--text-secondary)" }}>{intro}</p>}
      {!intro && <div className="mb-6" />}
      {children}
    </>
  );
}
