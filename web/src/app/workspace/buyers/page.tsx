"use client";

import { WorkspaceShell } from "@/components/layout/WorkspaceShell";
import { RestrictionsPanel } from "@/components/restrictions/RestrictionsPanel";

// D044. Needs buyer.restrict; the shell shows "No access" otherwise.
export default function WorkspaceBuyersPage() {
  return (
    <WorkspaceShell screenId="SCR-SHP-BUYERS">
      <h1 className="mb-6 font-display text-3xl font-bold" style={{ color: "var(--text-primary)" }}>
        Buyer Restrictions
      </h1>
      <RestrictionsPanel platform={false} />
    </WorkspaceShell>
  );
}
