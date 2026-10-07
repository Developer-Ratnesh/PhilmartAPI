"use client";

import { useRef, type ReactNode } from "react";

export const inputStyle: React.CSSProperties = {
  width: "100%",
  padding: "0.6rem 0.75rem",
  background: "var(--surface-card)",
  border: "1px solid var(--border-default)",
  borderRadius: 4,
  color: "var(--text-primary)",
};

export function Field({
  label,
  htmlFor,
  hint,
  children,
}: {
  label: string;
  htmlFor: string;
  hint?: string;
  children: ReactNode;
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
      {hint && (
        <p className="mt-1.5 text-xs" style={{ color: "var(--text-muted)" }}>
          {hint}
        </p>
      )}
    </div>
  );
}

export function Button({
  children,
  type = "submit",
  variant = "primary",
  disabled,
  onClick,
  wide = true,
}: {
  children: ReactNode;
  type?: "submit" | "button";
  variant?: "primary" | "secondary" | "danger";
  disabled?: boolean;
  onClick?: () => void;
  wide?: boolean;
}) {
  const colours = {
    primary: { background: "var(--philmart-navy-deep)", color: "#ffffff", border: "1px solid var(--philmart-navy-deep)" },
    secondary: { background: "var(--surface-card)", color: "var(--philmart-navy-deep)", border: "1px solid var(--philmart-navy-deep)" },
    danger: { background: "var(--accent-danger)", color: "#ffffff", border: "1px solid var(--accent-danger)" },
  }[variant];

  return (
    <button
      type={type}
      disabled={disabled}
      onClick={onClick}
      className={`${wide ? "w-full" : "px-5"} py-3 text-sm font-bold transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-40`}
      style={{ ...colours, borderRadius: 4 }}
    >
      {children}
    </button>
  );
}

export function ErrorNote({ message }: { message: string | null }) {
  if (!message) return null;

  return (
    <p
      role="alert"
      className="mb-4 px-3 py-2 text-sm"
      style={{
        color: "var(--accent-danger)",
        border: "1px solid var(--accent-danger)",
        borderRadius: 4,
        background: "var(--surface-card)",
      }}
    >
      {message}
    </p>
  );
}

export function Notice({ children }: { children: ReactNode }) {
  return (
    <p
      className="mb-4 px-3 py-2 text-sm"
      style={{
        color: "var(--text-primary)",
        border: "1px solid var(--border-subtle)",
        borderRadius: 4,
        background: "var(--surface-card-warm)",
      }}
    >
      {children}
    </p>
  );
}

// the four boxes on SCR-PUB-014 and 014.1
export function PinInput({
  value,
  onChange,
  disabled,
}: {
  value: string;
  onChange: (pin: string) => void;
  disabled?: boolean;
}) {
  const boxes = useRef<(HTMLInputElement | null)[]>([]);
  const digits = value.padEnd(4, " ").slice(0, 4).split("");

  function set(index: number, digit: string) {
    const next = digits.slice();
    next[index] = digit || " ";
    onChange(next.join("").replace(/\s+$/, ""));

    if (digit && index < 3) {
      boxes.current[index + 1]?.focus();
    }
  }

  return (
    <div className="mb-5 flex justify-center gap-4" aria-label="4-digit PIN">
      {digits.map((d, i) => (
        <input
          key={i}
          ref={(el) => {
            boxes.current[i] = el;
          }}
          aria-label={`PIN digit ${i + 1}`}
          inputMode="numeric"
          maxLength={1}
          disabled={disabled}
          value={d.trim()}
          onChange={(e) => set(i, e.target.value.replace(/\D/g, "").slice(-1))}
          onKeyDown={(e) => {
            if (e.key === "Backspace" && !d.trim() && i > 0) {
              boxes.current[i - 1]?.focus();
            }
          }}
          onPaste={(e) => {
            const pasted = e.clipboardData.getData("text").replace(/\D/g, "").slice(0, 4);
            if (pasted) {
              e.preventDefault();
              onChange(pasted);
            }
          }}
          className="h-14 w-14 text-center text-xl font-bold disabled:opacity-40"
          style={{ ...inputStyle, width: 56, padding: 0 }}
        />
      ))}
    </div>
  );
}

export function Panel({ children }: { children: ReactNode }) {
  return (
    <div
      className="p-6"
      style={{
        background: "var(--surface-card)",
        border: "1px solid var(--border-subtle)",
        borderRadius: "var(--radius-card)",
        boxShadow: "var(--shadow-card)",
      }}
    >
      {children}
    </div>
  );
}

export function StepHeading({ number, title, muted }: { number: number; title: string; muted?: boolean }) {
  return (
    <h2 className="mb-4 flex items-center gap-3 font-display text-lg font-semibold" style={{ color: muted ? "var(--text-muted)" : "var(--text-primary)" }}>
      <span
        className="flex h-8 w-8 items-center justify-center rounded-full text-sm text-white"
        style={{ background: muted ? "var(--text-muted)" : "var(--philmart-navy-deep)" }}
      >
        {number}
      </span>
      {title}
    </h2>
  );
}
