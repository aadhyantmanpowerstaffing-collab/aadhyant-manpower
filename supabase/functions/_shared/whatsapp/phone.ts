export type IndianWhatsAppPhone = {
  indianMobileKey: string;
  providerAddress: string;
};

export function normalizeIndianWhatsAppPhone(value: unknown): IndianWhatsAppPhone {
  const input = String(value ?? "").trim();
  if (!input || !/^[0-9+()\s-]+$/.test(input)) {
    throw new Error("A valid Indian mobile number is required");
  }
  const compact = input.replace(/[()\s-]/g, "");
  if (!/^(?:[6-9][0-9]{9}|91[6-9][0-9]{9}|\+91[6-9][0-9]{9})$/.test(compact)) {
    throw new Error("A valid Indian mobile number is required");
  }
  let digits = compact.startsWith("+91") ? compact.slice(3) : compact;
  if (digits.length === 12) digits = digits.slice(2);
  if (!/^[6-9][0-9]{9}$/.test(digits)) {
    throw new Error("A valid Indian mobile number is required");
  }
  return { indianMobileKey: digits, providerAddress: `+91${digits}` };
}
