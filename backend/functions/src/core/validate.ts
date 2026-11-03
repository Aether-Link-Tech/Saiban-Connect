import { HttpsError } from "firebase-functions/v2/https";
import { isValidDateKey } from "./time";

export function bad(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

export function asObject(v: unknown): Record<string, unknown> {
  if (v === null || typeof v !== "object" || Array.isArray(v)) bad("Request body must be an object.");
  return v as Record<string, unknown>;
}

export function reqString(v: unknown, field: string, max = 500, min = 1): string {
  if (typeof v !== "string") bad(`${field} is required.`);
  const s = v.trim();
  if (s.length < min || s.length > max) bad(`${field} must be ${min}-${max} characters.`);
  return s;
}

export function optString(v: unknown, field: string, max = 500): string | null {
  if (v === undefined || v === null || (typeof v === "string" && v.trim() === "")) return null;
  return reqString(v, field, max, 1);
}

export function reqNumber(v: unknown, field: string, min = -Infinity, max = Infinity): number {
  if (typeof v !== "number" || !Number.isFinite(v)) bad(`${field} must be a number.`);
  if (v < min || v > max) bad(`${field} must be between ${min} and ${max}.`);
  return v;
}

export function optNumber(v: unknown, field: string, min = -Infinity, max = Infinity): number | null {
  if (v === undefined || v === null) return null;
  return reqNumber(v, field, min, max);
}

export function reqBool(v: unknown, field: string): boolean {
  if (typeof v !== "boolean") bad(`${field} must be true or false.`);
  return v;
}

export function optBool(v: unknown, field: string): boolean | null {
  if (v === undefined || v === null) return null;
  return reqBool(v, field);
}

export function oneOf<T extends string>(v: unknown, field: string, allowed: readonly T[]): T {
  if (typeof v !== "string" || !(allowed as readonly string[]).includes(v)) {
    bad(`${field} must be one of: ${allowed.join(", ")}.`);
  }
  return v as T;
}

/** Client-generated identifiers (UUIDs, Firestore auto IDs). */
export function reqId(v: unknown, field: string): string {
  const s = reqString(v, field, 64, 6);
  if (!/^[A-Za-z0-9_-]+$/.test(s)) bad(`${field} has an invalid format.`);
  return s;
}

export function optId(v: unknown, field: string): string | null {
  if (v === undefined || v === null || v === "") return null;
  return reqId(v, field);
}

export function reqDateKey(v: unknown, field: string): string {
  const s = reqString(v, field, 10, 10);
  if (!isValidDateKey(s)) bad(`${field} must be a date in YYYY-MM-DD format.`);
  return s;
}

export function stringArray(v: unknown, field: string, maxItems: number, maxLen = 300): string[] {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v)) bad(`${field} must be a list.`);
  if (v.length > maxItems) bad(`${field} can contain at most ${maxItems} items.`);
  const out = v.map((x, i) => reqString(x, `${field}[${i}]`, maxLen));
  return [...new Set(out)];
}
