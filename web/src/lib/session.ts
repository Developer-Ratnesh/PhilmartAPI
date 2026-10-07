"use client";

import { useSyncExternalStore } from "react";

// The token sits in localStorage for now. Moving to an httpOnly cookie needs
// the API and the site on one domain, which is a staging decision.
export type SignedInUser = {
  actorID: string;
  actorKind: "Buy_Buyer" | "Shop_User" | "platform_admin";
  shopID: string | null;
  shopName: string | null;
  email: string;
  fullName: string | null;
  permissions: string[];
  registrationStep: number | null;
  emailVerified: boolean;
  pendingAcceptances: string[];
};

type Session = { token: string; user: SignedInUser };

const KEY = "philmart.session";
const listeners = new Set<() => void>();
let cached: Session | null | undefined;

function read(): Session | null {
  if (cached !== undefined) return cached;
  try {
    const raw = window.localStorage.getItem(KEY);
    cached = raw ? (JSON.parse(raw) as Session) : null;
  } catch {
    cached = null;
  }
  return cached;
}

export function saveSession(token: string, user: SignedInUser) {
  cached = { token, user };
  window.localStorage.setItem(KEY, JSON.stringify(cached));
  listeners.forEach((l) => l());
}

export function updateUser(user: SignedInUser) {
  const current = read();
  if (current) saveSession(current.token, user);
}

export function clearSession() {
  cached = null;
  window.localStorage.removeItem(KEY);
  listeners.forEach((l) => l());
}

export function currentToken(): string | null {
  if (typeof window === "undefined") return null;
  return read()?.token ?? null;
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

// null on the server and before sign-in
export function useSession(): Session | null {
  return useSyncExternalStore(subscribe, read, () => null);
}

export function hasPermission(user: SignedInUser | undefined, code: string) {
  return !!user && user.permissions.includes(code);
}
