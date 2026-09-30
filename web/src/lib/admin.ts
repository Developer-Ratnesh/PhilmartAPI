import { ApiError, type ShopStatus } from "@/lib/api";

export const SHOP_STATUS_LABEL: Record<ShopStatus, string> = {
  application_submitted: "Application submitted",
  application_rejected: "Application rejected",
  setup_access_granted: "In setup",
  active: "Active",
  deactivated: "Deactivated",
};

export const SHOP_STATUS_TONE: Record<
  ShopStatus,
  "live" | "scheduled" | "info" | "danger" | "neutral"
> = {
  application_submitted: "info",
  application_rejected: "neutral",
  setup_access_granted: "scheduled",
  active: "live",
  deactivated: "danger",
};

export function adminErrorMessage(e: unknown, fallback: string): string {
  if (e instanceof ApiError) {
    if (e.status === 401) return "You are not signed in. Sign in to the administration console.";
    if (e.status === 403) return "Only a PHILMART administrator can view this.";
    return e.message;
  }
  return fallback;
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return "—";
  return new Date(value).toLocaleDateString("en-ZA", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}
