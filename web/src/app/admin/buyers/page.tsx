import type { Metadata } from "next";
import { AdminShell } from "@/components/layout/AdminShell";
import { RestrictionsPanel } from "@/components/restrictions/RestrictionsPanel";

export const metadata: Metadata = {
  title: "Buyer Restrictions",
  robots: { index: false, follow: false },
};

export default function AdminBuyersPage() {
  return (
    <AdminShell
      screenId="SCR-ADM-BUYERS"
      title="Buyer Restrictions"
      subtitle="Platform-wide restrictions, and every Shop's own restrictions for oversight."
    >
      <RestrictionsPanel platform />
    </AdminShell>
  );
}
