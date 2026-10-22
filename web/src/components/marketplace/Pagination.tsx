// page numbers under a result list: the marketplace and the storefront share it
export function Pagination({
  page,
  totalPages,
  onPage,
}: {
  page: number;
  totalPages: number;
  onPage: (page: number) => void;
}) {
  const window = 5;
  const start = Math.max(1, Math.min(page - 2, totalPages - window + 1));
  const pages = Array.from({ length: Math.min(window, totalPages) }, (_, i) => start + i);

  const button = (label: string, target: number, disabled = false, active = false) => (
    <button
      key={`${label}-${target}`}
      type="button"
      disabled={disabled}
      onClick={() => onPage(target)}
      className="min-w-9 px-3 py-1.5 text-sm font-medium disabled:opacity-40"
      style={{
        background: active ? "var(--philmart-navy)" : "var(--surface-card)",
        color: active ? "var(--text-inverse)" : "var(--text-secondary)",
        border: "1px solid var(--border-default)",
        borderRadius: 4,
      }}
    >
      {label}
    </button>
  );

  return (
    <nav className="mt-8 flex flex-wrap justify-center gap-1" aria-label="Pagination">
      {button("«", 1, page === 1)}
      {button("‹", page - 1, page === 1)}
      {pages.map((p) => button(String(p), p, false, p === page))}
      {totalPages > start + window - 1 && (
        <span className="px-2 py-1.5 text-sm" style={{ color: "var(--text-muted)" }}>
          …
        </span>
      )}
      {totalPages > start + window - 1 && button(String(totalPages), totalPages)}
      {button("›", page + 1, page === totalPages)}
      {button("»", totalPages, page === totalPages)}
    </nav>
  );
}
