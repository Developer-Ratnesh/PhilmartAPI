"use client";

import { Field, inputStyle } from "@/components/ui/Form";

export type PhysicalAddress = {
  addressLine1: string;
  addressLine2: string;
  city: string;
  province: string;
  postalCode: string;
  countryCode: string;
};

// the server checks the same list (PhysicalAddress.cs)
const PROVINCES = [
  "Eastern Cape",
  "Free State",
  "Gauteng",
  "KwaZulu-Natal",
  "Limpopo",
  "Mpumalanga",
  "North West",
  "Northern Cape",
  "Western Cape",
];

const COUNTRIES = [
  { code: "ZA", name: "South Africa" },
  { code: "BW", name: "Botswana" },
  { code: "LS", name: "Lesotho" },
  { code: "NA", name: "Namibia" },
  { code: "SZ", name: "Eswatini" },
  { code: "ZW", name: "Zimbabwe" },
  { code: "MZ", name: "Mozambique" },
  { code: "GB", name: "United Kingdom" },
];

// SCR-PUB-014.4: everything but Line 2 is required. Registration step 3 and the
// profile both use these fields.
export function PhysicalAddressFields({ value, onChange }: { value: PhysicalAddress; onChange: (next: PhysicalAddress) => void }) {
  const set = (key: keyof PhysicalAddress) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => {
    const next = { ...value, [key]: e.target.value };
    // a province from one country means nothing in another
    if (key === "countryCode") next.province = "";
    onChange(next);
  };
  const southAfrica = value.countryCode === "ZA";

  return (
    <>
      <Field label="Address Line 1 *" htmlFor="line1">
        <input id="line1" required placeholder="e.g. 123 Main Road" value={value.addressLine1} onChange={set("addressLine1")} style={inputStyle} />
      </Field>
      <Field label="Address Line 2 (optional)" htmlFor="line2">
        <input id="line2" placeholder="e.g. Unit 4, Sandown Close" value={value.addressLine2} onChange={set("addressLine2")} style={inputStyle} />
      </Field>
      <div className="grid grid-cols-2 gap-4">
        <Field label="Suburb / City *" htmlFor="city">
          <input id="city" required placeholder="e.g. Claremont" value={value.city} onChange={set("city")} style={inputStyle} />
        </Field>
        <Field label="Province / Region *" htmlFor="province">
          {southAfrica ? (
            <select id="province" required value={value.province} onChange={set("province")} style={inputStyle}>
              <option value="">Select province</option>
              {PROVINCES.map((p) => (
                <option key={p} value={p}>{p}</option>
              ))}
            </select>
          ) : (
            <input id="province" required value={value.province} onChange={set("province")} style={inputStyle} />
          )}
        </Field>
      </div>
      <div className="grid grid-cols-2 gap-4">
        <Field label="Postal Code *" htmlFor="postal">
          <input
            id="postal"
            required
            placeholder="e.g. 7708"
            inputMode={southAfrica ? "numeric" : undefined}
            pattern={southAfrica ? "[0-9]{4}" : undefined}
            title={southAfrica ? "A South African postal code has 4 digits" : undefined}
            value={value.postalCode}
            onChange={set("postalCode")}
            style={inputStyle}
          />
        </Field>
        <Field label="Country *" htmlFor="country">
          <select id="country" required value={value.countryCode} onChange={set("countryCode")} style={inputStyle}>
            {COUNTRIES.map((c) => (
              <option key={c.code} value={c.code}>{c.name}</option>
            ))}
          </select>
        </Field>
      </div>
    </>
  );
}
