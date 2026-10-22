"use client";

import { useEffect, useState } from "react";
import { BuyerOnly } from "@/components/account/BuyerOnly";
import { ProfileTabs } from "@/components/account/ProfileTabs";
import { ShippingMethodsEditor, withPreferred } from "@/components/account/ShippingMethodsEditor";
import { AccountShell } from "@/components/layout/AccountShell";
import { PhysicalAddressFields } from "@/components/account/PhysicalAddressFields";
import { Button, ErrorNote, Field, inputStyle, Notice, Panel } from "@/components/ui/Form";
import { api, errorText, type BuyerProfile, type DeliveryOption, type ShippingPreference } from "@/lib/api";
import { useSession } from "@/lib/session";

// SCR-PUB-006.1 Personal Details & Delivery Addresses
export default function ProfilePage() {
  const session = useSession();
  const isBuyer = session?.user.actorKind === "Buy_Buyer";
  const [profile, setProfile] = useState<BuyerProfile | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [version, setVersion] = useState(0);

  useEffect(() => {
    if (!isBuyer) return;
    let cancelled = false;
    api.account
      .profile()
      .then((p) => !cancelled && setProfile(p))
      .catch((e) => !cancelled && setError(errorText(e)));
    return () => {
      cancelled = true;
    };
  }, [isBuyer, version]);

  return (
    <AccountShell screenId="SCR-PUB-006.1">
      <BuyerOnly>
        <h1 className="font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>
          Personal Details &amp; Delivery Addresses
        </h1>
        <p className="mt-1 text-sm" style={{ color: "var(--text-secondary)" }}>
          Manage your contact details and your delivery address and defaults.
        </p>

        <ProfileTabs />
        <ErrorNote message={error} />

        {profile && (
          <div className="grid gap-6 lg:grid-cols-2">
            <PersonalPanel profile={profile} onSaved={() => setVersion((v) => v + 1)} />
            <AddressPanel profile={profile} onSaved={() => setVersion((v) => v + 1)} />
          </div>
        )}
      </BuyerOnly>
    </AccountShell>
  );
}

function ReadOnly({ label, value }: { label: string; value: string | null }) {
  return (
    <div className="mb-4">
      <p className="mb-1 text-xs font-semibold" style={{ color: "var(--text-secondary)" }}>
        {label}
      </p>
      <p
        className="flex items-center justify-between px-3 py-2.5 text-sm"
        style={{ background: "var(--surface-sunken)", border: "1px solid var(--border-subtle)", borderRadius: 4, color: "var(--text-primary)" }}
      >
        <span>{value || "Not given"}</span>
        <span className="text-[11px]" style={{ color: "var(--text-muted)" }}>
          Read-only
        </span>
      </p>
    </div>
  );
}

function PersonalPanel({ profile, onSaved }: { profile: BuyerProfile; onSaved: () => void }) {
  const [mobile, setMobile] = useState(profile.mobile ?? "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setSaved(false);
    try {
      await api.account.updateMobile(mobile);
      setSaved(true);
      onSaved();
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  const idType = profile.identificationType === "sa_id" ? "SA ID" : profile.identificationType === "passport" ? "Passport" : null;

  return (
    <Panel>
      <h2 className="mb-4 font-display text-xl font-semibold" style={{ color: "var(--text-primary)" }}>
        Personal Details
      </h2>
      <form onSubmit={save}>
        <ErrorNote message={error} />
        {saved && <Notice>Your mobile number has been saved.</Notice>}

        <ReadOnly label="Full name" value={profile.fullName} />
        <ReadOnly label="Email address" value={profile.email} />

        <Field label="Mobile number" htmlFor="mobile">
          <input id="mobile" type="tel" value={mobile} onChange={(e) => setMobile(e.target.value)} style={inputStyle} />
        </Field>

        <div className="grid gap-x-4 sm:grid-cols-2">
          <ReadOnly label="ID type" value={idType} />
          <ReadOnly label="ID or passport number" value={profile.identificationNumber} />
        </div>
        <ReadOnly label="Date of birth" value={profile.dateOfBirth} />

        {/* D039 */}
        <p className="mb-5 text-xs" style={{ color: "var(--text-muted)" }}>
          Your name, identity details and date of birth are kept as registered and can&apos;t be changed here. Contact PHILMART Support if something is wrong.
        </p>

        <Button disabled={busy || mobile === (profile.mobile ?? "")} wide={false}>
          Save Changes
        </Button>
      </form>
    </Panel>
  );
}

function AddressPanel({ profile, onSaved }: { profile: BuyerProfile; onSaved: () => void }) {
  const [address, setAddress] = useState({
    addressLine1: profile.address?.addressLine1 ?? "",
    addressLine2: profile.address?.addressLine2 ?? "",
    city: profile.address?.city ?? "",
    province: profile.address?.province ?? "",
    postalCode: profile.address?.postalCode ?? "",
    countryCode: profile.address?.countryCode ?? "ZA",
  });
  const [methods, setMethods] = useState<DeliveryOption[]>([]);
  const [prefs, setPrefs] = useState<Record<string, ShippingPreference>>({});
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    let cancelled = false;
    api.register
      .deliveryOptions()
      .then((list) => {
        if (cancelled) return;
        setMethods(list);
        // start from what they have, a method added since starts switched off
        const initial: Record<string, ShippingPreference> = {};
        for (const m of list) {
          const mine = profile.shippingPreferences.find((p) => p.deliveryMethodID === m.id);
          initial[m.id] = {
            deliveryMethodID: m.id,
            available: mine?.available ?? false,
            pickupPointID: m.requiresPickupPoint ? (mine?.pickupPointID ?? m.pickupPoints[0]?.id ?? null) : null,
            useAddress: m.requiresAddress || (mine?.useAddress ?? false),
            preferred: mine?.preferred ?? false,
          };
        }
        setPrefs(withPreferred(initial, list));
      })
      .catch((err) => !cancelled && setError(errorText(err)));
    return () => {
      cancelled = true;
    };
  }, [profile]);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setSaved(false);
    try {
      await api.account.updateAddress({ ...address, shippingPreferences: Object.values(prefs) });
      setSaved(true);
      onSaved();
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }


  return (
    <Panel>
      <h2 className="mb-4 font-display text-xl font-semibold" style={{ color: "var(--text-primary)" }}>
        Delivery Address &amp; Defaults
      </h2>
      <form onSubmit={save}>
        <ErrorNote message={error} />
        {saved && <Notice>Saved. Your next purchase will use these details.</Notice>}

        <PhysicalAddressFields value={address} onChange={setAddress} />

        <h3 className="mb-2 mt-2 font-display text-base font-semibold" style={{ color: "var(--text-primary)" }}>
          Delivery methods
        </h3>
        <p className="mb-4 text-xs" style={{ color: "var(--text-muted)" }}>
          The methods that work where you live. These are the defaults at purchase; you can still change them for a single order.
        </p>

        <ShippingMethodsEditor methods={methods} prefs={prefs} onChange={setPrefs} />

        <p className="mb-5 text-xs" style={{ color: "var(--text-muted)" }}>
          Changes apply to future purchases only. Orders already placed keep the address they were placed with.
        </p>

        <Button disabled={busy} wide={false}>
          Save Changes
        </Button>
      </form>
    </Panel>
  );
}
