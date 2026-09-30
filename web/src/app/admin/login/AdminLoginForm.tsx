"use client";

import { useState } from "react";

// Sys_PlatformUser has PasswordHash NOT NULL and MfaSecret nullable, so admins
// sign in with a password and are then challenged for a TOTP code only if
// they have one set. That is different from the Buyer, who has no password at
// all and signs in with a 4 digit PIN (SCR-PUB-014).
//
// No auth endpoint exists yet. Submitting shows the MFA step so the layout can
// be reviewed; wiring waits on the auth decisions in the architecture record.

type Step = "credentials" | "mfa";

export function AdminLoginForm() {
  const [step, setStep] = useState<Step>("credentials");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [code, setCode] = useState("");

  function submitCredentials(e: React.FormEvent) {
    e.preventDefault();
    setStep("mfa");
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
      {step === "credentials" ? (
        <form onSubmit={submitCredentials} noValidate={false}>
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

          <SubmitButton>Sign in</SubmitButton>
        </form>
      ) : (
        <form onSubmit={(e) => e.preventDefault()}>
          <p className="mb-5 text-sm" style={{ color: "var(--text-secondary)" }}>
            Enter the 6 digit code from your authenticator app.
          </p>

          <Field label="Authentication code" htmlFor="code">
            <input
              id="code"
              name="code"
              inputMode="numeric"
              pattern="[0-9]{6}"
              maxLength={6}
              required
              autoComplete="one-time-code"
              autoFocus
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
              style={{ ...inputStyle, letterSpacing: "0.4em", fontSize: 18 }}
            />
          </Field>

          <SubmitButton>Verify and sign in</SubmitButton>

          <button
            type="button"
            onClick={() => setStep("credentials")}
            className="mt-4 w-full text-center text-xs hover:underline"
            style={{ color: "var(--text-muted)" }}
          >
            Back
          </button>
        </form>
      )}
    </div>
  );
}

const inputStyle: React.CSSProperties = {
  width: "100%",
  padding: "0.6rem 0.75rem",
  background: "var(--surface-card)",
  border: "1px solid var(--border-default)",
  borderRadius: 4,
  color: "var(--text-primary)",
};

function Field({
  label,
  htmlFor,
  children,
}: {
  label: string;
  htmlFor: string;
  children: React.ReactNode;
}) {
  return (
    <div className="mb-5">
      <label
        htmlFor={htmlFor}
        className="mb-1.5 block text-xs font-semibold"
        style={{ color: "var(--text-secondary)" }}
      >
        {label}
      </label>
      {children}
    </div>
  );
}

function SubmitButton({ children }: { children: React.ReactNode }) {
  return (
    <button
      type="submit"
      className="w-full py-3 text-sm font-bold transition-opacity hover:opacity-90"
      style={{
        background: "var(--philmart-navy-deep)",
        color: "#ffffff",
        borderRadius: 4,
      }}
    >
      {children}
    </button>
  );
}
