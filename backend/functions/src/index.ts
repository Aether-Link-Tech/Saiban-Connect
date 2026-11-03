// Initializes Firebase Admin and global function options (region) first.
import "./core/firebase";

export { submitRegistration, resolveLoginEmail, reviewRegistration } from "./functions/registration";
export { updateEmployee } from "./functions/employees";
export { requestDeviceChange, reviewDeviceChange } from "./functions/devices";
export { upsertSite, upsertDepartment } from "./functions/sites";
export { syncAttendanceEvents, reviewAttendanceEvent, correctAttendance } from "./functions/attendance";
export { uploadLocationPoints } from "./functions/location";
export { registerFieldPhoto } from "./functions/photos";
export { submitLeaveRequest, cancelLeaveRequest, reviewLeaveRequest } from "./functions/leave";
export { registerFcmToken, unregisterFcmToken } from "./functions/notifications";
export { updatePolicy } from "./functions/policyAdmin";
export { markMissingCheckouts, purgeLocationHistory } from "./functions/scheduled";
