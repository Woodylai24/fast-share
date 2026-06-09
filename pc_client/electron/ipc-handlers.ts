import { ipcMain, safeStorage, dialog, shell } from "electron";
import path from "path";
import fs from "fs";
import os from "os";
import { WebSocket } from "ws";
import { sendEncrypted, broadcastToClients, connectedClients, getLocalIp, getLocalIps, WS_PORT, HTTP_PORT, wss, queueMessage, stopHeartbeat } from "./server";
import { sendFileEncrypted } from "./file-transfer";
import { sendPushNotification, deviceFcmTokens } from "./firebase";
import { aiSettingsStore } from "./ai-summarize";
import settingsStore from "./settings-store";
import { app } from "electron";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type GetMainWindowFn = () => any;

interface IpcHandlerOptions {
  onClipboardSettingChanged?: () => void;
}

function registerIpcHandlers(
  ipcMainInstance: typeof ipcMain,
  getMainWindow: GetMainWindowFn,
  options?: IpcHandlerOptions,
) {
  // AI Settings handlers
  ipcMainInstance.handle("get-ai-settings", () => {
    const apiKeyEncrypted = aiSettingsStore.get("apiKeyEncrypted") as string;
    const provider = aiSettingsStore.get("provider") as string;
    const model = aiSettingsStore.get("model") as string;

    let apiKey: string | null = null;
    if (apiKeyEncrypted) {
      apiKey = "••••••••"; // masked
    }

    return { apiKey, provider, model };
  });

  ipcMainInstance.handle("save-ai-settings", (_event, settings: { apiKey?: string; provider?: string; model?: string }) => {
    try {
      if (settings.apiKey !== undefined) {
        if (safeStorage.isEncryptionAvailable()) {
          const encrypted = safeStorage.encryptString(settings.apiKey);
          aiSettingsStore.set("apiKeyEncrypted", encrypted.toString("base64"));
        } else {
          console.warn("[AI Settings] safeStorage not available — storing API key in plaintext");
          aiSettingsStore.set("apiKeyEncrypted", settings.apiKey);
        }
      }
      if (settings.provider !== undefined) {
        aiSettingsStore.set("provider", settings.provider);
      }
      if (settings.model !== undefined) {
        aiSettingsStore.set("model", settings.model);
      }
      return { success: true };
    } catch (error) {
      console.error("[AI Settings] Failed to save settings:", error);
      return { success: false };
    }
  });

  // Window control handlers
  ipcMainInstance.on("window-minimize", () => {
    getMainWindow()?.minimize();
  });

  ipcMainInstance.on("window-maximize", () => {
    if (getMainWindow()?.isMaximized()) {
      getMainWindow().unmaximize();
    } else {
      getMainWindow()?.maximize();
    }
  });

  ipcMainInstance.on("window-close", () => {
    getMainWindow()?.close();
  });

  ipcMainInstance.handle("window-is-maximized", () => {
    return getMainWindow()?.isMaximized() || false;
  });

  ipcMainInstance.on("open-external", async (event, url: string) => {
    try {
      await shell.openExternal(url);
    } catch (error) {
      console.error("[DEBUG] Failed to open external URL:", error);
    }
  });

  ipcMainInstance.on("open-path", async (event, filePath: string) => {
    try {
      await shell.openPath(filePath);
    } catch (error) {
      console.error("[DEBUG] Failed to open file:", error);
    }
  });

  ipcMainInstance.on("open-folder", async () => {
    try {
      const fastShareDir = path.join(os.homedir(), "FastShare");
      if (!fs.existsSync(fastShareDir)) {
        fs.mkdirSync(fastShareDir, { recursive: true });
      }
      await shell.openPath(fastShareDir);
    } catch (error) {
      console.error("[DEBUG] Failed to open FastShare folder:", error);
    }
  });

  ipcMainInstance.handle("get-connection-info", () => {
    return {
      ips: getLocalIps(),
      wsPort: WS_PORT,
      httpPort: HTTP_PORT,
    };
  });

  ipcMainInstance.on("send-text", (event, text) => {
    const message = { type: "text", content: text };

    // Send encrypted to all connected clients
    let sent = false;
    connectedClients.forEach((client) => {
      if (client.ws.readyState === WebSocket.OPEN && client.keyExchangeComplete) {
        sendEncrypted(client, message);
        sent = true;
      } else if (client.ws.readyState === WebSocket.OPEN) {
        // Key exchange not complete, send plaintext as fallback
        client.ws.send(JSON.stringify(message));
        sent = true;
      }
    });

    // If no clients connected, queue the message and send push notification
    if (!sent) {
      deviceFcmTokens.forEach(async (fcmToken, deviceId) => {
        queueMessage(deviceId, "text", message);
        await sendPushNotification(fcmToken, {
          title: "New Message",
          body: text.length > 50 ? text.substring(0, 50) + "..." : text,
          data: { type: "text" },
        });
      });
      console.log(
        "[DEBUG] No clients connected, text message queued and notification sent",
      );
    }
  });

  ipcMainInstance.on("disconnect-client", () => {
    console.log("[DEBUG] PC Client requested disconnect");

    // Send disconnect message to all mobile clients (unencrypted)
    broadcastToClients({
      type: "disconnect",
      reason: "PC client disconnected",
    });

    // Close all connections
    wss?.clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) {
        client.close(1000, "PC client disconnected");
      }
    });

    // Clear tracked clients
    const { cleanupFileReassembly } = require("./file-transfer");
    connectedClients.forEach((client) => {
      stopHeartbeat(client);
      cleanupFileReassembly(client);
      if (client.keyExchangeTimer) {
        clearTimeout(client.keyExchangeTimer);
      }
    });
    connectedClients.clear();
  });

  // Renderer sends pong in response to a ping from mobile (relayed through server)
  ipcMainInstance.on("send-pong", () => {
    connectedClients.forEach((client) => {
      if (client.ws.readyState === WebSocket.OPEN) {
        client.ws.send(JSON.stringify({ type: "pong" }));
      }
    });
  });

  ipcMainInstance.handle("select-file", async () => {
    const mw = getMainWindow();
    if (!mw) return undefined;
    const result = await dialog.showOpenDialog(mw, {
      properties: ["openFile", "multiSelections"],
    });
    if (result.canceled) {
      return undefined;
    } else {
      return result.filePaths;
    }
  });

  ipcMainInstance.on("offer-file", (event, filePath, ip) => {
    const fileName = path.basename(filePath);
    const sharedDir = path.join(os.homedir(), "FastShare");
    if (!fs.existsSync(sharedDir)) fs.mkdirSync(sharedDir, { recursive: true });

    const destPath = path.join(sharedDir, fileName);
    fs.copyFileSync(filePath, destPath);

    const hostIp = ip || getLocalIp();
    const fileUrl = `http://${hostIp}:${HTTP_PORT}/files/${encodeURIComponent(
      fileName,
    )}`;

    const imageExtensions = [
      ".jpg",
      ".jpeg",
      ".png",
      ".gif",
      ".bmp",
      ".webp",
      ".svg",
    ];
    const ext = path.extname(fileName).toLowerCase();
    const messageType = imageExtensions.includes(ext) ? "image" : "file";

    // Try encrypted chunked file transfer first, fall back to legacy URL-based offer
    let sentViaWs = false;
    connectedClients.forEach((client) => {
      if (
        client.ws.readyState === WebSocket.OPEN &&
        client.keyExchangeComplete
      ) {
        // Send file via encrypted chunked WS transfer
        sendFileEncrypted(client, destPath, fileName, messageType, sendEncrypted, getMainWindow);
        sentViaWs = true;
      }
    });

    // Also offer legacy URL-based file for clients without key exchange
    const legacyMessage = {
      type: messageType,
      filename: fileName,
      url: fileUrl,
    };

    let sentLegacy = false;
    connectedClients.forEach((client) => {
      if (
        client.ws.readyState === WebSocket.OPEN &&
        !client.keyExchangeComplete
      ) {
        client.ws.send(JSON.stringify(legacyMessage));
        sentLegacy = true;
      }
    });

    // If no clients connected, queue and send push notification
    if (!sentViaWs && !sentLegacy) {
      deviceFcmTokens.forEach(async (fcmToken, deviceId) => {
        queueMessage(deviceId, messageType, legacyMessage);
        await sendPushNotification(fcmToken, {
          title: messageType === "image" ? "Image Received" : "File Received",
          body: fileName,
          data: { type: messageType, filename: fileName, url: fileUrl },
        });
      });
      console.log(
        "[DEBUG] No clients connected, file offer queued and notification sent:",
        fileName,
      );
    }
  });

  // ── General Settings handlers ──────────────────────────────────────────
  ipcMainInstance.handle("get-settings", () => {
    return settingsStore.store;
  });

  ipcMainInstance.handle(
    "save-settings",
    (
      _event,
      settings: Partial<{
        startupOnBoot: boolean;
        minimizeToTray: boolean;
        clipboardSync: string;
        soundOnMessage: boolean;
        notificationsEnabled: boolean;
        theme: string;
      }>,
    ) => {
      try {
        const prevClipboardSync = settingsStore.get("clipboardSync");

        for (const [key, value] of Object.entries(settings)) {
          settingsStore.set(key, value);
        }

        // Side-effect: startupOnBoot → update login item
        if (settings.startupOnBoot !== undefined) {
          app.setLoginItemSettings({ openAtLogin: settings.startupOnBoot });
        }

        // Side-effect: clipboardSync changed → restart clipboard watcher
        const newClipboardSync = settingsStore.get("clipboardSync");
        if (newClipboardSync !== prevClipboardSync) {
          options?.onClipboardSettingChanged?.();
        }

        // Notify renderer of the updated settings
        const mw = getMainWindow();
        if (mw && !mw.isDestroyed()) {
          mw.webContents.send("settings-changed", settingsStore.store);
        }

        return { success: true };
      } catch (error) {
        console.error("[Settings] Failed to save settings:", error);
        return { success: false };
      }
    },
  );
}

export { registerIpcHandlers };
