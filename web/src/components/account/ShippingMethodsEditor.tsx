"use client";

import { inputStyle } from "@/components/ui/Form";
import type { DeliveryOption, ShippingPreference } from "@/lib/api";

export type ShippingPrefs = Record<string, ShippingPreference>;

// R.6/B.4: keep exactly one preferred method among the available ones. When the
// preferred one is switched off (or none was chosen yet) the first available
// method takes over, so the item page always has a sensible default.
export function withPreferred(prefs: ShippingPrefs, methods: DeliveryOption[]): ShippingPrefs {
  const order = methods.map((m) => m.id).filter((id) => prefs[id]);
  const current = order.find((id) => prefs[id].available && prefs[id].preferred);
  const chosen = current ?? order.find((id) => prefs[id].available) ?? null;
  const next: ShippingPrefs = {};
  for (const id of Object.keys(prefs)) next[id] = { ...prefs[id], preferred: id === chosen };
  return next;
}

// Shipping preferences for registration Step 3 and the buyer profile (D009/D037).
export function ShippingMethodsEditor({
  methods,
  prefs,
  onChange,
}: {
  methods: DeliveryOption[];
  prefs: ShippingPrefs;
  onChange: (prefs: ShippingPrefs) => void;
}) {
  const update = (id: string, change: Partial<ShippingPreference>) =>
    onChange(withPreferred({ ...prefs, [id]: { ...prefs[id], ...change } }, methods));

  const choosePreferred = (id: string) => {
    const next: ShippingPrefs = {};
    for (const key of Object.keys(prefs)) next[key] = { ...prefs[key], preferred: key === id };
    onChange(next);
  };

  return (
    <>
      {methods.map((m) => {
        const pref = prefs[m.id];
        if (!pref) return null;
        return (
          <div key={m.id} className="mb-3 p-3" style={{ border: "1px solid var(--border-subtle)", borderRadius: 4 }}>
            <div className="flex flex-wrap items-center justify-between gap-2">
              <label className="flex items-center gap-2 text-sm font-semibold" style={{ color: "var(--text-primary)" }}>
                <input type="checkbox" checked={pref.available} onChange={(e) => update(m.id, { available: e.target.checked })} />
                {m.name}
              </label>
              {pref.available && (
                <label className="flex items-center gap-2 text-xs" style={{ color: "var(--text-secondary)" }}>
                  <input type="radio" name="preferred-method" checked={!!pref.preferred} onChange={() => choosePreferred(m.id)} />
                  My preferred method
                </label>
              )}
            </div>
            {pref.available && m.requiresPickupPoint && (
              <select
                aria-label={`Default pickup point for ${m.name}`}
                className="mt-2"
                value={pref.pickupPointID ?? ""}
                onChange={(e) => update(m.id, { pickupPointID: e.target.value })}
                style={inputStyle}
              >
                {m.pickupPoints.map((pp) => (
                  <option key={pp.id} value={pp.id}>
                    {pp.name} {pp.address ? `— ${pp.address}` : ""}
                  </option>
                ))}
              </select>
            )}
            {pref.available && m.requiresAddress && (
              <p className="mt-1 text-xs" style={{ color: "var(--text-muted)" }}>
                Delivered to the address above.
              </p>
            )}
          </div>
        );
      })}
    </>
  );
}
