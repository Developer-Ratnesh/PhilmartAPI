"use client";

import { useEffect, useState } from "react";
import { BuyerOnly } from "@/components/account/BuyerOnly";
import { ProfileTabs } from "@/components/account/ProfileTabs";
import { AccountShell } from "@/components/layout/AccountShell";
import { Button, ErrorNote, Notice, Panel } from "@/components/ui/Form";
import { api, errorText } from "@/lib/api";
import { useSession } from "@/lib/session";

// SCR-PUB-006.3. D040: the outbid alert is the only optional email so far.
// Auction Event notifications come with auction events (Milestone 4).
export default function PreferencesPage() {
  const session = useSession();
  const isBuyer = session?.user.actorKind === "Buy_Buyer";
  const [outbid, setOutbid] = useState<boolean | null>(null);
  const [savedValue, setSavedValue] = useState<boolean | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    if (!isBuyer) return;
    let cancelled = false;
    api.account
      .preferences()
      .then((p) => {
        if (cancelled) return;
        setOutbid(p.outbidAlerts);
        setSavedValue(p.outbidAlerts);
      })
      .catch((e) => !cancelled && setError(errorText(e)));
    return () => {
      cancelled = true;
    };
  }, [isBuyer]);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (outbid === null) return;
    setBusy(true);
    setError(null);
    setSaved(false);
    try {
      await api.account.savePreferences({ outbidAlerts: outbid });
      setSavedValue(outbid);
      setSaved(true);
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <AccountShell screenId="SCR-PUB-006.3">
      <BuyerOnly>
        <h1 className="font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>
          Communication Preferences
        </h1>
        <p className="mt-1 text-sm" style={{ color: "var(--text-secondary)" }}>
          Choose which optional auction emails you would like to receive.
        </p>

        <ProfileTabs />
        <ErrorNote message={error} />

        <div className="grid gap-6 lg:grid-cols-[2fr_1fr]">
          <Panel>
            <form onSubmit={save}>
              <h2 className="font-display text-xl font-semibold" style={{ color: "var(--text-primary)" }}>
                Auction Email Notifications
              </h2>
              <p className="mb-5 mt-1 text-xs" style={{ color: "var(--text-muted)" }}>
                These are optional and can be changed at any time.
              </p>

              {saved && <Notice>Your preferences have been saved.</Notice>}

              <label className="mb-6 flex items-start gap-3" style={{ color: "var(--text-primary)" }}>
                <input
                  type="checkbox"
                  className="mt-1"
                  disabled={outbid === null}
                  checked={outbid ?? false}
                  onChange={(e) => setOutbid(e.target.checked)}
                />
                <span>
                  <span className="block text-sm font-semibold">Outbid notification</span>
                  <span className="block text-xs" style={{ color: "var(--text-muted)" }}>
                    Email me when another bidder goes above my current bid.
                  </span>
                </span>
              </label>

              <Button disabled={busy || outbid === null || outbid === savedValue} wide={false}>
                Save Changes
              </Button>
            </form>
          </Panel>

          <aside className="p-5" style={{ background: "var(--accent-info-bg)", border: "1px solid var(--border-subtle)", borderRadius: "var(--radius-card)" }}>
            <h2 className="font-display text-lg font-semibold" style={{ color: "var(--text-primary)" }}>
              Essential Emails
            </h2>
            <p className="mt-2 text-sm font-semibold" style={{ color: "var(--text-primary)" }}>
              Account and transaction emails can&apos;t be turned off.
            </p>
            <p className="mt-2 text-xs leading-relaxed" style={{ color: "var(--text-secondary)" }}>
              Sign-in PINs, purchase and auction results, invoices, payment and delivery updates are needed for your account and
              your purchases, so they are always sent.
            </p>
          </aside>
        </div>
      </BuyerOnly>
    </AccountShell>
  );
}
