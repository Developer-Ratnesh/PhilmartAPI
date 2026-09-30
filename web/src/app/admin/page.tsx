import type { Metadata } from "next";
import { AdminShell } from "@/components/layout/AdminShell";
import { AdminDashboard } from "./AdminDashboard";

export const metadata: Metadata = {
  title: "Administration Dashboard",
  robots: { index: false, follow: false },
};

export default function AdminDashboardPage() {
  return (
    <AdminShell
      screenId="SCR-ADM-001"
      title="Administration Dashboard"
      subtitle="Current overview of the PHILMART marketplace."
    >
      <AdminDashboard />
    </AdminShell>
  );
}
