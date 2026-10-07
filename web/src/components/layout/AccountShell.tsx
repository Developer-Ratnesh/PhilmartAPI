"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { PublicFooter, PublicHeader } from "@/components/layout/PublicHeader";

// Buyer "My Account" layout from SCR-PUB-008/009/015. Only built sections are listed.
const SECTIONS = [
  { href: "/account/saved", label: "Saved Items" },
  { href: "/account/recent", label: "Recently Viewed Items" },
  { href: "/support", label: "PHILMART Support" },
];

export function AccountShell({ screenId, children }: { screenId: string; children: ReactNode }) {
  const path = usePathname();

  return (
    <div className="flex min-h-screen flex-col" style={{ background: "var(--surface-marketplace)" }}>
      <PublicHeader />

      <div className="mx-auto flex w-full max-w-[1400px] flex-1 flex-col gap-6 px-4 py-8 md:flex-row">
        <nav className="flex shrink-0 flex-col gap-1.5 md:w-60" aria-label="My account">
          {SECTIONS.map((s) => {
            const active = path === s.href;
            return (
              <Link
                key={s.href}
                href={s.href}
                aria-current={active ? "page" : undefined}
                className="px-4 py-3 text-sm font-semibold transition-opacity hover:opacity-90"
                style={{
                  background: active ? "var(--accent-info)" :"var(--philmart-navy-deep)",
                  color: "#ffffff",
                  borderRadius: 4,
                }}
              >
                {s.label}
              </Link>
            );
          })}
        </nav>

        <main className="min-w-0 flex-1">{children}</main>
      </div>

      <PublicFooter screenId={screenId} />
    </div>
  );
}
