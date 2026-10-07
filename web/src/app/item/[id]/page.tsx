"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { PublicFooter, PublicHeader } from "@/components/layout/PublicHeader";
import { Button, ErrorNote, Field, inputStyle, Notice } from "@/components/ui/Form";
import {
  api,
  errorText,
  formatMoney,
  newIdempotencyKey,
  type Address,
  type ListingDetail,
  type PurchaseDefaults,
} from "@/lib/api";
import { useSession, type SignedInUser } from "@/lib/session";

// SCR-PUB-003A (Buy Now) and SCR-PUB-003B (auction)
export default function ItemDetailPage() {
  const { id } = useParams<{ id: string }>();
  const session = useSession();
  const [detail, setDetail] = useState<ListingDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [methodId, setMethodId] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);

  const reload = useCallback(() => setAttempt((n) => n + 1), []);

  useEffect(() => {
    let cancelled = false;
    api.listings
      .detail(id)
      .then((d) => {
        if (cancelled) return;
        setDetail(d);
        setMethodId((m) => m ?? d.deliveryOptions[0]?.id ?? null);
        setError(null);
      })
      .catch((e) => !cancelled && setError(errorText(e, "This item couldn't be loaded.")));
    return () => {
      cancelled = true;
    };
  }, [id, attempt]);

  const isBuyer = session?.user.actorKind === "Buy_Buyer";

  // feeds Recently Viewed (SCR-PUB-008). Not worth bothering the buyer if it fails.
  useEffect(() => {
    if (isBuyer && detail?.listingID) {
      api.account.viewed(detail.listingID).catch(() => {});
    }
  }, [isBuyer, detail?.listingID]);

  const isAuction = detail?.listingType === "auction";
  const open = detail?.state === "live";

  return (
    <div className="flex min-h-screen flex-col" style={{ background: "var(--surface-marketplace)" }}>
      <PublicHeader />

      <main className="mx-auto w-full max-w-[1400px] flex-1 px-4 py-8">
        <p className="text-xs" style={{ color: "var(--text-muted)" }}>
          <Link href="/marketplace" className="hover:underline">Marketplace</Link> ›{" "}
          {isAuction ? "Auction Item" : "Buy Now Item"}
        </p>

        <ErrorNote message={error} />

        {detail && (
          <>
            <div className="mb-6 mt-2 flex flex-wrap items-start justify-between gap-4">
              <h1 className="font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>
                {detail.title}
              </h1>
              {isBuyer && <SaveButton listingId={detail.listingID} />}
            </div>

            {result && <Notice>{result}</Notice>}

            <div className="grid gap-6 lg:grid-cols-[1.3fr_1fr_1fr]">
              <ImagesAndDescription detail={detail} />

              <div className="flex flex-col gap-6">
                <Box title={isAuction ? "Shipping Method if you win" : "Shipping Method"}>
                  <p className="mb-3 text-[11px]" style={{ color: "var(--text-muted)" }}>
                    Available methods are set by the Shop.
                  </p>
                  {detail.deliveryOptions.map((m) => (
                    <label
                      key={m.id}
                      className="mb-2 flex cursor-pointer items-center gap-3 p-3 text-sm"
                      style={{
                        border: `1px solid ${methodId === m.id ? "var(--philmart-navy-deep)" : "var(--border-subtle)"}`,
                        borderRadius: 4,
                        color: "var(--text-primary)",
                      }}
                    >
                      <input type="radio" name="method" checked={methodId === m.id} onChange={() => setMethodId(m.id)} />
                      <span className="font-semibold">{m.name}</span>
                      <span className="ml-auto text-[11px]" style={{ color: "var(--text-muted)" }}>
                        {m.methodKind === "collection" ? "Collection" : "Shipping"}
                      </span>
                    </label>
                  ))}
                  {detail.deliveryOptions.length === 0 && <Notice>This Shop hasn&apos;t set up delivery yet.</Notice>}
                </Box>

                <Box title="Shop">
                  <p className="font-display text-base font-semibold" style={{ color: "var(--text-primary)" }}>
                    {detail.shopName}
                  </p>
                  <p className="mb-3 text-xs" style={{ color: "var(--text-muted)" }}>
                    Approved PHILMART Shop / Club
                  </p>
                  <Link href={`/shop/${detail.shopID}`}>
                    <Button type="button" variant="secondary">View Shop</Button>
                  </Link>
                </Box>
              </div>

              <Box title={isAuction ? "Auction" : "Buy Now"}>
                {isAuction ? <AuctionSummary detail={detail} /> : (
                  <>
                    <p className="text-xs" style={{ color: "var(--text-muted)" }}>Item price</p>
                    <p className="mb-5 font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>
                      {formatMoney(detail.priceMinor)}
                    </p>
                  </>
                )}

                <CommitAction
                  detail={detail}
                  open={open}
                  signedIn={session?.user ?? null}
                  onStart={() => setConfirming(true)}
                />
              </Box>
            </div>

            {confirming && (
              <ConfirmModal
                detail={detail}
                methodId={methodId}
                onClose={() => setConfirming(false)}
                onDone={(message) => {
                  setConfirming(false);
                  setResult(message);
                  reload();
                }}
              />
            )}
          </>
        )}
      </main>

      <PublicFooter screenId={isAuction ? "SCR-PUB-003B" : "SCR-PUB-003A"} />
    </div>
  );
}

function ImagesAndDescription({ detail }: { detail: ListingDetail }) {
  const [current, setCurrent] = useState(0);

  return (
    <Box>
      <div
        className="mb-3 flex aspect-[4/3] items-center justify-center overflow-hidden"
        style={{ border: "1px solid var(--border-subtle)", borderRadius: 4, background: "var(--surface-sunken)" }}
      >
        {detail.images.length > 0 ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={detail.images[current]} alt={detail.title} className="max-h-full max-w-full object-contain" />
        ) : (
          <span className="text-xs" style={{ color: "var(--text-muted)" }}>No images yet</span>
        )}
      </div>
      {detail.images.length > 1 && (
        <div className="mb-4 flex gap-2">
          {detail.images.map((src, i) => (
            <button
              key={src}
              type="button"
              onClick={() => setCurrent(i)}
              className="h-14 w-16 overflow-hidden"
              style={{ border: `2px solid ${i === current ? "var(--philmart-navy-deep)" : "var(--border-subtle)"}`, borderRadius: 4 }}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={src} alt="" className="h-full w-full object-cover" />
            </button>
          ))}
        </div>
      )}

      <h2 className="mb-2 font-display text-lg font-semibold" style={{ color: "var(--text-primary)" }}>Description</h2>
      <p className="mb-4 whitespace-pre-wrap text-sm" style={{ color: "var(--text-secondary)" }}>
        {detail.description || "No description given."}
      </p>

      <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs">
        {[
          ["Reference", detail.reference],
          ["Area / Country", detail.areaCountry],
          ["Type", detail.type],
          ["Subtype", detail.subtype],
          ["Theme", detail.theme],
          ["Condition", detail.condition],
          ["Catalogue", detail.catalogueReference],
        ]
          .filter(([, v]) => v)
          .map(([k, v]) => (
            <div key={k} className="contents">
              <dt style={{ color: "var(--text-muted)" }}>{k}</dt>
              <dd style={{ color: "var(--text-primary)" }}>{v}</dd>
            </div>
          ))}
      </dl>
    </Box>
  );
}

function AuctionSummary({ detail }: { detail: ListingDetail }) {
  const left = useServerCountdown(detail.endsAt, detail.serverNow);

  return (
    <div className="mb-5">
      <p className="text-xs" style={{ color: "var(--text-muted)" }}>
        {detail.currentBidMinor ? "Current bid" : "Starting price"}
      </p>
      <p className="font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>
        {formatMoney(detail.currentBidMinor ?? detail.startingPriceMinor)}
      </p>
      <p className="mt-1 text-xs" style={{ color: "var(--text-secondary)" }}>
        {detail.bids.length} {detail.bids.length === 1 ? "bid" : "bids"} ·{" "}
        {detail.reserveMet ? "Reserve met" : "Reserve not yet met"}
      </p>
      <p className="mt-3 text-sm font-semibold" style={{ color: "var(--accent-auction)" }}>
        {detail.state === "live" ? left : `Auction ${detail.state}`}
      </p>
      {detail.softCloseSeconds && (
        <p className="text-[11px]" style={{ color: "var(--text-muted)" }}>
          A bid in the last {Math.round(detail.softCloseSeconds / 60)} minutes extends the close.
          {detail.extensionCount > 0 && ` Extended ${detail.extensionCount}×.`}
        </p>
      )}

      {detail.bids.length > 0 && (
        <details className="mt-4 text-xs" style={{ color: "var(--text-secondary)" }}>
          <summary className="cursor-pointer font-semibold">Bid history</summary>
          <ul className="mt-2">
            {detail.bids.map((b) => (
              <li key={b.sequenceNo} className="flex justify-between py-0.5">
                <span>#{b.sequenceNo}</span>
                <span>{formatMoney(b.amountMinor)}</span>
                <span>{new Date(b.placedAt).toLocaleString("en-ZA")}</span>
              </li>
            ))}
          </ul>
        </details>
      )}
    </div>
  );
}

function CommitAction({
  detail,
  open,
  signedIn,
  onStart,
}: {
  detail: ListingDetail;
  open: boolean;
  signedIn: SignedInUser | null;
  onStart: () => void;
}) {
  const label = detail.listingType === "auction" ? "Place a bid" : "Continue to purchase";

  if (!open) return <Notice>This item is no longer available.</Notice>;

  // D032: a deactivated Shop's storefront takes no new commitments
  if (!detail.shopActive && (detail.listingType !== "auction" || detail.bids.length === 0)) {
    return <Notice>This Shop isn&apos;t trading at the moment.</Notice>;
  }

  if (!signedIn) {
    return (
      <Link href="/login">
        <Button type="button">Sign in to {detail.listingType === "auction" ? "bid" : "buy"}</Button>
      </Link>
    );
  }

  if (signedIn.actorKind !== "Buy_Buyer") {
    return <Notice>Sign in with a Buyer account to buy or bid.</Notice>;
  }

  if (signedIn.registrationStep !== null) {
    return (
      <Link href="/register">
        <Button type="button">Finish registering to {detail.listingType === "auction" ? "bid" : "buy"}</Button>
      </Link>
    );
  }

  // BR-01-R09
  if (signedIn.pendingAcceptances.length > 0) {
    return (
      <Link href="/account/terms">
        <Button type="button">Review updated terms first</Button>
      </Link>
    );
  }

  return <Button type="button" onClick={onStart} disabled={!detail.commitment}>{label}</Button>;
}

function ConfirmModal({
  detail,
  methodId,
  onClose,
  onDone,
}: {
  detail: ListingDetail;
  methodId: string | null;
  onClose: () => void;
  onDone: (message: string) => void;
}) {
  const isAuction = detail.listingType === "auction";
  const method = detail.deliveryOptions.find((m) => m.id === methodId) ?? null;
  const [defaults, setDefaults] = useState<PurchaseDefaults[]>([]);
  const [pickupId, setPickupId] = useState<string | null>(null);
  const [override, setOverride] = useState<Address | null>(null);
  const [amount, setAmount] = useState(((detail.nextMinimumBidMinor ?? 0) / 100).toFixed(2));
  const [accepted, setAccepted] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [key] = useState(newIdempotencyKey);

  useEffect(() => {
    let cancelled = false;
    api.listings
      .purchaseDefaults(detail.listingID)
      .then((d) => {
        if (cancelled) return;
        setDefaults(d);
        const mine = d.find((x) => x.deliveryMethodID === methodId);
        setPickupId(mine?.pickupPointID ?? method?.pickupPoints[0]?.id ?? null);
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [detail.listingID, methodId, method]);

  const saved = defaults.find((x) => x.deliveryMethodID === methodId);
  const destination = override ?? saved?.address ?? null;

  async function confirm() {
    if (!detail.commitment || !method) return;
    setBusy(true);
    setError(null);
    try {
      if (isAuction) {
        const res = await api.listings.bid(detail.listingID, {
          commitmentVersionID: detail.commitment.versionID,
          amountMinor: Math.round(Number(amount) * 100),
          idempotencyKey: key,
        });
        onDone(
          `Your bid of ${formatMoney(res.amountMinor)} is in.` +
            (res.leading ? " You're the leading bidder." : "") +
            (res.extendedClose ? " It landed in the closing minutes, so the auction has been extended." : ""),
        );
      } else {
        const res = await api.listings.buy(detail.listingID, {
          commitmentVersionID: detail.commitment.versionID,
          deliveryMethodID: method.id,
          pickupPointID: method.requiresPickupPoint ? pickupId : null,
          address: method.requiresAddress ? override : null,
          idempotencyKey: key,
        });
        onDone(`Purchase confirmed: ${formatMoney(res.priceMinor)}, ${res.deliveryMethod}. The Shop will send your invoice.`);
      }
    } catch (e) {
      setError(errorText(e));
      setBusy(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto p-4" style={{ background: "rgb(15 23 42 / 0.5)" }} role="dialog" aria-modal="true">
      <div className="mt-10 w-full max-w-3xl p-6" style={{ background: "var(--surface-card)", borderRadius: "var(--radius-card)" }}>
        <h2 className="font-display text-2xl font-bold" style={{ color: "var(--text-primary)" }}>
          {isAuction ? "Confirm Bid" : "Confirm Purchase"}
        </h2>
        <p className="mb-5 text-xs" style={{ color: "var(--text-muted)" }}>
          {isAuction ? "Review your bid and the Shipping Method that will apply if you win." : "Review your purchase and delivery before you confirm."}
        </p>

        <ErrorNote message={error} />

        <div className="mb-4 grid grid-cols-3 gap-4 p-4 text-sm" style={{ border: "1px solid var(--border-subtle)", borderRadius: 4 }}>
          <div>
            <p className="text-[11px]" style={{ color: "var(--text-muted)" }}>Item</p>
            <p className="font-semibold" style={{ color: "var(--text-primary)" }}>{detail.title}</p>
          </div>
          <div>
            <p className="text-[11px]" style={{ color: "var(--text-muted)" }}>Shop</p>
            <p className="font-semibold" style={{ color: "var(--text-primary)" }}>{detail.shopName}</p>
          </div>
          <div>
            <p className="text-[11px]" style={{ color: "var(--text-muted)" }}>{isAuction ? "Your bid" : "Price"}</p>
            {isAuction ? (
              <input
                aria-label="Your bid in rand"
                type="number"
                step="0.01"
                min={(detail.nextMinimumBidMinor ?? 0) / 100}
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                style={inputStyle}
              />
            ) : (
              <p className="font-semibold" style={{ color: "var(--text-primary)" }}>{formatMoney(detail.priceMinor)}</p>
            )}
            {isAuction && (
              <p className="mt-1 text-[11px]" style={{ color: "var(--text-muted)" }}>
                Minimum {formatMoney(detail.nextMinimumBidMinor)}
              </p>
            )}
          </div>
        </div>

        <div className="mb-4 p-4 text-sm" style={{ border: "1px solid var(--border-subtle)", borderRadius: 4, background: "var(--surface-sunken)" }}>
          <p className="mb-1 font-semibold" style={{ color: "var(--text-primary)" }}>
            {isAuction ? "Shipping preference if you win" : "Shipping Method"}: {method?.name ?? "choose one on the item page"}
          </p>

          {method?.requiresPickupPoint && (
            <Field label="Pickup point" htmlFor="pickup">
              <select id="pickup" value={pickupId ?? ""} onChange={(e) => setPickupId(e.target.value)} style={inputStyle} disabled={isAuction}>
                {method.pickupPoints.map((p) => (
                  <option key={p.id} value={p.id}>{p.name} {p.address ? `— ${p.address}` : ""}</option>
                ))}
              </select>
            </Field>
          )}

          {method?.requiresAddress && (
            <div>
              <p className="text-xs" style={{ color: "var(--text-secondary)" }}>
                Destination: {destination ? `${destination.addressLine1}, ${destination.city}` : "no saved address"}
              </p>
              {!isAuction && (
                <AddressOverride value={override} onChange={setOverride} />
              )}
            </div>
          )}

          <p className="mt-2 text-[11px]" style={{ color: "var(--text-muted)" }}>
            A change here applies to this {isAuction ? "bid" : "purchase"} only. Your saved preferences stay as they are.
          </p>
        </div>

        {detail.commitment && (
          <div className="mb-4">
            <p className="mb-1 text-sm font-semibold" style={{ color: "var(--text-primary)" }}>
              {detail.commitment.name} <span className="text-xs font-normal" style={{ color: "var(--text-muted)" }}>version {detail.commitment.version}</span>
            </p>
            <div className="mb-2 max-h-32 overflow-y-auto whitespace-pre-wrap p-3 text-xs" style={{ border: "1px solid var(--border-subtle)", borderRadius: 4, color: "var(--text-secondary)" }}>
              {detail.commitment.body}
            </div>
            <label className="flex items-center gap-2 text-sm" style={{ color: "var(--text-primary)" }}>
              <input type="checkbox" checked={accepted} onChange={(e) => setAccepted(e.target.checked)} />
              I accept the {detail.commitment.name}
            </label>
          </div>
        )}

        <div className="grid grid-cols-2 gap-4">
          <Button type="button" variant="secondary" onClick={onClose}>Back</Button>
          <Button type="button" onClick={confirm} disabled={!accepted || busy || !method}>
            {isAuction ? "Confirm bid" : "Confirm purchase"}
          </Button>
        </div>
      </div>
    </div>
  );
}

function AddressOverride({ value, onChange }: { value: Address | null; onChange: (a: Address | null) => void }) {
  if (!value) {
    return (
      <button
        type="button"
        className="mt-1 text-xs font-semibold hover:underline"
        style={{ color: "var(--philmart-navy-deep)" }}
        onClick={() => onChange({ addressLine1: "", city: "", postalCode: "", countryCode: "ZA" })}
      >
        Send this one somewhere else
      </button>
    );
  }

  return (
    <div className="mt-2 grid grid-cols-2 gap-2">
      <input aria-label="Street address" placeholder="Street address" value={value.addressLine1} onChange={(e) => onChange({ ...value, addressLine1: e.target.value })} style={inputStyle} />
      <input aria-label="City" placeholder="City" value={value.city} onChange={(e) => onChange({ ...value, city: e.target.value })} style={inputStyle} />
      <input aria-label="Postal code" placeholder="Postal code" value={value.postalCode ?? ""} onChange={(e) => onChange({ ...value, postalCode: e.target.value })} style={inputStyle} />
      <button type="button" className="text-xs hover:underline" style={{ color: "var(--text-muted)" }} onClick={() => onChange(null)}>
        Use my saved address
      </button>
    </div>
  );
}

function Box({ title, children }: { title?: string; children: React.ReactNode }) {
  return (
    <section className="p-5" style={{ background: "var(--surface-card)", border: "1px solid var(--border-subtle)", borderRadius: "var(--radius-card)" }}>
      {title && (
        <h2 className="mb-3 font-display text-xl font-semibold" style={{ color: "var(--text-primary)" }}>{title}</h2>
      )}
      {children}
    </section>
  );
}

// counts down from the server's clock, not the device's (clause 9.2)
function useServerCountdown(endsAt: string | null, serverNow: string) {
  const [offset] = useState(() => new Date(serverNow).getTime() - Date.now());
  const [now, setNow] = useState(() => Date.now() + offset);

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now() + offset), 1000);
    return () => clearInterval(timer);
  }, [offset]);

  if (!endsAt) return null;
  const ms = new Date(endsAt).getTime() - now;
  if (ms <= 0) return "Closing…";

  const d = Math.floor(ms / 86_400_000);
  const h = Math.floor((ms % 86_400_000) / 3_600_000);
  const m = Math.floor((ms % 3_600_000) / 60_000);
  const s = Math.floor((ms % 60_000) / 1000);
  return d > 0 ? `${d}d ${h}h ${m}m left` : `${h}h ${m}m ${s}s left`;
}

// SCR-PUB-009
function SaveButton({ listingId }: { listingId: string }) {
  const [saved, setSaved] = useState<boolean | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let cancelled = false;
    api.account
      .isSaved(listingId)
      .then((r) => !cancelled && setSaved(r.saved))
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, [listingId]);

  async function toggle() {
    setBusy(true);
    try {
      if (saved) {
        await api.account.removeSaved(listingId);
        setSaved(false);
      } else {
        await api.account.save(listingId);
        setSaved(true);
      }
    } catch {
      // leave it as it was, the button still shows the real state
    } finally {
      setBusy(false);
    }
  }

  if (saved === null) return null;

  return (
    <button
      type="button"
      onClick={toggle}
      disabled={busy}
      aria-pressed={saved}
      className="px-4 py-2 text-sm font-semibold disabled:opacity-50"
      style={{
        border: "1px solid var(--philmart-navy-deep)",
        borderRadius: 4,
        background: saved ? "var(--philmart-navy-deep)" : "var(--surface-card)",
        color: saved ? "#ffffff" : "var(--philmart-navy-deep)",
      }}
    >
      {saved ? "♥ Saved" : "♡ Save item"}
    </button>
  );
}
