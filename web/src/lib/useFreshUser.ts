"use client";

import { useEffect } from "react";
import { api, ApiError } from "@/lib/api";
import { clearSession, updateUser, useSession } from "@/lib/session";

// The signed-in user (permissions, pending terms) is saved at sign-in. Re-read
// it from the server when a page opens, so a permission change by the Shop
// Administrator (S.8) or a disabled account (S.9) applies without signing out.
export function useFreshUser() {
  const session = useSession();
  const signedIn = !!session;

  useEffect(() => {
    if (!signedIn) return;
    let cancelled = false;
    api.auth
      .me()
      .then((user) => !cancelled && updateUser(user))
      .catch((e) => {
        if (!cancelled && e instanceof ApiError && e.status === 401) clearSession();
      });
    return () => {
      cancelled = true;
    };
  }, [signedIn]);
}
