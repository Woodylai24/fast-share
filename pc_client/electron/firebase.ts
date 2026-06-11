import path from "path";
import fs from "fs";
import admin from "firebase-admin";
import { getPairedDeviceFcmToken } from "./settings-store";

// --- Firebase Admin SDK Initialization ---

// Load service account from file
const serviceAccountPath = path.join(__dirname, "service-account.json");
let firebaseInitialized = false;

try {
  if (fs.existsSync(serviceAccountPath)) {
    const serviceAccount = JSON.parse(
      fs.readFileSync(serviceAccountPath, "utf8"),
    );
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    firebaseInitialized = true;
    console.log("[DEBUG] Firebase Admin SDK initialized successfully");
  } else {
    console.warn(
      "[DEBUG] service-account.json not found. Push notifications will be logged but not sent.",
    );
    console.warn(
      "[DEBUG] To enable push notifications, place your Firebase service account key at:",
      serviceAccountPath,
    );
  }
} catch (error) {
  console.error("[DEBUG] Failed to initialize Firebase Admin SDK:", error);
}

// --- Push Notification Function ---
interface PushNotificationPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

async function sendPushNotification(
  deviceId: string,
  payload: PushNotificationPayload,
): Promise<boolean> {
  const fcmToken = getPairedDeviceFcmToken(deviceId);

  if (!fcmToken) {
    console.log(
      "[DEBUG] No FCM token found for device:",
      deviceId,
      "— push notification skipped.",
    );
    return false;
  }

  if (!firebaseInitialized) {
    console.log(
      "[DEBUG] Firebase not initialized. Push notification would be sent to:",
      fcmToken,
    );
    console.log("[DEBUG] Notification payload:", payload);
    return false;
  }

  try {
    await admin.messaging().send({
      notification: {
        title: payload.title,
        body: payload.body,
      },
      data: payload.data || {},
      token: fcmToken,
    });
    console.log("[DEBUG] Push notification sent successfully");
    return true;
  } catch (error) {
    console.error("[DEBUG] Failed to send push notification:", error);
    return false;
  }
}

export { sendPushNotification };
