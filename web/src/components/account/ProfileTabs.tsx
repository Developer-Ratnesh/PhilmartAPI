"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

// the tab row on SCR-PUB-006.1 and 006.3
const TABS = [
  { href: "/account/profile", label: "Personal & Addresses" },
  { href: "/account/preferences", label: "Communication Preferences" },
];

export function ProfileTabs() {
  const path = usePathname();

  return (
    <nav className="my-6 flex flex-wrap gap-2" aria-label="Profile sections">
      {TABS.map((tab) => {
        const active = path === tab.href;
        return (
          <Link
            key={tab.href}
            href={tab.href}
            aria-current={active ? "page" : undefined}
            className="px-6 py-2.5 text-sm font-semibold"
            style={{
              background: active ? "var(--philmart-navy-deep)" : "var(--surface-card)",
              color: active ? "#ffffff" : "var(--text-primary)",
              border: "1px solid var(--border-default)",
              borderRadius: 4,
            }}
          >
            {tab.label}
          </Link>
        );
      })}
    </nav>
  );
}
