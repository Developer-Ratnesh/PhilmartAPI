"use client";

import { useCallback, useEffect, useState } from "react";
import { WorkspaceShell } from "@/components/layout/WorkspaceShell";
import { Button, ErrorNote, Field, inputStyle, Notice, Panel } from "@/components/ui/Form";
import { api, errorText, formatMoney, type InvoiceDetail, type InvoicePayment, type ShopSale } from "@/lib/api";
import { hasPermission, useSession } from "@/lib/session";

const STATUS: Record<string, string> = { unpaid: "Unpaid", part_paid: "Part paid", paid: "Paid" };

const day = (iso: string) => new Date(iso).toLocaleDateString("en-ZA", { day: "numeric", month: "short", year: "numeric" });

// Schedule A6 early technical proof: issue an invoice for a sale, record the
// payment the Buyer made to the Shop, and reverse it as a separate linked
// record. The full invoicing screens (BR-15/BR-16) are Milestone 3 and 4.
export default function WorkspaceSalesPage() {
  const session = useSession();
  const user = session?.user;
  const [sales, setSales] = useState<ShopSale[] | null>(null);
  const [invoice, setInvoice] = useState<InvoiceDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(() => {
    api.invoices
      .sales()
      .then(setSales)
      .catch((e) => setError(errorText(e)));
  }, []);

  useEffect(load, [load]);

  async function run(work: () => Promise<InvoiceDetail>) {
    setBusy(true);
    setError(null);
    try {
      setInvoice(await work());
      load();
    } catch (e) {
      setError(errorText(e));
    } finally {
      setBusy(false);
    }
  }

  const canIssue = hasPermission(user, "invoice.manage");

  return (
    <WorkspaceShell screenId="SCR-SHP-SALES">
      <h1 className="mb-1 font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>
        Sales &amp; Invoices
      </h1>
      <p className="mb-6 text-sm" style={{ color: "var(--text-secondary)" }}>
        Buyers pay your Shop directly. PHILMART only keeps the record: the invoice, the payments you record and any reversal.
      </p>

      <ErrorNote message={error} />

      <Panel>
        {sales === null ? (
          <p className="text-sm" style={{ color: "var(--text-muted)" }}>Loading…</p>
        ) : sales.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--text-secondary)" }}>No sales yet.</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead>
                <tr style={{ color: "var(--text-muted)" }}>
                  <th className="py-2 pr-4 font-semibold">Sold</th>
                  <th className="py-2 pr-4 font-semibold">Item</th>
                  <th className="py-2 pr-4 font-semibold">Buyer</th>
                  <th className="py-2 pr-4 text-right font-semibold">Price</th>
                  <th className="py-2 pr-4 font-semibold">Invoice</th>
                  <th className="py-2 font-semibold"></th>
                </tr>
              </thead>
              <tbody>
                {sales.map((s) => (
                  <tr key={s.saleTransactionID} style={{ borderTop: "1px solid var(--border-subtle)", color: "var(--text-primary)" }}>
                    <td className="py-2 pr-4 whitespace-nowrap">{day(s.soldAt)}</td>
                    <td className="py-2 pr-4">
                      <span className="font-semibold">{s.listingReference}</span> {s.title}
                      <span className="ml-2 text-[11px]" style={{ color: "var(--text-muted)" }}>
                        {s.saleKind === "auction" ? "Auction" : "Buy Now"}
                      </span>
                    </td>
                    <td className="py-2 pr-4">{s.buyerName ?? "—"}</td>
                    <td className="py-2 pr-4 text-right whitespace-nowrap">{formatMoney(s.salePriceMinor)}</td>
                    <td className="py-2 pr-4 whitespace-nowrap">
                      {s.invoiceNumber ? `${s.invoiceNumber} · ${STATUS[s.invoiceStatus ?? ""] ?? s.invoiceStatus}` : "Not invoiced"}
                    </td>
                    <td className="py-2 text-right whitespace-nowrap">
                      {s.invoiceID ? (
                        <button
                          type="button"
                          className="text-xs font-semibold hover:underline"
                          style={{ color: "var(--philmart-navy-ink)" }}
                          onClick={() => run(() => api.invoices.get(s.invoiceID!))}
                        >
                          Open
                        </button>
                      ) : canIssue ? (
                        <button
                          type="button"
                          disabled={busy}
                          className="text-xs font-semibold hover:underline disabled:opacity-50"
                          style={{ color: "var(--philmart-navy-ink)" }}
                          onClick={() => run(() => api.invoices.issue(s.saleTransactionID))}
                        >
                          Issue invoice
                        </button>
                      ) : null}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Panel>

      {invoice && (
        // a fresh panel after each change, so the form starts from the new outstanding amount
        <InvoicePanel
          key={`${invoice.invoiceID}-${invoice.payments.length}`}
          invoice={invoice}
          busy={busy}
          canRecord={hasPermission(user, "payment.record")}
          canReverse={hasPermission(user, "payment.reverse")}
          onRecord={(body) => run(() => api.invoices.recordPayment(invoice.invoiceID, body))}
          onReverse={(p, reason) => run(() => api.invoices.reverse(p.paymentID, reason))}
        />
      )}
    </WorkspaceShell>
  );
}

function InvoicePanel({
  invoice,
  busy,
  canRecord,
  canReverse,
  onRecord,
  onReverse,
}: {
  invoice: InvoiceDetail;
  busy: boolean;
  canRecord: boolean;
  canReverse: boolean;
  onRecord: (body: { amountMinor: number; receivedOn: string; paymentReference?: string }) => void;
  onReverse: (payment: InvoicePayment, reason: string) => void;
}) {
  const today = new Date().toISOString().slice(0, 10);
  const [amount, setAmount] = useState((invoice.outstandingMinor / 100).toFixed(2));
  const [receivedOn, setReceivedOn] = useState(today);
  const [reference, setReference] = useState("");
  const [reversing, setReversing] = useState<InvoicePayment | null>(null);
  const [reason, setReason] = useState("");

  const amountMinor = Math.round(Number(amount) * 100);

  return (
    <div className="mt-6">
      <Panel>
        <div className="mb-4 flex flex-wrap items-baseline justify-between gap-3">
          <h2 className="font-display text-2xl font-semibold" style={{ color: "var(--text-primary)" }}>
            Invoice {invoice.invoiceNumber}
          </h2>
          <span className="px-2 py-1 text-xs font-semibold" style={{ border: "1px solid var(--border-default)", borderRadius: 4, color: "var(--text-primary)" }}>
            {STATUS[invoice.status] ?? invoice.status}
          </span>
        </div>

        <dl className="mb-4 grid grid-cols-2 gap-x-6 gap-y-1 text-sm sm:grid-cols-4">
          <dt style={{ color: "var(--text-muted)" }}>Buyer</dt>
          <dd style={{ color: "var(--text-primary)" }}>{invoice.buyerName ?? "—"}</dd>
          <dt style={{ color: "var(--text-muted)" }}>Issued</dt>
          <dd style={{ color: "var(--text-primary)" }}>{invoice.issuedAt ? day(invoice.issuedAt) : "—"}</dd>
          <dt style={{ color: "var(--text-muted)" }}>Total</dt>
          <dd style={{ color: "var(--text-primary)" }}>{formatMoney(invoice.totalMinor)}</dd>
          <dt style={{ color: "var(--text-muted)" }}>Outstanding</dt>
          <dd style={{ color: "var(--text-primary)" }}>{formatMoney(invoice.outstandingMinor)}</dd>
        </dl>

        <h3 className="mb-1 text-sm font-semibold" style={{ color: "var(--text-primary)" }}>Lines</h3>
        <ul className="mb-4 text-sm" style={{ color: "var(--text-secondary)" }}>
          {invoice.lines.map((l, i) => (
            <li key={i} className="flex justify-between py-0.5">
              <span>{l.description}</span>
              <span>{formatMoney(l.lineTotalMinor)}</span>
            </li>
          ))}
        </ul>
        <p className="mb-4 text-[11px]" style={{ color: "var(--text-muted)" }}>
          An issued invoice can&apos;t be edited. A correction is a separate linked record.
        </p>

        <h3 className="mb-1 text-sm font-semibold" style={{ color: "var(--text-primary)" }}>Payments</h3>
        {invoice.payments.length === 0 ? (
          <p className="mb-4 text-sm" style={{ color: "var(--text-secondary)" }}>No payments recorded.</p>
        ) : (
          <ul className="mb-4 text-sm">
            {invoice.payments.map((p) => (
              <li key={p.paymentID} className="flex flex-wrap items-center justify-between gap-2 py-1" style={{ borderTop: "1px solid var(--border-subtle)", color: "var(--text-primary)" }}>
                <span>
                  {p.reversesPaymentID ? "Reversal" : "Payment"} · {day(p.receivedOn)}
                  {p.paymentReference && ` · ${p.paymentReference}`}
                  {p.reversalReason && <span style={{ color: "var(--text-muted)" }}> · {p.reversalReason}</span>}
                  {p.reversedByPaymentID && <span style={{ color: "var(--text-muted)" }}> · reversed</span>}
                </span>
                <span className="flex items-center gap-3">
                  <span>{p.reversesPaymentID ? `−${formatMoney(p.amountMinor)}` : formatMoney(p.amountMinor)}</span>
                  {canReverse && !p.reversesPaymentID && !p.reversedByPaymentID && (
                    <button type="button" className="text-xs font-semibold hover:underline" style={{ color: "var(--accent-danger)" }} onClick={() => setReversing(p)}>
                      Reverse
                    </button>
                  )}
                </span>
              </li>
            ))}
          </ul>
        )}

        {reversing && (
          <div className="mb-4 p-4" style={{ border: "1px solid var(--border-default)", borderRadius: 4 }}>
            <p className="mb-2 text-sm" style={{ color: "var(--text-primary)" }}>
              Reverse the payment of {formatMoney(reversing.amountMinor)}? The original stays on record and a linked reversal is added.
            </p>
            <Field label="Reason (required)" htmlFor="reverse-reason">
              <input id="reverse-reason" value={reason} onChange={(e) => setReason(e.target.value)} style={inputStyle} />
            </Field>
            <div className="mt-3 flex gap-3">
              <Button type="button" variant="secondary" onClick={() => setReversing(null)}>Cancel</Button>
              <Button type="button" disabled={busy || !reason.trim()} onClick={() => onReverse(reversing, reason.trim())}>
                Reverse payment
              </Button>
            </div>
          </div>
        )}

        {canRecord && invoice.outstandingMinor > 0 && (
          <form
            className="mb-4 grid gap-3 sm:grid-cols-[1fr_1fr_2fr_auto] sm:items-end"
            onSubmit={(e) => {
              e.preventDefault();
              onRecord({ amountMinor, receivedOn, paymentReference: reference.trim() || undefined });
            }}
          >
            <Field label="Amount received (R)" htmlFor="pay-amount">
              <input id="pay-amount" type="number" step="0.01" min="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} style={inputStyle} />
            </Field>
            <Field label="Received on" htmlFor="pay-date">
              <input id="pay-date" type="date" max={today} value={receivedOn} onChange={(e) => setReceivedOn(e.target.value)} style={inputStyle} />
            </Field>
            <Field label="Reference" htmlFor="pay-ref">
              <input id="pay-ref" value={reference} onChange={(e) => setReference(e.target.value)} placeholder="e.g. EFT reference" style={inputStyle} />
            </Field>
            <Button type="submit" disabled={busy || !(amountMinor > 0)}>Record payment</Button>
          </form>
        )}

        <h3 className="mb-1 text-sm font-semibold" style={{ color: "var(--text-primary)" }}>Buyer account statement</h3>
        <ul className="text-xs" style={{ color: "var(--text-secondary)" }}>
          {invoice.ledger.map((e) => (
            <li key={e.entryID} className="flex justify-between py-0.5">
              <span>
                {day(e.occurredAt)} · {e.description}
                {e.reversesEntryID && ` (reverses #${e.reversesEntryID})`}
              </span>
              <span>
                {e.direction === "debit" ? "Dr" : "Cr"} {formatMoney(e.amountMinor)}
              </span>
            </li>
          ))}
        </ul>
      </Panel>
      {invoice.status === "paid" && (
        <div className="mt-3">
          <Notice>Paid in full.</Notice>
        </div>
      )}
    </div>
  );
}
