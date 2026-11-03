# Approval workflows

## Registration
Employee creates a sign-in account on the phone → `submitRegistration` stores a `pending` profile with the phone's device ID → HR/Admin `reviewRegistration`:
- **approve**: assigns role, department, manager, supervisor, sites; the registering phone becomes the approved device.
- **reject**: requires a reason; the employee can correct details and resubmit.

HR can assign Employee/Supervisor/Manager roles only; HR and Administrator roles are Administrator-only.

## Device change (one device per employee)
Signing in on a different phone shows a blocked screen → `requestDeviceChange` → HR/Admin `reviewDeviceChange`. On approval the new device replaces the old one; attendance and location calls from the old phone are refused.

## Leave
Manager (of the employee), HR and Administrator review **in parallel**; each slot keeps its latest decision. Implemented in `backend/functions/src/logic/leaveWorkflow.ts`, configured by `config/policy.leave`:

| Policy | Default | Meaning |
|---|---|---|
| `requiredApprovals` | 2 | Distinct approvals (Manager/HR/Admin) that approve the request |
| `adminCanApproveAlone` | true | Administrator approval alone approves |
| `rejectionBlocks` | true | One Manager/HR rejection rejects |
| `adminCanOverrideRejection` | true | Administrator may approve a rejected request |

**These defaults implement the proposal's current instruction (§11) and must be confirmed by SAIBAAN in writing.** An administrator can change them in the app (Admin → Policy settings) without a code change.

## Attendance review
Flagged events (outside geofence, low accuracy, late sync, mock location, duplicates, etc.) are recorded and marked `reviewStatus: pending`. HR/Admin, or the employee's manager, accept or reject them. Corrections of missed check-in/out are made by roles in `attendance.correctionRoles` (default HR, Admin) with a mandatory reason; every correction is kept in the day record and audit log.
