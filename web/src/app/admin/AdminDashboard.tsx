"use client";

import { useEffect, useState } from "react";
import { Card, StatTile } from "@/components/ui/Card";
import { api, formatMoney, type AdminDashboard as Dashboard } from "@/lib/api";
import { adminErrorMessage } from "@/lib/admin";

// BR-21-R01 overview. The history view comes later with reports.
export function AdminDashboard() {
  const [data, setData] = useState<Dashboard | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let cancelled = false;

    api.admin
      .dashboard()
      .then((res) => {
        if (cancelled) return;
        setData(res);
        setError(null);
      })
      .catch((e: unknown) => {
        if (cancelled) return;
        setError(adminErrorMessage(e, "Could not load the dashboard."));
      });

    return () => {
      cancelled = true;
    };
  }, [attempt]);

  if (error) {
    return (
      <Card>
        <p className="text-sm" style={{ color: "var(--accent-danger)" }}>
          {error}
        </p>
        <button
          type="button"
          onClick={() => setAttempt((n) => n + 1)}
          className="mt-3 text-sm font-semibold hover:underline"
          style={{ color: "var(--accent-info)" }}
        >
          Try again
        </button>
      </Card>
    );
  }

  if (!data) {
    return (
      <p className="text-sm" style={{ color: "var(--text-muted)" }}>
        Loading…
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-8">
      <Section title="Shops">
        <StatTile
          label="Applications awaiting review"
          value={data.applicationsAwaitingReview}
          tone="attention"
          href="/admin/shops?status=application_submitted"
        />
        <StatTile
          label="In setup"
          value={data.shopsInSetup}
          tone="info"
          href="/admin/shops?status=setup_access_granted"
        />
        <StatTile
          label="Active"
          value={data.activeShops}
          tone="live"
          href="/admin/shops?status=active"
        />
        <StatTile
          label="Deactivated"
          value={data.deactivatedShops}
          tone="danger"
          href="/admin/shops?status=deactivated"
        />
      </Section>

      <Section title="Marketplace">
        <StatTile label="Live Buy Now listings" value={data.liveFixedPriceListings} tone="info" />
        <StatTile label="Live auctions" value={data.liveAuctions} tone="auction" />
        <StatTile
          label="Live auctions with bids"
          value={data.liveAuctionsWithBids}
          tone="auction"
          caption="Run to their scheduled end even if the Shop is deactivated."
        />
        <StatTile label="Items ready to list" value={data.itemsReadyToList} tone="info" />
        <StatTile
          label="Past 75-day escalation"
          value={data.itemsPastReadyToListEscalation}
          tone="attention"
          caption="Ready to List items waiting 75 days or more."
        />
      </Section>

      <Section title="PHILMART fees">
        <StatTile label="Outstanding" value={formatMoney(data.feesOutstandingMinor)} tone="info" />
        <StatTile label="Overdue" value={formatMoney(data.feesOverdueMinor)} tone="danger" />
        <StatTile
          label="Shops with overdue fees"
          value={data.shopsWithOverdueFees}
          tone="attention"
          caption="Arrears never deactivate a Shop automatically."
          href="/admin/shops?overdueOnly=true"
        />
      </Section>

      <p className="text-xs" style={{ color: "var(--text-muted)" }}>
        Figures as at{" "}
        {new Date(data.asAt).toLocaleString("en-ZA", {
          dateStyle: "medium",
          timeStyle: "short",
        })}
        .
      </p>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section>
      <h2 className="mb-3 font-display text-lg font-semibold" style={{ color: "var(--text-primary)" }}>
        {title}
      </h2>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">{children}</div>
    </section>
  );
}
