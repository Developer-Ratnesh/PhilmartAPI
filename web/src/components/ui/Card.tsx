import type { ReactNode } from "react";

export function Card({
  title,
  action,
  children,
  warm = false,
  className = "",
}: {
  title?: string;
  action?: ReactNode;
  children: ReactNode;
  warm?: boolean;
  className?: string;
}) {
  return (
    <section
      className={`overflow-hidden ${className}`}
      style={{
        background: warm ? "var(--surface-card-warm)" : "var(--surface-card)",
        border: "1px solid var(--border-subtle)",
        borderRadius: "var(--radius-card)",
        boxShadow: "var(--shadow-card)",
      }}
    >
      {title && (
        <header
          className="flex items-center justify-between px-5 py-4"
          style={{ borderBottom: "1px solid var(--border-subtle)" }}
        >
          <h2
            className="font-display text-lg font-semibold"
            style={{ color: "var(--text-primary)" }}
          >
            {title}
          </h2>
          {action}
        </header>
      )}
      <div className={title ? "p-5" : "p-5"}>{children}</div>
    </section>
  );
}

// the number carries the colour, each one means a different queue
export function StatTile({
  label,
  value,
  caption,
  tone = "info",
  href,
}: {
  label: string;
  value: number | string;
  caption?: string;
  tone?: "info" | "attention" | "auction" | "live" | "danger";
  href?: string;
}) {
  const colour = {
    info: "var(--accent-info)",
    attention: "var(--accent-attention)",
    auction: "var(--accent-auction)",
    live: "var(--accent-live)",
    danger: "var(--accent-danger)",
  }[tone];

  const body = (
    <>
      <div className="flex items-start justify-between gap-3">
        <p className="text-xs font-semibold" style={{ color: "var(--text-secondary)" }}>
          {label}
        </p>
        {href && (
          <span aria-hidden className="text-sm" style={{ color: "var(--text-muted)" }}>
            ›
          </span>
        )}
      </div>
      <p className="mt-2 font-display text-3xl font-bold" style={{ color: colour }}>
        {value}
      </p>
      {caption && (
        <p className="mt-1 text-xs leading-snug" style={{ color: "var(--text-muted)" }}>
          {caption}
        </p>
      )}
    </>
  );

  const style: React.CSSProperties = {
    background: "var(--surface-card)",
    border: "1px solid var(--border-subtle)",
    borderRadius: "var(--radius-card)",
  };

  return href ? (
    <a href={href} className="block p-4 transition-shadow hover:shadow-md" style={style}>
      {body}
    </a>
  ) : (
    <div className="p-4" style={style}>
      {body}
    </div>
  );
}

export function StatRow({
  label,
  value,
  icon,
}: {
  label: string;
  value: ReactNode;
  icon?: ReactNode;
}) {
  return (
    <div
      className="flex items-center justify-between gap-4 py-3"
      style={{ borderBottom: "1px solid var(--border-subtle)" }}
    >
      <div className="flex items-center gap-3">
        {icon && (
          <span
            className="flex h-9 w-9 items-center justify-center rounded-full"
            style={{ background: "var(--surface-sunken)" }}
          >
            {icon}
          </span>
        )}
        <span className="text-sm" style={{ color: "var(--text-secondary)" }}>
          {label}
        </span>
      </div>
      <span
        className="font-display text-lg font-bold tabular-nums"
        style={{ color: "var(--text-primary)" }}
      >
        {value}
      </span>
    </div>
  );
}
