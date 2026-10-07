"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, type ReactNode } from "react";
import { Lockup } from "@/components/brand/Lockup";
import { clearSession, hasPermission, useSession } from "@/lib/session";

// Shop workspace layout. Only shows sections that are built and that this
// user has permission for.
const NAV = [
  { href: "/workspace/auctions", label: "Auctions", permission: "auction.manage" },
  { href: "/workspace/users", label: "Users & Permissions", permission: "shop.users.view" },
];

export function WorkspaceShell({ children, screenId }: { children: ReactNode; screenId: string }) {
  const session = useSession();
  const pathname = usePathname();
  const router = useRouter();
  const user = session?.user;

  useEffect(() => {
    // the store reads localStorage on the client, so wait a tick before deciding
    const t = setTimeout(() => {
      if (!session || session.user.actorKind !== "Shop_User") router.replace("/workspace/login");
    }, 50);
    return () => clearTimeout(t);
  }, [session, router]);

  if (!user || user.actorKind !== "Shop_User") return null;

  return (
    <div className="flex min-h-screen flex-col" style={{ background: "var(--surface-page)" }}>
      <header className="flex items-center justify-between gap-4 px-6 py-3" style={{ background: "var(--surface-card)", borderBottom: "1px solid var(--border-default)" }}>
        <div className="flex items-center gap-6">
          <Lockup size="sm" />
          <div className="pl-6" style={{ borderLeft: "1px solid var(--border-subtle)" }}>
            <p className="font-display text-lg font-semibold" style={{ color: "var(--text-primary)" }}>{user.shopName}</p>
            <p className="text-xs" style={{ color: "var(--text-muted)" }}>Shop Workspace</p>
          </div>
        </div>
        <div className="flex items-center gap-4 text-sm">
          <div className="text-right">
            <p className="font-semibold" style={{ color: "var(--text-primary)" }}>{user.fullName}</p>
            <p className="text-xs" style={{ color: "var(--text-muted)" }}>
              {user.permissions.includes("shop.users.manage") ? "Shop Administrator" : "Shop user"}
            </p>
          </div>
          <button
            type="button"
            className="text-xs hover:underline"
            style={{ color: "var(--text-muted)" }}
            onClick={() => {
              clearSession();
              router.push("/workspace/login");
            }}
          >
            Sign out
          </button>
        </div>
      </header>

      <div className="flex flex-1">
        <nav aria-label="Shop" className="w-56 shrink-0 py-4" style={{ background: "var(--surface-card)", borderRight: "1px solid var(--border-subtle)" }}>
          <ul>
            {NAV.filter((n) => hasPermission(user, n.permission)).map((n) => {
              const active = pathname.startsWith(n.href);
              return (
                <li key={n.href}>
                  <Link
                    href={n.href}
                    className="block px-5 py-2.5 text-sm font-medium"
                    style={{
                      color: active ? "var(--philmart-navy-deep)" : "var(--text-primary)",
                      background: active ? "var(--surface-sunken)" : "transparent",
                      borderLeft: `3px solid ${active ? "var(--philmart-navy-deep)" : "transparent"}`,
                    }}
                  >
                    {n.label}
                  </Link>
                </li>
              );
            })}
          </ul>
        </nav>

        <main className="flex-1 px-8 py-6">{children}</main>
      </div>

      <footer className="flex items-center justify-between px-6 py-3 text-xs" style={{ background: "var(--surface-inverse)", color: "var(--text-inverse)" }}>
        <span>© PHILMART</span>
        <span className="px-2 py-1 font-mono text-[10px]" style={{ border: "1px solid rgb(255 255 255 / 0.3)", borderRadius: 3 }}>{screenId}</span>
      </footer>
    </div>
  );
}
