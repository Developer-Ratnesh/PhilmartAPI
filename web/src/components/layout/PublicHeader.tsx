"use client";

import Link from "next/link";
import { useTheme } from "@/lib/theme";

function Logo() {
  return (
    <Link href="/" className="flex items-center gap-3" aria-label="PHILMART home">
      <span
        className="flex h-11 w-11 shrink-0 items-center justify-center font-display text-lg font-bold"
        style={{
          background: "var(--philmart-navy)",
          color: "var(--philmart-gold)",
          border: "2px solid var(--philmart-gold)",
          borderRadius: 3,
        }}
        aria-hidden
      >
        PM
      </span>
      <span className="leading-tight">
        <span className="block font-display text-xl font-bold tracking-wide">
          <span style={{ color: "var(--philmart-navy)" }}>PHIL</span>
          <span style={{ color: "var(--philmart-gold)" }}>MART</span>
        </span>
        <span className="block text-[9px]" style={{ color: "var(--text-muted)" }}>
          South Africa&rsquo;s Philatelic Marketplace &amp; Auction House
        </span>
      </span>
    </Link>
  );
}

export function ThemeToggle() {
  const { theme, setTheme } = useTheme();

  const options: { value: "light" | "dark" | "system"; label: string; icon: string }[] = [
    { value: "light", label: "Light", icon: "☀" },
    { value: "dark", label: "Dark", icon: "☾" },
    { value: "system", label: "System", icon: "◐" },
  ];

  return (
    <div
      className="flex items-center gap-0.5 p-0.5"
      role="group"
      aria-label="Colour theme"
      style={{
        background: "var(--surface-sunken)",
        border: "1px solid var(--border-subtle)",
        borderRadius: 999,
      }}
    >
      {options.map((option) => {
        const active = theme === option.value;
        return (
          <button
            key={option.value}
            type="button"
            onClick={() => setTheme(option.value)}
            aria-pressed={active}
            title={option.label}
            className="flex h-7 w-7 items-center justify-center text-xs transition-colors"
            style={{
              borderRadius: 999,
              background: active ? "var(--philmart-navy)" : "transparent",
              color: active ? "var(--text-inverse)" : "var(--text-muted)",
            }}
          >
            <span aria-hidden>{option.icon}</span>
            <span className="sr-only">{option.label}</span>
          </button>
        );
      })}
    </div>
  );
}

export function PublicHeader() {
  const links = [
    { href: "/marketplace", label: "Marketplace" },
    { href: "/marketplace?sellingMethod=auction", label: "Auctions" },
    { href: "/open-your-shop", label: "Open Your Shop", sub: "for Shops and Clubs" },
    { href: "/about", label: "About PHILMART" },
  ];

  return (
    <header
      style={{
        background: "var(--surface-card)",
        borderBottom: "1px solid var(--border-default)",
      }}
    >
      <div className="mx-auto flex max-w-[1400px] flex-wrap items-center justify-between gap-4 px-4 py-3">
        <Logo />

        <nav className="flex flex-wrap items-center gap-6" aria-label="Main">
          {links.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="text-center text-sm font-medium transition-colors hover:opacity-70"
              style={{ color: "var(--text-primary)" }}
            >
              {link.label}
              {link.sub && (
                <span className="block text-[10px]" style={{ color: "var(--text-muted)" }}>
                  {link.sub}
                </span>
              )}
            </Link>
          ))}

          <ThemeToggle />

          <Link
            href="/login"
            className="text-sm font-medium"
            style={{ color: "var(--text-primary)" }}
          >
            Login
          </Link>
        </nav>
      </div>
    </header>
  );
}

export function PublicFooter({ screenId }: { screenId?: string }) {
  return (
    <footer
      className="mt-auto"
      style={{ background: "var(--surface-inverse)", color: "var(--text-inverse)" }}
    >
      <div className="mx-auto flex max-w-[1400px] flex-wrap items-center justify-between gap-4 px-4 py-4 text-xs">
        <span>© PHILMART</span>
        <nav className="flex gap-6" aria-label="Legal">
          <Link href="/terms" className="hover:underline">
            Terms &amp; Conditions
          </Link>
          <Link href="/support" className="hover:underline">
            Contact Us
          </Link>
        </nav>
        <div className="flex items-center gap-4">
          <span>All values in ZAR</span>
          {screenId && (
            <span
              className="px-2 py-1 font-mono text-[10px]"
              style={{ border: "1px solid rgb(255 255 255 / 0.3)", borderRadius: 3 }}
            >
              {screenId}
            </span>
          )}
        </div>
      </div>
    </footer>
  );
}
