"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { Button, ErrorNote, Field, inputStyle } from "@/components/ui/Form";
import { api, errorText } from "@/lib/api";
import { saveSession } from "@/lib/session";

// Admins sign in with a password. The MFA step isn't built yet, it's on the
// known issues list.
export function AdminLoginForm() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await api.auth.login(email, password, "admin");
      saveSession(res.token, res.user);
      router.push("/admin");
    } catch (err) {
      setError(errorText(err));
      setBusy(false);
    }
  }

  return (
    <div
      className="mt-7 p-6"
      style={{
        background: "var(--surface-card)",
        border: "1px solid var(--border-subtle)",
        borderRadius: "var(--radius-card)",
        boxShadow: "var(--shadow-card)",
      }}
    >
      <form onSubmit={submit}>
        <ErrorNote message={error} />

        <Field label="Email address" htmlFor="email">
          <input
            id="email"
            name="email"
            type="email"
            required
            autoComplete="username"
            autoFocus
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="name@philmart.co.za"
            style={inputStyle}
          />
        </Field>

        <Field label="Password" htmlFor="password">
          <input
            id="password"
            name="password"
            type="password"
            required
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            style={inputStyle}
          />
        </Field>

        <Button disabled={busy}>Sign in</Button>
      </form>
    </div>
  );
}
