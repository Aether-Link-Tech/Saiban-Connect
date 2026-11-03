export const ROLES = ["employee", "supervisor", "manager", "hr", "admin"] as const;
export type Role = (typeof ROLES)[number];

export const ACCOUNT_STATUSES = ["pending", "active", "rejected", "disabled"] as const;
export type AccountStatus = (typeof ACCOUNT_STATUSES)[number];

export const LEAVE_TYPES = ["sick", "emergency", "half_day", "other"] as const;
export type LeaveType = (typeof LEAVE_TYPES)[number];

export const DECISIONS = ["approve", "reject"] as const;
export type Decision = (typeof DECISIONS)[number];

export const ATTENDANCE_TYPES = ["check_in", "check_out"] as const;
export type AttendanceType = (typeof ATTENDANCE_TYPES)[number];

/** Accounts created with a phone number only get a synthetic sign-in email on this domain. */
export const SYNTHETIC_EMAIL_DOMAIN = "users.saibaan-connect.app";
