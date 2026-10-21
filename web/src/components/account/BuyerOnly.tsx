"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, type ReactNode } from "react";
import { Notice } from "@/components/ui/Form";
import type { PagedResult } from "@/lib/api";
import { useSession } from "@/lib/session";

export function BuyerOnly({ children }: { children: ReactNode }) {
  const session = useSession();
  const router = useRouter();
  const path = usePathname();

  // signed out: off to sign in, then back here (checklist L.9)
  useEffect(() => {
    // the session store reads localStorage on the client, so wait a tick before deciding
    const t = setTimeout(() => {
      if (!session) router.replace("/login?next=" + encodeURIComponent(path));
    }, 50);
    return () => clearTimeout(t);
  }, [session, router, path]);

  if (!session) {
    return (
      <Notice>
        <Link href={"/login?next=" + encodeURIComponent(path)} className="font-semibold hover:underline">Sign in</Link> to see this page.
      </Notice>
    );
  }

  if (session.user.actorKind !== "Buy_Buyer") {
    return <Notice>This page is for buyer accounts.</Notice>;
  }

  return <>{children}</>;
}

export function Pager<T>({ data, onPage }: { data: PagedResult<T>; onPage: (page: number) => void }) {
  if (data.totalPages <= 1) return null;

  return (
    <div className="mt-4 flex items-center justify-between text-xs" style={{ color: "var(--text-secondary)" }}>
      <span>Page {data.page} of {data.totalPages}</span>
      <span className="flex gap-2">
        <PageButton disabled={!data.hasPrevious} onClick={() => onPage(data.page - 1)}>Previous</PageButton>
        <PageButton disabled={!data.hasNext} onClick={() => onPage(data.page + 1)}>Next</PageButton>
      </span>
    </div>
  );
}

function PageButton({ disabled, onClick, children }: { disabled: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className="px-4 py-2 font-semibold disabled:opacity-40"
      style={{ border: "1px solid var(--border-default)", borderRadius: 4, background: "var(--surface-card)", color: "var(--text-primary)" }}
    >
      {children}
    </button>
  );
}
