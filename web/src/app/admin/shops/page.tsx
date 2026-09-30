import { Suspense } from "react";
import type { Metadata } from "next";
import { AdminShell } from "@/components/layout/AdminShell";
import { ShopRegister } from "./ShopRegister";

export const metadata: Metadata = {
  title: "Shops",
  robots: { index: false, follow: false },
};

export default function AdminShopsPage() {
  return (
    <AdminShell
      screenId="SCR-ADM-004"
      title="Shops"
      subtitle="Every Shop with its status, activation history and fee standing."
    >
      {/* the register reads its starting filter from the URL */}
      <Suspense>
        <ShopRegister />
      </Suspense>
    </AdminShell>
  );
}
