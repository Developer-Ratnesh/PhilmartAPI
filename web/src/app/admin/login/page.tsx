import type { Metadata } from "next";
import { AdminChrome } from "@/components/layout/AdminChrome";
import { AdminLoginForm } from "./AdminLoginForm";

export const metadata: Metadata = {
  title: "Administration Sign In",
  robots: { index: false, follow: false },
};

export default function AdminLoginPage() {
  return (
    <AdminChrome screenId="SCR-ADM-LOGIN">
      <div className="mx-auto w-full max-w-[460px] px-4 py-16">
        <h1 className="font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>
          PHILMART Administration
        </h1>
        <p className="mt-1 text-sm" style={{ color: "var(--text-secondary)" }}>
          Sign in to the marketplace administration console.
        </p>

        <AdminLoginForm />

        <p className="mt-6 text-center text-xs" style={{ color: "var(--text-muted)" }}>
          Administration access is separate from Shop and Buyer accounts.
        </p>
      </div>
    </AdminChrome>
  );
}
