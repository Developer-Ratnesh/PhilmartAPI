"use client";

import { useEffect, type ReactNode } from "react";
import { usePathname, useRouter } from "next/navigation";
import { AdminChrome } from "@/components/layout/AdminChrome";
import { useSession } from "@/lib/session";
import { signOut } from "@/lib/api";

// Admin layout with the section menu. Only built sections are listed, add the
// rest here as they're done.
const NAV = [
  { href: "/admin", label: "Dashboard" },
  { href: "/admin/shops", label: "Shops" },
  { href: "/admin/buyers", label: "Buyer Restrictions" },
];

export function AdminShell({
  children,
  screenId,
  title,
  subtitle,
}: {
  children: ReactNode;
  screenId: string;
  title: string;
  subtitle?: string;
}) {
  const pathname = usePathname();
  const router = useRouter();
  const session = useSession();
  const isAdmin = session?.user.actorKind === "platform_admin";

  // D.4: a buyer, a Shop user or nobody goes to the admin sign-in. The API
  // refuses them anyway; this just doesn't show them an empty panel.
  useEffect(() => {
    // the session store reads localStorage on the client, so wait a tick before deciding
    const t = setTimeout(() => {
      if (!isAdmin) router.replace("/admin/login");
    }, 50);
    return () => clearTimeout(t);
  }, [isAdmin, router]);

  if (!isAdmin || !session) return <AdminChrome screenId={screenId}>{null}</AdminChrome>;

  return (
    <AdminChrome
      screenId={screenId}
      user={{ name: session.user.fullName ?? session.user.email }}
      onLogout={async () => {
        await signOut();
        router.replace("/admin/login");
      }}
    >
      <div className="mx-auto flex max-w-[1600px] flex-col gap-6 px-4 py-6 md:flex-row">
        <nav aria-label="Administration" className="md:w-52 md:shrink-0">
          <ul className="flex gap-1 overflow-x-auto md:flex-col">
            {NAV.map((link) => {
              const active =
                link.href === "/admin" ? pathname === "/admin" : pathname.startsWith(link.href);

              return (
                <li key={link.href}>
                  <a
                    href={link.href}
                    aria-current={active ? "page" : undefined}
                    className="block whitespace-nowrap px-3 py-2 text-sm font-semibold"
                    style={{
                      borderRadius: 4,
                      background: active ? "var(--surface-sunken)" : "transparent",
                      color: active ? "var(--text-primary)" : "var(--text-secondary)",
                      borderLeft: active
                        ? "3px solid var(--philmart-gold)"
                        : "3px solid transparent",
                    }}
                  >
                    {link.label}
                  </a>
                </li>
              );
            })}
          </ul>
        </nav>

        <div className="min-w-0 flex-1">
          <h1
            className="font-display text-2xl font-bold md:text-3xl"
            style={{ color: "var(--text-primary)" }}
          >
            {title}
          </h1>
          {subtitle && (
            <p className="mt-1 text-sm" style={{ color: "var(--text-secondary)" }}>
              {subtitle}
            </p>
          )}
          <div className="mt-6">{children}</div>
        </div>
      </div>
    </AdminChrome>
  );
}
