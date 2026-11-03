import { SYNTHETIC_EMAIL_DOMAIN } from "../core/types";

/**
 * Normalizes a phone number to international digits (default country Pakistan, +92).
 * "0300-1234567", "+92 300 1234567" and "3001234567" all become "923001234567".
 */
export function normalizePhone(raw: string): string | null {
  let digits = raw.replace(/\D/g, "");
  if (digits.startsWith("00")) digits = digits.slice(2);
  if (digits.length === 11 && digits.startsWith("0")) digits = `92${digits.slice(1)}`;
  else if (digits.length === 10 && digits.startsWith("3")) digits = `92${digits}`;
  if (digits.length < 10 || digits.length > 15) return null;
  return digits;
}

export function syntheticEmailFor(normalizedPhone: string): string {
  return `p${normalizedPhone}@${SYNTHETIC_EMAIL_DOMAIN}`;
}

export function isSyntheticEmail(email: string): boolean {
  return email.toLowerCase().endsWith(`@${SYNTHETIC_EMAIL_DOMAIN}`);
}
