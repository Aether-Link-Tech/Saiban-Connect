import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { getStorage } from "firebase-admin/storage";
import { setGlobalOptions } from "firebase-functions/v2";

/** Mumbai region: closest Firebase region to Pakistan. Must match the mobile client. */
export const REGION = "asia-south1";

setGlobalOptions({ region: REGION, maxInstances: 10 });

if (getApps().length === 0) initializeApp();

export const db = getFirestore();
export const adminAuth = getAuth();
export const messaging = getMessaging();
export const bucket = () => getStorage().bucket();
