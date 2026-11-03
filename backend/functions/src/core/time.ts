/** Organization time: Asia/Karachi (UTC+5, no daylight saving). */
export const ORG_TIME_ZONE = "Asia/Karachi";
export const ORG_UTC_OFFSET_MINUTES = 5 * 60;

/** Working-day key (YYYY-MM-DD) in organization time for an epoch-millisecond instant. */
export function dateKeyOf(ms: number): string {
  return new Date(ms + ORG_UTC_OFFSET_MINUTES * 60_000).toISOString().slice(0, 10);
}

export function isValidDateKey(s: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}

/** Adds whole days to a date key. */
export function addDays(key: string, days: number): string {
  const d = new Date(`${key}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/** Inclusive day count between two date keys (b >= a). */
export function daysInclusive(a: string, b: string): number {
  const ms = new Date(`${b}T00:00:00Z`).getTime() - new Date(`${a}T00:00:00Z`).getTime();
  return Math.round(ms / 86_400_000) + 1;
}
