"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState } from "react";
import { PublicFooter, PublicHeader } from "@/components/layout/PublicHeader";
import { Button, ErrorNote, Field, inputStyle, Notice, Panel, PinInput, StepHeading } from "@/components/ui/Form";
import { api, errorText } from "@/lib/api";
import { saveSession } from "@/lib/session";

// SCR-PUB-014. Buyers have no password, every sign-in is an emailed PIN.
export default function BuyerLoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [challenge, setChallenge] = useState<string | null>(null);
  const [pin, setPin] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function sendPin(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await api.auth.buyerPin(email);
      setChallenge(res.challenge);
      setPin("");
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  async function signIn(e: React.FormEvent) {
    e.preventDefault();
    if (!challenge) return;
    setBusy(true);
    setError(null);
    try {
      const res = await api.auth.buyerVerify(challenge, pin);
      saveSession(res.token, res.user);

      // a registration left half way carries on where it stopped
      if (res.user.registrationStep !== null) {
        router.push("/register");
      } else {
        router.push("/marketplace");
      }
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex min-h-screen flex-col" style={{ background: "var(--surface-marketplace)" }}>
      <PublicHeader />

      <main className="mx-auto w-full max-w-xl flex-1 px-4 py-10">
        <div className="mb-6 flex items-end justify-between gap-4">
          <div>
            <h1 className="font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>
              Buyer Login
            </h1>
            <p className="text-sm" style={{ color: "var(--text-secondary)" }}>
              Sign in to access your Buyer account.
            </p>
          </div>
          <Link href="/register" className="text-xs font-bold hover:underline" style={{ color: "var(--philmart-navy-deep)" }}>
            New Buyer? Create Buyer Account
          </Link>
        </div>

        <Panel>
          <ErrorNote message={error} />

          <form onSubmit={sendPin}>
            <StepHeading number={1} title="Enter your registered email" />
            <Field label="Registered Email" htmlFor="email" hint="If the email address is registered, a 4-digit PIN will be sent.">
              <input
                id="email"
                type="email"
                required
                autoComplete="email"
                autoFocus
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="name@example.com"
                style={inputStyle}
              />
            </Field>
            <Button disabled={busy || !email}>{challenge ? "Resend PIN" : "Send sign-in PIN"}</Button>
          </form>

          <p className="my-5 text-center text-xs font-semibold" style={{ color: "var(--text-muted)" }}>
            THEN
          </p>

          <form onSubmit={signIn}>
            <StepHeading number={2} title="Enter your 4-digit PIN" muted={!challenge} />
            {challenge ? (
              <Notice>Enter the PIN sent to your registered email. It expires in 10 minutes.</Notice>
            ) : (
              <p className="mb-4 text-xs" style={{ color: "var(--text-muted)" }}>
                Send a sign-in PIN first.
              </p>
            )}
            <PinInput value={pin} onChange={setPin} disabled={!challenge || busy} />
            <Button disabled={!challenge || pin.length !== 4 || busy}>Sign in</Button>
          </form>
        </Panel>

        <p className="mt-6 text-center text-xs" style={{ color: "var(--text-muted)" }}>
          A Shop or Club user?{" "}
          <Link href="/workspace/login" className="font-semibold hover:underline" style={{ color: "var(--philmart-navy-deep)" }}>
            Sign in to your Shop workspace
          </Link>
        </p>
      </main>

      <PublicFooter screenId="SCR-PUB-014" />
    </div>
  );
}
