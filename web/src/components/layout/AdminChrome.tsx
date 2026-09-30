import type { ReactNode } from "react";
import { Lockup } from "@/components/brand/Lockup";

// Admin chrome from SCR-ADM-001. Deeper navy than the public shell, no
// marketplace nav and no trust strip. BRAND-SHELL-001 treats the header, logo
// and footer as shared components, so every ADM screen uses these two.

export function AdminTopBar({ user }: { user?: { name: string } }) {
  return (
    <header style={{ background: "var(--philmart-navy-deep)" }}>
      <div className="mx-auto flex max-w-[1600px] items-center justify-between gap-4 px-4 py-3">
        {/* white card behind the lockup, the asset has a light background */}
        <span
          className="inline-flex items-center px-4 py-2"
          style={{ background: "#ffffff", borderRadius: 3 }}
        >
          <Lockup size="sm" href={user ? "/admin" : null} priority />
        </span>

        {user && (
          <div className="flex items-center gap-4 text-sm" style={{ color: "#ffffff" }}>
            <span>{user.name}</span>
            <span aria-hidden style={{ color: "rgb(255 255 255 / 0.4)" }}>
              |
            </span>
            <a href="/admin/logout" className="hover:underline">
              Log out
            </a>
          </div>
        )}
      </div>
    </header>
  );
}

export function AdminFooter({ screenId }: { screenId?: string }) {
  return (
    <footer className="mt-auto" style={{ background: "var(--philmart-navy-deep)" }}>
      <div
        className="mx-auto flex max-w-[1600px] items-center justify-between gap-4 px-4 py-4 text-xs"
        style={{ color: "rgb(255 255 255 / 0.75)" }}
      >
        <span>PHILMART</span>
        {screenId && (
          <span
            className="px-2 py-1 font-mono text-[10px]"
            style={{ border: "1px solid rgb(255 255 255 / 0.3)", borderRadius: 3 }}
          >
            {screenId}
          </span>
        )}
      </div>
    </footer>
  );
}

export function AdminChrome({
  children,
  screenId,
  user,
}: {
  children: ReactNode;
  screenId?: string;
  user?: { name: string };
}) {
  return (
    <div className="flex min-h-screen flex-col" style={{ background: "var(--surface-page)" }}>
      <AdminTopBar user={user} />
      <main className="flex-1">{children}</main>
      <AdminFooter screenId={screenId} />
    </div>
  );
}
