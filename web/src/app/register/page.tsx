"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { PublicFooter, PublicHeader } from "@/components/layout/PublicHeader";
import { Button, ErrorNote, Field, inputStyle, Notice, Panel, PinInput, StepHeading } from "@/components/ui/Form";
import { api, errorText, type DeliveryOption, type LegalDocument, type ShippingPreference } from "@/lib/api";
import { saveSession, updateUser, useSession } from "@/lib/session";

// BR-01. SCR-PUB-014.1 to 014.4. The buyer is registered only when step 4 is
// accepted, and only then does the welcome email go (D036).
const STEPS = ["Buyer Registration", "Personal Details", "Address Details", "Review and Accept"];
const SCREENS = ["SCR-PUB-014.1", "SCR-PUB-014.2", "SCR-PUB-014.4", "SCR-PUB-014.3"];

export default function RegisterPage() {
  const session = useSession();
  const signedInBuyer = session?.user.actorKind === "Buy_Buyer" ? session.user : null;

  const [serverStep, setServerStep] = useState<number | null>(null);
  const [viewStep, setViewStep] = useState<number | null>(null);
  const [done, setDone] = useState(false);

  useEffect(() => {
    if (!signedInBuyer) return;
    let cancelled = false;

    api.register
      .state()
      .then((s) => {
        if (cancelled) return;
        if (s.completed) setDone(true);
        setServerStep(s.step);
      })
      .catch(() => {});

    return () => {
      cancelled = true;
    };
  }, [signedInBuyer]);

  const step = !signedInBuyer ? 1 : (viewStep ?? serverStep ?? 2);

  function advance(next: number) {
    setServerStep((s) => Math.max(s ?? 1, next));
    setViewStep(next);
  }

  return (
    <div className="flex min-h-screen flex-col" style={{ background: "var(--surface-marketplace)" }}>
      <PublicHeader />

      <main className="mx-auto w-full max-w-2xl flex-1 px-4 py-10">
        <h1 className="font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>
          Create Buyer Account
        </h1>
        <p className="mb-6 text-sm" style={{ color: "var(--text-secondary)" }}>
          Buyer Registration — Step {done ? 4 : step} of 4 · {STEPS[(done ? 4 : step) - 1]}
        </p>

        <ol className="mb-6 grid grid-cols-4 gap-2" aria-label="Registration steps">
          {STEPS.map((label, i) => {
            const reached = done || i + 1 <= step;
            return (
              <li
                key={label}
                className="px-2 py-2 text-center text-[11px] font-semibold"
                style={{
                  borderBottom: `3px solid ${reached ? "var(--philmart-navy-deep)" : "var(--border-subtle)"}`,
                  color: reached ? "var(--text-primary)" : "var(--text-muted)",
                }}
              >
                {i + 1}. {label}
              </li>
            );
          })}
        </ol>

        {done ? (
          <Panel>
            <h2 className="mb-2 font-display text-xl font-semibold" style={{ color: "var(--text-primary)" }}>
              You&apos;re registered
            </h2>
            <p className="mb-5 text-sm" style={{ color: "var(--text-secondary)" }}>
              Your Buyer account is ready. We&apos;ve sent you a welcome email. You can now buy and bid on the marketplace.
            </p>
            <Link href="/marketplace">
              <Button type="button">Go to the marketplace</Button>
            </Link>
          </Panel>
        ) : step === 1 ? (
          <EmailStep />
        ) : step === 2 ? (
          <PersonalStep onDone={() => advance(3)} />
        ) : step === 3 ? (
          <AddressStep onBack={() => setViewStep(2)} onDone={() => advance(4)} />
        ) : (
          <ReviewStep onBack={() => setViewStep(3)} onDone={() => setDone(true)} />
        )}
      </main>

      <PublicFooter screenId={SCREENS[(done ? 4 : step) - 1]} />
    </div>
  );
}

function EmailStep() {
  const [email, setEmail] = useState("");
  const [challenge, setChallenge] = useState<string | null>(null);
  const [pin, setPin] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function send(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      setChallenge((await api.register.start(email)).challenge);
      setPin("");
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  async function verify(e: React.FormEvent) {
    e.preventDefault();
    if (!challenge) return;
    setBusy(true);
    setError(null);
    try {
      const res = await api.register.verify(challenge, pin);
      saveSession(res.token, res.user);
    } catch (err) {
      setError(errorText(err));
      setBusy(false);
    }
  }

  return (
    <Panel>
      <ErrorNote message={error} />

      <form onSubmit={send}>
        <StepHeading number={1} title="Enter your email" />
        <Field label="Email" htmlFor="email" hint="If the email address can be used to continue, a 4-digit PIN will be sent.">
          <input
            id="email"
            type="email"
            required
            autoFocus
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="name@example.com"
            style={inputStyle}
          />
        </Field>
        <Button disabled={busy || !email}>{challenge ? "Resend verification PIN" : "Send verification PIN"}</Button>
      </form>

      <p className="my-5 text-center text-xs font-semibold" style={{ color: "var(--text-muted)" }}>
        THEN
      </p>

      <form onSubmit={verify}>
        <StepHeading number={2} title="Enter your 4-digit PIN" muted={!challenge} />
        <p className="mb-4 text-xs" style={{ color: "var(--text-muted)" }}>
          {challenge ? "Enter the PIN we emailed you. Verifying your email lets you continue. It doesn't complete registration." : "Send a verification PIN first."}
        </p>
        <PinInput value={pin} onChange={setPin} disabled={!challenge || busy} />
        <Button disabled={!challenge || pin.length !== 4 || busy}>Verify email and continue</Button>
      </form>

      <p className="mt-6 text-center text-xs" style={{ color: "var(--text-muted)" }}>
        Already registered?{" "}
        <Link href="/login" className="font-semibold hover:underline" style={{ color: "var(--philmart-navy-deep)" }}>
          Sign in
        </Link>
      </p>
    </Panel>
  );
}

function PersonalStep({ onDone }: { onDone: () => void }) {
  const [form, setForm] = useState({
    fullName: "",
    mobile: "",
    identificationType: "sa_id",
    identificationNumber: "",
    dateOfBirth: "",
  });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await api.register.personal(form);
      onDone();
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  const set = (key: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setForm((f) => ({ ...f, [key]: e.target.value }));

  return (
    <Panel>
      <form onSubmit={save}>
        <ErrorNote message={error} />
        <Notice>Your identification details become read-only once registration is complete.</Notice>

        <Field label="Full name" htmlFor="fullName">
          <input id="fullName" required value={form.fullName} onChange={set("fullName")} style={inputStyle} />
        </Field>
        <Field label="Mobile number" htmlFor="mobile">
          <input id="mobile" type="tel" value={form.mobile} onChange={set("mobile")} style={inputStyle} />
        </Field>
        <Field label="Identification type" htmlFor="idType">
          <select id="idType" value={form.identificationType} onChange={set("identificationType")} style={inputStyle}>
            <option value="sa_id">South African ID</option>
            <option value="passport">Passport</option>
          </select>
        </Field>
        <Field label={form.identificationType === "passport" ? "Passport number" : "ID number"} htmlFor="idNumber">
          <input id="idNumber" required value={form.identificationNumber} onChange={set("identificationNumber")} style={inputStyle} />
        </Field>
        <Field label="Date of birth" htmlFor="dob">
          <input id="dob" type="date" required value={form.dateOfBirth} onChange={set("dateOfBirth")} style={inputStyle} />
        </Field>

        <Button disabled={busy}>Save and continue</Button>
      </form>
    </Panel>
  );
}

function AddressStep({ onBack, onDone }: { onBack: () => void; onDone: () => void }) {
  const [address, setAddress] = useState({ addressLine1: "", addressLine2: "", city: "", province: "", postalCode: "", countryCode: "ZA" });
  const [methods, setMethods] = useState<DeliveryOption[]>([]);
  const [prefs, setPrefs] = useState<Record<string, ShippingPreference>>({});
  const [outbidAlerts, setOutbidAlerts] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    api.register
      .deliveryOptions()
      .then((list) => {
        if (cancelled) return;
        setMethods(list);
        const initial: Record<string, ShippingPreference> = {};
        for (const m of list) {
          initial[m.id] = {
            deliveryMethodID: m.id,
            available: true,
            pickupPointID: m.requiresPickupPoint ? (m.pickupPoints[0]?.id ?? null) : null,
            useAddress: m.requiresAddress,
          };
        }
        setPrefs(initial);
      })
      .catch((err) => !cancelled && setError(errorText(err)));
    return () => {
      cancelled = true;
    };
  }, []);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await api.register.address({ ...address, shippingPreferences: Object.values(prefs), outbidAlerts });
      onDone();
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  const set = (key: keyof typeof address) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setAddress((a) => ({ ...a, [key]: e.target.value }));

  return (
    <Panel>
      <form onSubmit={save}>
        <ErrorNote message={error} />

        <Field label="Street address" htmlFor="line1">
          <input id="line1" required value={address.addressLine1} onChange={set("addressLine1")} style={inputStyle} />
        </Field>
        <Field label="Suburb or complex (optional)" htmlFor="line2">
          <input id="line2" value={address.addressLine2} onChange={set("addressLine2")} style={inputStyle} />
        </Field>
        <div className="grid grid-cols-2 gap-4">
          <Field label="City" htmlFor="city">
            <input id="city" required value={address.city} onChange={set("city")} style={inputStyle} />
          </Field>
          <Field label="Postal code" htmlFor="postal">
            <input id="postal" value={address.postalCode} onChange={set("postalCode")} style={inputStyle} />
          </Field>
        </div>
        <Field label="Province" htmlFor="province">
          <input id="province" value={address.province} onChange={set("province")} style={inputStyle} />
        </Field>

        <h3 className="mb-2 mt-6 font-display text-base font-semibold" style={{ color: "var(--text-primary)" }}>
          Shipping preferences
        </h3>
        <p className="mb-4 text-xs" style={{ color: "var(--text-muted)" }}>
          Tell us which methods work where you live. Your choice here becomes the default at purchase, and you can change it for any single order.
        </p>

        {methods.length === 0 && <Notice>No delivery methods are set up yet.</Notice>}

        {methods.map((m) => {
          const pref = prefs[m.id];
          if (!pref) return null;
          return (
            <div key={m.id} className="mb-3 p-3" style={{ border: "1px solid var(--border-subtle)", borderRadius: 4 }}>
              <label className="flex items-center gap-2 text-sm font-semibold" style={{ color: "var(--text-primary)" }}>
                <input
                  type="checkbox"
                  checked={pref.available}
                  onChange={(e) => setPrefs((p) => ({ ...p, [m.id]: { ...pref, available: e.target.checked } }))}
                />
                {m.name}
              </label>
              {pref.available && m.requiresPickupPoint && (
                <select
                  aria-label={`Default pickup point for ${m.name}`}
                  className="mt-2"
                  value={pref.pickupPointID ?? ""}
                  onChange={(e) => setPrefs((p) => ({ ...p, [m.id]: { ...pref, pickupPointID: e.target.value } }))}
                  style={inputStyle}
                >
                  {m.pickupPoints.map((pp) => (
                    <option key={pp.id} value={pp.id}>
                      {pp.name} {pp.address ? `— ${pp.address}` : ""}
                    </option>
                  ))}
                </select>
              )}
              {pref.available && m.requiresAddress && (
                <p className="mt-1 text-xs" style={{ color: "var(--text-muted)" }}>
                  Delivered to the address above.
                </p>
              )}
            </div>
          );
        })}

        <h3 className="mb-2 mt-6 font-display text-base font-semibold" style={{ color: "var(--text-primary)" }}>
          Communication
        </h3>
        <label className="mb-2 flex items-center gap-2 text-sm" style={{ color: "var(--text-primary)" }}>
          <input type="checkbox" checked={outbidAlerts} onChange={(e) => setOutbidAlerts(e.target.checked)} />
          Email me when I&apos;m outbid on an auction
        </label>
        <p className="mb-6 text-xs" style={{ color: "var(--text-muted)" }}>
          Purchase, payment, delivery, account and security emails are always sent.
        </p>

        <div className="grid grid-cols-2 gap-4">
          <Button type="button" variant="secondary" onClick={onBack}>
            Back
          </Button>
          <Button disabled={busy}>Save and continue</Button>
        </div>
      </form>
    </Panel>
  );
}

function ReviewStep({ onBack, onDone }: { onBack: () => void; onDone: () => void }) {
  const [docs, setDocs] = useState<LegalDocument[]>([]);
  const [ticked, setTicked] = useState<Record<string, boolean>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    api.register
      .legal()
      .then((d) => !cancelled && setDocs(d))
      .catch((err) => !cancelled && setError(errorText(err)));
    return () => {
      cancelled = true;
    };
  }, []);

  async function accept(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      // the exact versions shown go back with the acceptance (BR-01-R04)
      await api.register.accept(docs.map((d) => d.versionID));
      updateUser(await api.auth.me());
      onDone();
    } catch (err) {
      setError(errorText(err));
      setBusy(false);
    }
  }

  const allTicked = docs.length > 0 && docs.every((d) => ticked[d.versionID]);

  return (
    <Panel>
      <form onSubmit={accept}>
        <ErrorNote message={error} />

        {docs.map((d) => (
          <div key={d.versionID} className="mb-4">
            <h3 className="font-display text-base font-semibold" style={{ color: "var(--text-primary)" }}>
              {d.name} <span className="text-xs font-normal" style={{ color: "var(--text-muted)" }}>version {d.version}</span>
            </h3>
            <div
              className="my-2 max-h-40 overflow-y-auto whitespace-pre-wrap p-3 text-xs"
              style={{ border: "1px solid var(--border-subtle)", borderRadius: 4, color: "var(--text-secondary)" }}
            >
              {d.body}
            </div>
            <label className="flex items-center gap-2 text-sm" style={{ color: "var(--text-primary)" }}>
              <input
                type="checkbox"
                checked={!!ticked[d.versionID]}
                onChange={(e) => setTicked((t) => ({ ...t, [d.versionID]: e.target.checked }))}
              />
              {d.acceptanceMode === "acknowledge" ? `I acknowledge the ${d.name}` : `I accept the ${d.name}`}
            </label>
          </div>
        ))}

        <div className="mt-6 grid grid-cols-2 gap-4">
          <Button type="button" variant="secondary" onClick={onBack}>
            Back
          </Button>
          <Button disabled={!allTicked || busy}>Accept and complete registration</Button>
        </div>
      </form>
    </Panel>
  );
}
