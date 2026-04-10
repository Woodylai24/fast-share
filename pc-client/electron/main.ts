import { app, BrowserWindow, ipcMain, dialog, shell, clipboard } from "electron";
import path from "path";
import { WebSocketServer, WebSocket } from "ws";
import express from "express";
import http from "http";
import cors from "cors";
import ip from "ip";
import fs from "fs";
import os from "os";
import admin from "firebase-admin";

// --- Initialize Firebase Admin SDK ---
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

// --- Configuration ---
const WS_PORT = 8080;
const HTTP_PORT = 8081;

let mainWindow: BrowserWindow | null = null;
let wss: WebSocketServer | null = null;
let httpServer: http.Server | null = null;

// --- Client Tracking ---
interface ClientInfo {
  ws: WebSocket;
  deviceId?: string; // Optional device identifier for reconnection
}

const connectedClients: Set<ClientInfo> = new Set();

// --- Message Queuing for Offline Clients ---
// Stores messages for clients that are temporarily disconnected (e.g., mobile in background)
interface QueuedMessage {
  type: string;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  data: any;
  timestamp: number;
}

// Map of device ID -> array of queued messages
const messageQueue: Map<string, QueuedMessage[]> = new Map();
// Map of device ID -> FCM token for push notifications
const deviceFcmTokens: Map<string, string> = new Map();

// --- Clipboard Sync ---
let lastClipboardText = clipboard.readText();
setInterval(() => {
  const currentText = clipboard.readText();
  if (currentText && currentText !== lastClipboardText) {
    lastClipboardText = currentText;
    broadcastToClients({ type: "clipboard", content: currentText });
    console.log("[DEBUG] Clipboard changed, broadcasting to clients");
  }
}, 1000);

// Enable remote debugging for VS Code to attach to Renderer
app.commandLine.appendSwitch("remote-debugging-port", "9222");

// --- Helper Functions ---
function getLocalIp() {
  return ip.address(); // Keep for default usage if needed, but better to use dynamic IPs
}

function getLocalIps() {
  const interfaces = os.networkInterfaces();
  const addresses: string[] = [];

  Object.keys(interfaces).forEach((iface) => {
    interfaces[iface]?.forEach((address) => {
      if (address.family === "IPv4" && !address.internal) {
        addresses.push(address.address);
      }
    });
  });

  return addresses;
}

// --- Message Queuing Functions ---
function queueMessage(
  deviceId: string,
  type: string,
  data: QueuedMessage["data"],
) {
  if (!messageQueue.has(deviceId)) {
    messageQueue.set(deviceId, []);
  }
  const queue = messageQueue.get(deviceId);
  if (queue) {
    queue.push({ type, data, timestamp: Date.now() });
    // Keep only last 100 messages in queue
    if (queue.length > 100) {
      queue.shift();
    }
  }
}

function getQueuedMessages(deviceId: string): QueuedMessage[] {
  const messages = messageQueue.get(deviceId) || [];
  messageQueue.delete(deviceId); // Clear queue after retrieval
  return messages;
}

// --- Push Notification Function ---
interface PushNotificationPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

async function sendPushNotification(
  fcmToken: string,
  payload: PushNotificationPayload,
): Promise<boolean> {
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

// --- Broadcast to all clients ---
function broadcastToClients(message: object, excludeWs?: WebSocket) {
  wss?.clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN && client !== excludeWs) {
      client.send(JSON.stringify(message));
    }
  });
}

// --- Server Setup ---
function startServers() {
  // Log all available IPs for debugging
  const allIps = getLocalIps();
  console.log("=== SERVER STARTUP DIAGNOSTICS ===");
  console.log("[DEBUG] Available network interfaces:", allIps);
  console.log("[DEBUG] WebSocket Port:", WS_PORT);
  console.log("[DEBUG] HTTP Port:", HTTP_PORT);

  // 1. HTTP Server (for file transfer)
  const expressApp = express();
  expressApp.use(cors());
  expressApp.use(express.json());

  // Shared directory for files (both uploads from mobile and files offered by PC)
  const sharedDir = path.join(os.homedir(), "FastShare");
  if (!fs.existsSync(sharedDir)) fs.mkdirSync(sharedDir, { recursive: true });
  console.log("[DEBUG] Shared directory:", sharedDir);

  // Endpoint to receive files from Mobile
  expressApp.post("/upload", (req, res) => {
    console.log("[DEBUG] HTTP upload request received from:", req.ip);
    const filename =
      (req.headers["x-filename"] as string) || `upload-${Date.now()}.bin`;
    const savePath = path.join(sharedDir, filename);

    const fileStream = fs.createWriteStream(savePath);
    req.pipe(fileStream);

    fileStream.on("finish", () => {
      console.log(`[DEBUG] File saved to ${savePath}`);
      // Notify Renderer
      mainWindow?.webContents.send("file-received", {
        filename,
        path: savePath,
      });
      // Note: Don't broadcast to mobile - they already add the file optimistically on their side.
      res.status(200).send("Upload complete");
    });

    fileStream.on("error", (err) => {
      console.error("[DEBUG] File write error:", err);
      res.status(500).send("Write error");
    });
  });

  // Endpoint to serve files to Mobile
  expressApp.use("/files", express.static(sharedDir));

  httpServer = expressApp.listen(HTTP_PORT, () => {
    console.log(
      `[DEBUG] HTTP Server running on http://${getLocalIp()}:${HTTP_PORT}`,
    );
    console.log(
      "[DEBUG] HTTP Server listening on ALL interfaces (0.0.0.0):" + HTTP_PORT,
    );
  });
  console.log("[DEBUG] HTTP Server address:", httpServer.address());

  // 2. WebSocket Server (for signaling & text)
  console.log("[DEBUG] Starting WebSocket Server on port", WS_PORT);
  wss = new WebSocketServer({ port: WS_PORT });

  wss.on("error", (error) => {
    console.error("[DEBUG] WebSocket Server ERROR:", error);
  });

  wss.on("listening", () => {
    console.log("[DEBUG] WebSocket Server is LISTENING on port", WS_PORT);
    console.log("[DEBUG] WebSocket Server should be accessible at:");
    allIps.forEach((ip) => {
      console.log(`[DEBUG]   ws://${ip}:${WS_PORT}`);
    });
  });

  wss.on("connection", (ws: WebSocket, req) => {
    // Log the client's IP address
    const clientIp = req.socket.remoteAddress || "unknown";
    console.log("[DEBUG] === MOBILE CLIENT CONNECTED ===");
    console.log("[DEBUG] Client IP:", clientIp);
    console.log("[DEBUG] Connection time:", new Date().toISOString());

    // Track this client
    const clientInfo: ClientInfo = {
      ws,
    };
    connectedClients.add(clientInfo);

    ws.on("message", (message: string) => {
      console.log("[DEBUG] Received message:", message.toString());
      try {
        const data = JSON.parse(message.toString());
        console.log("[DEBUG] Parsed message type:", data.type);

        // Handle handshake from mobile - don't forward to renderer
        if (data.type === "handshake") {
          console.log("[DEBUG] Received handshake from mobile:", data.device);

          // Store device ID if provided for reconnection support
          if (data.deviceId) {
            clientInfo.deviceId = data.deviceId;
            console.log("[DEBUG] Device ID:", data.deviceId);

            // Store FCM token if provided
            if (data.fcmToken) {
              deviceFcmTokens.set(data.deviceId, data.fcmToken);
              console.log(
                "[DEBUG] Stored FCM token for device:",
                data.deviceId,
              );
            }

            // Send any queued messages for this device
            const queuedMessages = getQueuedMessages(data.deviceId);
            if (queuedMessages.length > 0) {
              console.log(
                "[DEBUG] Sending",
                queuedMessages.length,
                "queued messages to device",
              );
              queuedMessages.forEach((msg) => {
                if (ws.readyState === WebSocket.OPEN) {
                  ws.send(JSON.stringify(msg.data));
                }
              });
            }
          }
          return; // Don't forward mobile's handshake to renderer
        }

        // Handle reconnect message from mobile (after being in background)
        if (data.type === "reconnect") {
          console.log("[DEBUG] Client reconnecting, device ID:", data.deviceId);
          if (data.deviceId) {
            clientInfo.deviceId = data.deviceId;
            const queuedMessages = getQueuedMessages(data.deviceId);
            if (queuedMessages.length > 0) {
              console.log(
                "[DEBUG] Sending",
                queuedMessages.length,
                "queued messages on reconnect",
              );
              queuedMessages.forEach((msg) => {
                if (ws.readyState === WebSocket.OPEN) {
                  ws.send(JSON.stringify(msg.data));
                }
              });
            }
          }
          return;
        }

        // Handle disconnect message from mobile
        if (data.type === "disconnect") {
          console.log("[DEBUG] Client sent disconnect message:", data.reason);
          // Notify renderer
          mainWindow?.webContents.send("ws-disconnect", {
            reason: data.reason || "Mobile client disconnected",
          });
          // Close the connection
          connectedClients.delete(clientInfo);
          ws.close();
          return;
        }

        // Forward other messages to Renderer
        if (data.type === "clipboard") {
          clipboard.writeText(data.content);
          lastClipboardText = data.content; // Avoid loopback
          console.log("[DEBUG] Received clipboard from mobile");
          // Show Windows notification
          const { Notification } = require("electron");
          if (Notification.isSupported()) {
            new Notification({
              title: "Fast Share - Clipboard Sync",
              body: data.content.length > 100 ? data.content.substring(0, 100) + "..." : data.content,
              silent: false,
            }).show();
          }
        }
        mainWindow?.webContents.send("ws-message", data);
      } catch (error) {
        console.error("[DEBUG] Failed to parse WS message", error);
      }
    });

    ws.on("close", (code, reason) => {
      console.log(
        "[DEBUG] WebSocket CLOSED - Code:",
        code,
        "Reason:",
        reason.toString(),
      );

      // Remove from tracked clients
      connectedClients.delete(clientInfo);

      // Only notify renderer about intentional disconnects
      // Code 1006 = abnormal closure (mobile app went to background)
      // Code 1000 = normal closure
      // Code 1001 = going away (browser closing)
      const isAbnormalClosure = code === 1006;
      const isIntentionalDisconnect = code === 1000 || code === 1001;

      if (!isAbnormalClosure) {
        // Notify renderer about disconnect only for intentional disconnects
        // For abnormal closures (mobile in background), we keep the UI connected
        // so the user can still send messages (which will be queued and sent via push)
        mainWindow?.webContents.send("ws-disconnect", {
          reason: isIntentionalDisconnect
            ? "Connection closed"
            : `Connection lost (code: ${code})`,
          deviceId: clientInfo.deviceId,
        });
      } else {
        // For abnormal closures, just log it - the mobile will reconnect when back in foreground
        console.log(
          "[DEBUG] Abnormal closure detected - mobile likely in background. Keeping UI connected.",
        );
        console.log(
          "[DEBUG] Messages will be queued and sent via push notification.",
        );
      }
    });

    ws.on("error", (error) => {
      console.error("[DEBUG] WebSocket ERROR:", error);
      connectedClients.delete(clientInfo);
    });

    // Send handshake to client
    ws.send(JSON.stringify({ type: "handshake", message: "Connected to PC" }));

    // Notify renderer that a client has connected
    mainWindow?.webContents.send("ws-message", {
      type: "handshake",
      message: "Mobile Connected",
    });
  });

  console.log(
    `[DEBUG] WebSocket Server initialized on ws://${getLocalIp()}:${WS_PORT}`,
  );
  console.log("=== END SERVER STARTUP ===");
}

// --- IPC Handlers ---
function setupIpc() {
  // Window control handlers
  ipcMain.on("window-minimize", () => {
    mainWindow?.minimize();
  });

  ipcMain.on("window-maximize", () => {
    if (mainWindow?.isMaximized()) {
      mainWindow.unmaximize();
    } else {
      mainWindow?.maximize();
    }
  });

  ipcMain.on("window-close", () => {
    mainWindow?.close();
  });

  ipcMain.handle("window-is-maximized", () => {
    return mainWindow?.isMaximized() || false;
  });

  ipcMain.on("open-external", async (event, url: string) => {
    try {
      await shell.openExternal(url);
    } catch (error) {
      console.error("[DEBUG] Failed to open external URL:", error);
    }
  });

  ipcMain.handle("get-connection-info", () => {
    return {
      ips: getLocalIps(),
      wsPort: WS_PORT,
      httpPort: HTTP_PORT,
    };
  });

  ipcMain.on("send-text", (event, text) => {
    const message = { type: "text", content: text };
    let sent = false;

    // Broadcast to all connected mobile clients
    wss?.clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(JSON.stringify(message));
        sent = true;
      }
    });

    // If no clients connected, queue the message and send push notification
    if (!sent) {
      // Queue for all known devices
      deviceFcmTokens.forEach(async (fcmToken, deviceId) => {
        queueMessage(deviceId, "text", message);
        // Send push notification to wake up the app
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

  ipcMain.on("disconnect-client", () => {
    console.log("[DEBUG] PC Client requested disconnect");

    // Send disconnect message to all mobile clients
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
    connectedClients.clear();
  });

  ipcMain.handle("select-file", async () => {
    if (!mainWindow) return undefined;
    const result = await dialog.showOpenDialog(mainWindow, {
      properties: ["openFile", "multiSelections"],
    });
    if (result.canceled) {
      return undefined;
    } else {
      return result.filePaths;
    }
  });

  ipcMain.on("offer-file", (event, filePath, ip) => {
    // 1. Copy file to shared dir (same directory as uploads)
    const fileName = path.basename(filePath);
    const sharedDir = path.join(os.homedir(), "FastShare");
    if (!fs.existsSync(sharedDir)) fs.mkdirSync(sharedDir, { recursive: true });

    const destPath = path.join(sharedDir, fileName);
    fs.copyFileSync(filePath, destPath);

    // 2. Create URL
    // Use the IP passed from the frontend (selected by user) or fallback to detected one
    const hostIp = ip || getLocalIp();
    const fileUrl = `http://${hostIp}:${HTTP_PORT}/files/${encodeURIComponent(
      fileName,
    )}`;

    // 3. Determine message type based on file extension
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

    const message = {
      type: messageType,
      filename: fileName,
      url: fileUrl,
    };

    // 4. Broadcast Offer
    let sent = false;
    wss?.clients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(JSON.stringify(message));
        sent = true;
      }
    });

    // 5. If no clients connected, queue the message and send push notification
    if (!sent) {
      deviceFcmTokens.forEach(async (fcmToken, deviceId) => {
        queueMessage(deviceId, messageType, message);
        // Send push notification to wake up the app
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
}

// --- Electron Window ---
function createWindow() {
  mainWindow = new BrowserWindow({
    width: 900,
    height: 600,
    frame: false, // Remove default window frame
    transparent: false, // Keep false for resizability
    backgroundColor: "#242424", // Match app background
    resizable: true, // Allow window resizing
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      nodeIntegration: false,
      contextIsolation: true,
    },
  });

  if (!app.isPackaged) {
    mainWindow.loadURL("http://localhost:5173");
    mainWindow.webContents.openDevTools();
  } else {
    mainWindow.loadFile(path.join(__dirname, "../dist/index.html"));
  }
}




app.whenReady().then(() => {
  setupIpc();
  startServers();
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});
