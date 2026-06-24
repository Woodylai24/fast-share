import path from "path";
import fs from "fs";
import os from "os";
import { CryptoManager } from "./crypto";

// --- MimeType Lookup ---
function getMimeType(filename: string): string {
  const ext = path.extname(filename).toLowerCase();
  const mimeMap: Record<string, string> = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".gif": "image/gif",
    ".bmp": "image/bmp",
    ".webp": "image/webp",
    ".svg": "image/svg+xml",
    ".pdf": "application/pdf",
    ".zip": "application/zip",
    ".txt": "text/plain",
    ".json": "application/json",
    ".mp4": "video/mp4",
    ".mp3": "audio/mpeg",
  };
  return mimeMap[ext] || "application/octet-stream";
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type GetMainWindowFn = () => any;

/** Tell the renderer to play the notification sound via IPC. */
function playNotificationSound(getMainWindow: GetMainWindowFn) {
  getMainWindow()?.webContents.send("play-notification-sound");
}

/**
 * Process a decrypted (or plaintext legacy) message from a mobile client.
 * Handles clipboard, text, file, image, and default messages.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function processFileMessage(clientInfo: any, data: any, getMainWindow: GetMainWindowFn) {
  const msgType = data.type;

  switch (msgType) {
    case "clipboard": {
      // Incoming clipboard events are ALWAYS auto-copied regardless of the
      // local clipboard-sync setting (the setting only controls OUTGOING).
      const { setLastClipboardText } = require("./clipboard-sync");
      const { clipboard, Notification } = require("electron");
      const settingsStore = require("./settings-store").default;

      clipboard.writeText(data.content);
      setLastClipboardText(data.content);
      console.log("[DEBUG] Received clipboard from mobile, auto-copied to clipboard");

      // Show Windows notification (gated by notificationsEnabled setting)
      const notificationsEnabled = settingsStore.get("notificationsEnabled", true) as boolean;
      const soundOnMessage = settingsStore.get("soundOnMessage", true) as boolean;
      if (notificationsEnabled && Notification.isSupported()) {
        new Notification({
          title: "Fast Share - Clipboard Sync",
          body:
            data.content.length > 100
              ? data.content.substring(0, 100) + "..."
              : data.content,
          silent: true,
        }).show();
      }
      if (soundOnMessage) {
        playNotificationSound(getMainWindow);
      }

      getMainWindow()?.webContents.send("ws-message", data);
      break;
    }

    case "text": {
      getMainWindow()?.webContents.send("ws-message", data);

      // Show Windows notification for incoming text messages (gated by setting)
      const { Notification: ElectronNotification } = require("electron");
      const settingsStore = require("./settings-store").default;
      const notificationsEnabled = settingsStore.get("notificationsEnabled", true) as boolean;
      const soundOnMessage = settingsStore.get("soundOnMessage", true) as boolean;
      if (notificationsEnabled && ElectronNotification.isSupported()) {
        const text = typeof data.content === "string" ? data.content : "";
        new ElectronNotification({
          title: "Fast Share - New Message",
          body:
            text.length > 100
              ? text.substring(0, 100) + "..."
              : text,
          silent: true,
        }).show();
      }
      if (soundOnMessage) {
        playNotificationSound(getMainWindow);
      }
      break;
    }

    // Legacy file/image messages (HTTP-based)
    case "file":
    case "image": {
      getMainWindow()?.webContents.send("ws-message", data);
      break;
    }

    default: {
      // Forward everything else to renderer
      getMainWindow()?.webContents.send("ws-message", data);
      break;
    }
  }
}

export {
  processFileMessage,
  getMimeType,
};
