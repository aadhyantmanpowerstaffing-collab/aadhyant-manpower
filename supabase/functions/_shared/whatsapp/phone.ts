export type IndianWhatsAppPhone = {
  indianMobileKey: string;
  providerAddress: string;
};

export function normalizeIndianWhatsAppPhone(value: unknown): IndianWhatsAppPhone {
  let digits = String(value ?? "").replace(/[^0-9]/g, "");
  if (digits.length === 12 && digits.startsWith("91")) digits = digits.slice(2);
  if (!/^[6-9][0-9]{9}$/.test(digits)) {
    throw new Error("A valid Indian mobile number is required");
  }
  return { indianMobileKey: digits, providerAddress: `+91${digits}` };
}
