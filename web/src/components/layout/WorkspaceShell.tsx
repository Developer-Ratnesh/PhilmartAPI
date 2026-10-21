"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, type ReactNode } from "react";
import { Lockup } from "@/components/brand/Lockup";
import { hasPermission, useSession } from "@/lib/session";
import { signOut } from "@/lib/api";
import { useFreshUser } from "@/lib/useFreshUser";

// Shop workspace layout. Only shows sections that are built and that this
// user has permission for. The dashboard is for everyone.
const NAV: { href: string; label: string; permission: string | null }[] = [
  { href: "/workspace", label: "Dashboard", permission: null },
  { href: "/workspace/auctions", label: "Auctions", permission: "auction.manage" },
  { href: "/workspace/sales", label: "Sales & Invoices", permission: "invoice.view" },
  { href: "/workspace/buyers", label: "Buyer Restrictions", permission: "buyer.restrict" },
  { href: "/workspace/users", label: "Users & Permissions", permission: "shop.users.view" },
];

export function WorkspaceShell({ children, screenId }: { children: ReactNode; screenId: string }) {
  const session = useSession();
  const pathname = usePathname();
  const router = useRouter();
  const user = session?.user;
  useFreshUser();

  useEffect(() => {
    // the store reads localStorage on the client, so wait a tick before deciding
    const t = setTimeout(() => {
      if (!session || session.user.actorKind !== "Shop_User") router.replace("/workspace/login");
    }, 50);
    return () => clearTimeout(t);
  }, [session, router]);

  if (!user || user.actorKind !== "Shop_User") return null;

  // S.8: a section the user can't use says so instead of showing an API error
  const section = NAV.find((n) => n.href !== "/workspace" && pathname.startsWith(n.href));
  const allowedHere = !section?.permission || hasPermission(user, section.permission);

  return (
    <div className="flex min-h-screen flex-col" style={{ background: "var(--surface-page)" }}>
      <header className="flex flex-wrap items-center justify-between gap-4 px-4 py-3 md:px-6" style={{ background: "var(--surface-card)", borderBottom: "1px solid var(--border-default)" }}>
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
            onClick={async () => {
              await signOut();
              router.push("/workspace/login");
            }}
          >
            Sign out
          </button>
        </div>
      </header>

      <div className="flex flex-1 flex-col md:flex-row">
        <nav aria-label="Shop" className="w-full shrink-0 py-2 md:w-56 md:py-4" style={{ background: "var(--surface-card)", borderRight: "1px solid var(--border-subtle)" }}>
          <ul>
            {NAV.filter((n) => n.permission === null || hasPermission(user, n.permission)).map((n) => {
              const active = n.href === "/workspace" ? pathname === n.href : pathname.startsWith(n.href);
              return (
                <li key={n.href}>
                  <Link
                    href={n.href}
                    className="block px-5 py-2.5 text-sm font-medium"
                    style={{
                      color: active ? "var(--philmart-navy-ink)" : "var(--text-primary)",
                      background: active ? "var(--surface-sunken)" : "transparent",
                      borderLeft: `3px solid ${active ? "var(--philmart-navy-ink)" : "transparent"}`,
                    }}
                  >
                    {n.label}
                  </Link>
                </li>
              );
            })}
          </ul>
        </nav>

        <main className="min-w-0 flex-1 px-4 py-6 md:px-8">
          {allowedHere ? children : (
            <div className="p-6" style={{ background: "var(--surface-card)", border: "1px solid var(--border-subtle)", borderRadius: "var(--radius-card)" }}>
              <h1 className="font-display text-2xl font-bold" style={{ color: "var(--text-primary)" }}>No access</h1>
              <p className="mt-2 text-sm" style={{ color: "var(--text-secondary)" }}>
                Your account doesn&apos;t have permission for this section. Ask your Shop Administrator if you need it.
              </p>
              <Link href="/workspace" className="mt-4 inline-block text-sm font-semibold hover:underline" style={{ color: "var(--accent-info)" }}>
                Back to the Dashboard
              </Link>
            </div>
          )}
        </main>
      </div>

      <footer className="flex items-center justify-between px-6 py-3 text-xs" style={{ background: "var(--surface-inverse)", color: "var(--text-on-inverse)" }}>
        <span>© PHILMART</span>
        <span className="px-2 py-1 font-mono text-[10px]" style={{ border: "1px solid rgb(255 255 255 / 0.3)", borderRadius: 3 }}>{screenId}</span>
      </footer>
    </div>
  );
}
