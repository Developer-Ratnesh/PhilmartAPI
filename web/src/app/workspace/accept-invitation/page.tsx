"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";
import { Lockup } from "@/components/brand/Lockup";
import { Button, ErrorNote, Field, inputStyle, Notice, Panel } from "@/components/ui/Form";
import { api, errorText } from "@/lib/api";

export default function AcceptInvitationPage() {
  return (
    <Suspense>
      <AcceptInvitation />
    </Suspense>
  );
}

function AcceptInvitation() {
  const token = useSearchParams().get("token") ?? "";
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [done, setDone] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function accept(e: React.FormEvent) {
    e.preventDefault();
    if (password !== confirm) {
      setError("The two passwords don't match.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await api.shop.acceptInvitation(token, password);
      setDone(true);
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center px-4" style={{ background: "var(--surface-page)" }}>
      <div className="w-full max-w-md">
        <div className="mb-6 flex justify-center">
          <Lockup />
        </div>
        <Panel>
          <h1 className="mb-4 font-display text-xl font-bold" style={{ color: "var(--text-primary)" }}>
            Join your Shop on PHILMART
          </h1>
          {done ? (
            <>
              <Notice>Your account is ready.</Notice>
              <Link href="/workspace/login"><Button type="button">Sign in</Button></Link>
            </>
          ) : (
            <form onSubmit={accept}>
              <ErrorNote message={error} />
              <Field label="Choose a password" htmlFor="pw" hint="At least 10 characters.">
                <input id="pw" type="password" required minLength={10} autoComplete="new-password" value={password} onChange={(e) => setPassword(e.target.value)} style={inputStyle} />
              </Field>
              <Field label="Type it again" htmlFor="pw2">
                <input id="pw2" type="password" required autoComplete="new-password" value={confirm} onChange={(e) => setConfirm(e.target.value)} style={inputStyle} />
              </Field>
              <Button disabled={busy || !token}>Set password</Button>
            </form>
          )}
        </Panel>
      </div>
    </div>
  );
}
