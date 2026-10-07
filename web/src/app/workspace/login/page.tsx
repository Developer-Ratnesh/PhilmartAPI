"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { Lockup } from "@/components/brand/Lockup";
import { Button, ErrorNote, Field, inputStyle, Panel } from "@/components/ui/Form";
import { api, errorText } from "@/lib/api";
import { saveSession } from "@/lib/session";

// Shop users sign in with a password, set when they accepted their invitation.
// The reference is only asked for when the same email works at two Shops.
export default function WorkspaceLoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [shopReference, setShopReference] = useState("");
  const [needsShop, setNeedsShop] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function signIn(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await api.auth.login(email, password, "shop", shopReference || undefined);
      saveSession(res.token, res.user);
      router.push(res.user.permissions.includes("auction.manage") ? "/workspace/auctions" : "/workspace/users");
    } catch (err) {
      const message = errorText(err);
      if (message.includes("more than one Shop")) setNeedsShop(true);
      setError(message);
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
        <h1 className="mb-1 text-center font-display text-2xl font-bold" style={{ color: "var(--text-primary)" }}>
          Shop Workspace
        </h1>
        <p className="mb-6 text-center text-sm" style={{ color: "var(--text-secondary)" }}>
          Sign in to manage your Shop.
        </p>

        <Panel>
          <form onSubmit={signIn}>
            <ErrorNote message={error} />
            <Field label="Email address" htmlFor="email">
              <input id="email" type="email" required autoFocus autoComplete="username" value={email} onChange={(e) => setEmail(e.target.value)} style={inputStyle} />
            </Field>
            <Field label="Password" htmlFor="password">
              <input id="password" type="password" required autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} style={inputStyle} />
            </Field>
            {needsShop && (
              <Field label="Shop reference" htmlFor="shop" hint="Shown on your invitation email.">
                <input id="shop" value={shopReference} onChange={(e) => setShopReference(e.target.value)} style={inputStyle} />
              </Field>
            )}
            <Button disabled={busy}>Sign in</Button>
          </form>
        </Panel>
      </div>
    </div>
  );
}
