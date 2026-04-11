import { app, BrowserWindow, ipcMain, dialog, shell, clipboard, safeStorage } from "electron";
import path from "path";
import { WebSocketServer, WebSocket } from "ws";
import express from "express";
import http from "http";
import cors from "cors";
import ip from "ip";
import fs from "fs";
import os from "os";
import admin from "firebase-admin";
import crypto from "crypto";
import { CryptoManager, isUnencryptedType } from "./crypto";
// eslint-disable-next-line @typescript-eslint/no-require-imports
const ElectronStore = require("electron-store").default;
// eslint-disable-next-line @typescript-eslint/no-require-imports
const pdfParse = require("pdf-parse");
// eslint-disable-next-line @typescript-eslint/no-require-imports
const mammoth = require("mammoth");

// --- Active Summarize Streams ---
const activeSummarizeStreams = new Map<string, AbortController>();

// Supported text file extensions for summarization
const SUMMARIZABLE_EXTENSIONS = new Set([
  ".txt", ".md", ".json", ".csv", ".log", ".xml", ".yaml", ".yml", ".ini", ".conf",
  ".cfg", ".toml", ".env", ".sh", ".bat", ".py", ".js", ".ts", ".html", ".css",
  ".sql", ".rb", ".go", ".rs", ".java", ".c", ".cpp", ".h", ".hpp", ".tsx",
  ".jsx", ".vue", ".svelte", ".dart", ".php", ".r", ".swift", ".kt",
  ".pdf", ".docx",
]);

const IMAGE_EXTENSIONS = new Set([
  ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".svg",
]);

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const aiSettingsStore: { get: (key: string) => any; set: (key: string, value: any) => void } = new ElectronStore({
  name: "fastshare-ai-settings",
  defaults: {
    apiKeyEncrypted: "",
    provider: "openrouter",
    model: "openrouter/auto",
  },
}) as any;

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
const FILE_CHUNK_SIZE = 64 * 1024; // 64KB chunks
const KEY_EXCHANGE_TIMEOUT_MS = 5000; // 5 seconds
const CHUNK_REASSEMBLY_TIMEOUT_MS = 30000; // 30 seconds

let mainWindow: BrowserWindow | null = null;
let wss: WebSocketServer | null = null;
let httpServer: http.Server | null = null;


// --- Client Tracking ---
interface ClientInfo {
  ws: WebSocket;
  deviceId?: string;
  crypto: CryptoManager;
  keyExchangeComplete: boolean;
  keyExchangeTimer?: ReturnType<typeof setTimeout>;
  // File chunk reassembly state
  incomingFile?: {
    filename: string;
    fileSize: number;
    mimeType: string;
    chunks: Buffer[];
    receivedBytes: number;
    timer: ReturnType<typeof setTimeout>;
  };
}

const connectedClients: Set<ClientInfo> = new Set();

// --- Message Queuing for Offline Clients ---
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
    sendEncryptedToClients({ type: "clipboard", content: currentText });
    console.log("[DEBUG] Clipboard changed, broadcasting to clients (encrypted)");
  }
}, 1000);

// Enable remote debugging for VS Code to attach to Renderer
app.commandLine.appendSwitch("remote-debugging-port", "9222");

// --- Helper Functions ---
function getLocalIp() {
  return ip.address();
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
  messageQueue.delete(deviceId);
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

// --- Encrypt and send to a single client ---
function sendEncrypted(client: ClientInfo, data: object) {
  if (client.ws.readyState !== WebSocket.OPEN) return;

  if (!client.keyExchangeComplete || !client.crypto.isReady()) {
    // Key exchange not done — fall back to plaintext
    client.ws.send(JSON.stringify(data));
    return;
  }

  try {
    const encrypted = client.crypto.encrypt(data);
    client.ws.send(
      JSON.stringify({
        type: "encrypted",
        ...encrypted,
      }),
    );
  } catch (error) {
    console.error("[DEBUG] Failed to encrypt message, sending plaintext:", error);
    client.ws.send(JSON.stringify(data));
  }
}

// --- Broadcast encrypted to all clients ---
function sendEncryptedToClients(message: object, excludeClient?: ClientInfo) {
  connectedClients.forEach((client) => {
    if (client.ws.readyState === WebSocket.OPEN && client !== excludeClient) {
      sendEncrypted(client, message);
    }
  });
}

// --- Legacy broadcast (plaintext, for queued messages fallback) ---
function broadcastToClients(message: object, excludeWs?: WebSocket) {
  wss?.clients.forEach((client) => {
    if (client.readyState === WebSocket.OPEN && client !== excludeWs) {
      client.send(JSON.stringify(message));
    }
  });
}

// --- File chunk reassembly cleanup ---
function cleanupFileReassembly(client: ClientInfo) {
  if (client.incomingFile) {
    clearTimeout(client.incomingFile.timer);
    client.incomingFile = undefined;
  }
}

// --- Server Setup ---
function startServers() {
  const allIps = getLocalIps();
  console.log("=== SERVER STARTUP DIAGNOSTICS ===");
  console.log("[DEBUG] Available network interfaces:", allIps);
  console.log("[DEBUG] WebSocket Port:", WS_PORT);
  console.log("[DEBUG] HTTP Port:", HTTP_PORT);

  // 1. HTTP Server (fallback for file transfer)
  const expressApp = express();
  expressApp.use(cors());
  expressApp.use(express.json());

  const sharedDir = path.join(os.homedir(), "FastShare");
  if (!fs.existsSync(sharedDir)) fs.mkdirSync(sharedDir, { recursive: true });
  console.log("[DEBUG] Shared directory:", sharedDir);

  // Endpoint to receive files from Mobile (legacy HTTP fallback)
  expressApp.post("/upload", (req, res) => {
    console.log("[DEBUG] HTTP upload request received from:", req.ip);
    const filename =
      (req.headers["x-filename"] as string) || `upload-${Date.now()}.bin`;
    const savePath = path.join(sharedDir, filename);

    const fileStream = fs.createWriteStream(savePath);
    req.pipe(fileStream);

    fileStream.on("finish", () => {
      console.log(`[DEBUG] File saved to ${savePath}`);
      mainWindow?.webContents.send("file-received", {
        filename,
        path: savePath,
      });
      res.status(200).send("Upload complete");
    });

    fileStream.on("error", (err) => {
      console.error("[DEBUG] File write error:", err);
      res.status(500).send("Write error");
    });
  });

  // Endpoint to serve files to Mobile (legacy HTTP fallback)
  expressApp.use("/files", express.static(sharedDir));

  httpServer = expressApp.listen(HTTP_PORT, "127.0.0.1", () => {
    console.log(
      `[DEBUG] HTTP Server running on http://${getLocalIp()}:${HTTP_PORT}`,
    );
    console.log(
      "[DEBUG] HTTP Server listening on ALL interfaces (0.0.0.0):" + HTTP_PORT,
    );
  });
  console.log("[DEBUG] HTTP Server address:", httpServer.address());

  // 2. WebSocket Server (with E2EE)
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
    const clientIp = req.socket.remoteAddress || "unknown";
    console.log("[DEBUG] === MOBILE CLIENT CONNECTED ===");
    console.log("[DEBUG] Client IP:", clientIp);
    console.log("[DEBUG] Connection time:", new Date().toISOString());

    // Create client info with a new ephemeral CryptoManager
    const clientInfo: ClientInfo = {
      ws,
      crypto: new CryptoManager(),
      keyExchangeComplete: false,
    };
    connectedClients.add(clientInfo);

    // Set a timeout for key exchange — close connection if not completed
    clientInfo.keyExchangeTimer = setTimeout(() => {
      if (!clientInfo.keyExchangeComplete) {
        console.error("[DEBUG] Key exchange timeout — closing connection");
        ws.close(4001, "Key exchange timeout");
      }
    }, KEY_EXCHANGE_TIMEOUT_MS);

    ws.on("message", (message: string) => {
      console.log("[DEBUG] Received message:", message.toString());
      try {
        const data = JSON.parse(message.toString());
        console.log("[DEBUG] Parsed message type:", data.type);

        // --- Unencrypted message types ---
        if (data.type === "handshake") {
          console.log("[DEBUG] Received handshake from mobile:", data.device);

          if (data.deviceId) {
            clientInfo.deviceId = data.deviceId;
            console.log("[DEBUG] Device ID:", data.deviceId);

            if (data.fcmToken) {
              deviceFcmTokens.set(data.deviceId, data.fcmToken);
              console.log(
                "[DEBUG] Stored FCM token for device:",
                data.deviceId,
              );
            }

            // Send queued messages (they may be plaintext for legacy compat)
            const queuedMessages = getQueuedMessages(data.deviceId);
            if (queuedMessages.length > 0) {
              console.log(
                "[DEBUG] Sending",
                queuedMessages.length,
                "queued messages to device",
              );
              // Queued messages are sent as plaintext since key exchange isn't done yet
              queuedMessages.forEach((msg) => {
                if (ws.readyState === WebSocket.OPEN) {
                  ws.send(JSON.stringify(msg.data));
                }
              });
            }
          }

          // Respond with handshake + our public key for key exchange
          ws.send(
            JSON.stringify({
              type: "handshake",
              message: "Connected to PC",
            }),
          );

          // Initiate key exchange — send our public key
          const ourPubKey = clientInfo.crypto.getPublicKeyBase64();
          ws.send(
            JSON.stringify({
              type: "key-exchange",
              publicKey: ourPubKey,
            }),
          );
          console.log("[DEBUG] Sent key-exchange with public key");

          // Notify renderer that a client has connected
          mainWindow?.webContents.send("ws-message", {
            type: "handshake",
            message: "Mobile Connected",
          });
          return;
        }

        if (data.type === "key-exchange") {
          console.log("[DEBUG] Received key-exchange from mobile");
          try {
            clientInfo.crypto.computeSharedSecret(data.publicKey);
            clientInfo.keyExchangeComplete = true;
            // Clear key exchange timeout
            if (clientInfo.keyExchangeTimer) {
              clearTimeout(clientInfo.keyExchangeTimer);
              clientInfo.keyExchangeTimer = undefined;
            }
            console.log("[DEBUG] Key exchange complete — encrypted channel established");
          } catch (error) {
            console.error("[DEBUG] Key exchange failed:", error);
            ws.close(4002, "Key exchange failed");
          }
          return;
        }

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
          // Re-do key exchange on reconnect — send new public key
          const newClientInfo: ClientInfo = {
            ws,
            deviceId: clientInfo.deviceId,
            crypto: new CryptoManager(),
            keyExchangeComplete: false,
          };
          // Replace the client info in the set
          connectedClients.delete(clientInfo);
          connectedClients.add(newClientInfo);

          // Set key exchange timeout for reconnected client
          newClientInfo.keyExchangeTimer = setTimeout(() => {
            if (!newClientInfo.keyExchangeComplete) {
              console.error("[DEBUG] Key exchange timeout on reconnect — closing connection");
              ws.close(4001, "Key exchange timeout");
            }
          }, KEY_EXCHANGE_TIMEOUT_MS);

          ws.send(
            JSON.stringify({
              type: "key-exchange",
              publicKey: newClientInfo.crypto.getPublicKeyBase64(),
            }),
          );
          console.log("[DEBUG] Sent new key-exchange for reconnect");
          return;
        }

        if (data.type === "disconnect") {
          console.log("[DEBUG] Client sent disconnect message:", data.reason);
          mainWindow?.webContents.send("ws-disconnect", {
            reason: data.reason || "Mobile client disconnected",
          });
          cleanupFileReassembly(clientInfo);
          connectedClients.delete(clientInfo);
          ws.close();
          return;
        }

        // --- Encrypted message handling ---
        if (data.type === "encrypted") {
          if (!clientInfo.keyExchangeComplete) {
            console.error("[DEBUG] Received encrypted message before key exchange — dropping");
            return;
          }

          const decrypted = clientInfo.crypto.decrypt({
            nonce: data.nonce,
            payload: data.payload,
            tag: data.tag,
          });

          if (!decrypted) {
            console.error("[DEBUG] Decryption failed — dropping message");
            return;
          }

          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const inner = decrypted as any;
          console.log("[DEBUG] Decrypted inner message type:", inner.type);

          // Process the decrypted inner message
          processDecryptedMessage(clientInfo, inner);
          return;
        }

        // Any other plaintext message (legacy fallback for pre-key-exchange)
        console.log("[DEBUG] Processing plaintext message:", data.type);
        processDecryptedMessage(clientInfo, data);
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

      // Clean up timers
      if (clientInfo.keyExchangeTimer) {
        clearTimeout(clientInfo.keyExchangeTimer);
      }
      cleanupFileReassembly(clientInfo);
      connectedClients.delete(clientInfo);

      const isAbnormalClosure = code === 1006;
      const isIntentionalDisconnect = code === 1000 || code === 1001;

      if (!isAbnormalClosure) {
        mainWindow?.webContents.send("ws-disconnect", {
          reason: isIntentionalDisconnect
            ? "Connection closed"
            : `Connection lost (code: ${code})`,
          deviceId: clientInfo.deviceId,
        });
      } else {
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
      if (clientInfo.keyExchangeTimer) {
        clearTimeout(clientInfo.keyExchangeTimer);
      }
      cleanupFileReassembly(clientInfo);
      connectedClients.delete(clientInfo);
    });
  });

  console.log(
    `[DEBUG] WebSocket Server initialized on ws://${getLocalIp()}:${WS_PORT}`,
  );
  console.log("=== END SERVER STARTUP ===");
}

/**
 * Process a decrypted (or plaintext legacy) message from a mobile client.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function processDecryptedMessage(clientInfo: ClientInfo, data: any) {
  const msgType = data.type;

  switch (msgType) {
    case "clipboard": {
      clipboard.writeText(data.content);
      lastClipboardText = data.content;
      console.log("[DEBUG] Received clipboard from mobile (encrypted)");
      const { Notification } = require("electron");
      if (Notification.isSupported()) {
        new Notification({
          title: "Fast Share - Clipboard Sync",
          body:
            data.content.length > 100
              ? data.content.substring(0, 100) + "..."
              : data.content,
          silent: false,
        }).show();
      }
      mainWindow?.webContents.send("ws-message", data);
      break;
    }

    case "text": {
      mainWindow?.webContents.send("ws-message", data);
      break;
    }

    case "file-start": {
      // Incoming file transfer over encrypted WS
      console.log(
        `[DEBUG] File transfer starting: ${data.filename} (${data.fileSize} bytes)`,
      );
      // Clean up any previous partial file
      cleanupFileReassembly(clientInfo);

      clientInfo.incomingFile = {
        filename: data.filename,
        fileSize: data.fileSize,
        mimeType: data.mimeType || "application/octet-stream",
        chunks: [],
        receivedBytes: 0,
        timer: setTimeout(() => {
          console.error(
            `[DEBUG] File chunk reassembly timeout for ${clientInfo.incomingFile?.filename}`,
          );
          cleanupFileReassembly(clientInfo);
        }, CHUNK_REASSEMBLY_TIMEOUT_MS),
      };
      break;
    }

    case "file-chunk": {
      if (!clientInfo.incomingFile) {
        console.error("[DEBUG] Received file-chunk without file-start — dropping");
        return;
      }
      const chunkData = Buffer.from(data.data, "base64");
      clientInfo.incomingFile.chunks.push(chunkData);
      clientInfo.incomingFile.receivedBytes += chunkData.length;

      // Reset the reassembly timer on each chunk
      clearTimeout(clientInfo.incomingFile.timer);
      clientInfo.incomingFile.timer = setTimeout(() => {
        console.error(
          `[DEBUG] File chunk reassembly timeout for ${clientInfo.incomingFile?.filename}`,
        );
        cleanupFileReassembly(clientInfo);
      }, CHUNK_REASSEMBLY_TIMEOUT_MS);
      break;
    }

    case "file-end": {
      if (!clientInfo.incomingFile) {
        console.error("[DEBUG] Received file-end without file-start — ignoring");
        return;
      }

      const fileTransfer = clientInfo.incomingFile;
      clearTimeout(fileTransfer.timer);

      // Verify checksum
      const assembled = Buffer.concat(fileTransfer.chunks);
      const checksum = CryptoManager.sha256(assembled);

      if (checksum !== data.checksum) {
        console.error(
          `[DEBUG] File checksum mismatch for ${fileTransfer.filename}: expected ${data.checksum}, got ${checksum}`,
        );
        clientInfo.incomingFile = undefined;
        return;
      }

      // Save file to shared directory
      const sharedDir = path.join(os.homedir(), "FastShare");
      const savePath = path.join(sharedDir, fileTransfer.filename);
      fs.writeFileSync(savePath, assembled);

      console.log(`[DEBUG] File received via encrypted WS: ${savePath}`);

      // Notify renderer
      mainWindow?.webContents.send("file-received", {
        filename: fileTransfer.filename,
        path: savePath,
      });

      clientInfo.incomingFile = undefined;
      break;
    }

    // Legacy file/image messages (HTTP-based)
    case "file":
    case "image": {
      mainWindow?.webContents.send("ws-message", data);
      break;
    }

    default: {
      // Forward everything else to renderer
      mainWindow?.webContents.send("ws-message", data);
      break;
    }
  }
}

// --- IPC Handlers ---
function setupIpc() {
  // AI Settings handlers
  ipcMain.handle("get-ai-settings", () => {
    const apiKeyEncrypted = aiSettingsStore.get("apiKeyEncrypted") as string;
    const provider = aiSettingsStore.get("provider") as string;
    const model = aiSettingsStore.get("model") as string;

    let apiKey: string | null = null;
    if (apiKeyEncrypted) {
      apiKey = "••••••••"; // masked
    }

    return { apiKey, provider, model };
  });

  ipcMain.handle("save-ai-settings", (_event, settings: { apiKey?: string; provider?: string; model?: string }) => {
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

  ipcMain.handle("fetch-models", async () => {
    try {
      // Decrypt API key if available
      const apiKeyEncrypted = aiSettingsStore.get("apiKeyEncrypted") as string;
      let apiKey = "";
      if (apiKeyEncrypted) {
        if (safeStorage.isEncryptionAvailable()) {
          try {
            apiKey = safeStorage.decryptString(Buffer.from(apiKeyEncrypted, "base64"));
          } catch {
            // Fallback: might be stored as plaintext
            apiKey = apiKeyEncrypted;
          }
        } else {
          apiKey = apiKeyEncrypted;
        }
      }

      const headers: Record<string, string> = {
        "Content-Type": "application/json",
      };
      if (apiKey) {
        headers["Authorization"] = `Bearer ${apiKey}`;
      }

      const response = await fetch("https://openrouter.ai/api/v1/models", {
        method: "GET",
        headers,
      });

      if (!response.ok) {
        return { error: `Failed to fetch models (HTTP ${response.status})` };
      }

      const data = await response.json();
      const models = (data.data || []).map(
        (m: { id: string; name?: string; input_modalities?: string[]; supported_parameters?: string[] }) => ({
          id: m.id,
          name: m.name || m.id,
          vision: !!(
            (m.input_modalities && (
              m.input_modalities.includes("image") ||
              m.input_modalities.includes("image/png")
            )) ||
            (m.supported_parameters && Array.isArray(m.supported_parameters) &&
              m.supported_parameters.some((p: string) => p.includes("vision") || p.includes("image")))
          ),
        })
      );

      return models;
    } catch (error) {
      console.error("[AI Settings] Failed to fetch models:", error);
      return { error: "Failed to fetch models from OpenRouter" };
    }
  });

  // --- Summarize IPC handlers ---
  ipcMain.handle("summarize-content", async (_event, data: { type: string; content: string; filename?: string; filePath?: string }) => {
    try {
      // Decrypt API key
      const apiKeyEncrypted = aiSettingsStore.get("apiKeyEncrypted") as string;
      let apiKey = "";
      if (apiKeyEncrypted) {
        if (safeStorage.isEncryptionAvailable()) {
          try {
            apiKey = safeStorage.decryptString(Buffer.from(apiKeyEncrypted, "base64"));
          } catch {
            apiKey = apiKeyEncrypted;
          }
        } else {
          apiKey = apiKeyEncrypted;
        }
      }

      if (!apiKey) {
        return { error: "no-api-key" };
      }

      const model = (aiSettingsStore.get("model") as string) || "openrouter/auto";

      // Prepare content — text or multimodal
      let textContent: string | null = null;
      let imageContent: { type: string; image_url: { url: string } } | null = null;

      if (data.type === "text") {
        textContent = data.content;
      } else {
        // File type — check extension
        const filename = data.filename || "";
        const ext = path.extname(filename).toLowerCase();
        const isImage = IMAGE_EXTENSIONS.has(ext);

        if (!SUMMARIZABLE_EXTENSIONS.has(ext) && !isImage) {
          return { error: "unsupported-type" };
        }

        // Resolve file path: prefer filePath from renderer, else ~/FastShare/<filename>
        const filePath = data.filePath || path.join(os.homedir(), "FastShare", filename);
        if (!fs.existsSync(filePath)) {
          return { error: "File not found: " + filename };
        }

        if (ext === ".pdf") {
          try {
            const fileBuffer = fs.readFileSync(filePath);
            const pdfData = await pdfParse(fileBuffer);
            let extracted = pdfData.text || "";
            const MAX_BYTES = 100 * 1024;
            if (Buffer.byteLength(extracted, "utf-8") > MAX_BYTES) {
              extracted = extracted.substring(0, MAX_BYTES) + "\n\n[Content truncated, showing first 100KB]";
            }
            textContent = extracted;
          } catch {
            return { error: "Could not extract text from PDF" };
          }
        } else if (ext === ".docx") {
          try {
            const result = await mammoth.extractRawText({ path: filePath });
            let extracted = result.value || "";
            const MAX_BYTES = 100 * 1024;
            if (Buffer.byteLength(extracted, "utf-8") > MAX_BYTES) {
              extracted = extracted.substring(0, MAX_BYTES) + "\n\n[Content truncated, showing first 100KB]";
            }
            textContent = extracted;
          } catch {
            return { error: "Could not extract text from DOCX" };
          }
        } else if (isImage) {
          // Check if model supports vision
          try {
            const headers: Record<string, string> = { "Content-Type": "application/json" };
            if (apiKey) headers["Authorization"] = `Bearer ${apiKey}`;
            const modelsResp = await fetch("https://openrouter.ai/api/v1/models", { headers });
            if (modelsResp.ok) {
              const modelsData = await modelsResp.json();
              const modelObj = (modelsData.data || []).find(
                (m: { id: string }) => m.id === model
              );
              if (modelObj) {
                const modalities: string[] = modelObj.input_modalities || [];
                const hasVision = modalities.includes("image") || modalities.includes("image/png") ||
                  (modelObj.supported_parameters && Array.isArray(modelObj.supported_parameters) &&
                    modelObj.supported_parameters.some((p: string) => p.includes("vision") || p.includes("image")));
                if (!hasVision) {
                  return { error: "model-unsupported" };
                }
              }
              // If model not found in list, allow attempt (e.g. openrouter/auto)
            }
          } catch {
            // If model list fetch fails, allow attempt
          }

          const fileBuffer = fs.readFileSync(filePath);
          const base64Data = fileBuffer.toString("base64");
          const mimeType = getMimeType(filename);
          imageContent = {
            type: "image_url",
            image_url: { url: `data:${mimeType};base64,${base64Data}` },
          };
        } else {
          // Plain text file
          const stat = fs.statSync(filePath);
          let fileContent = fs.readFileSync(filePath, "utf-8");
          const MAX_BYTES = 100 * 1024;
          if (stat.size > MAX_BYTES) {
            fileContent = fileContent.substring(0, MAX_BYTES) + "\n\n[Content truncated, showing first 100KB]";
          }
          textContent = fileContent;
        }
      }

      // Generate stream ID
      const streamId = crypto.randomUUID();
      const abortController = new AbortController();
      activeSummarizeStreams.set(streamId, abortController);

      // Make streaming request to OpenRouter (fire and forget — we handle response async)
      (async () => {
        try {
          const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
            method: "POST",
            headers: {
              "Authorization": `Bearer ${apiKey}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              model,
              messages: [{
                role: "user",
                content: imageContent
                  ? [{ type: "text", text: "Summarize the following image concisely:" }, imageContent]
                  : "Summarize the following content concisely:\n\n" + textContent,
              }],
              stream: true,
            }),
            signal: abortController.signal,
          });

          if (!response.ok) {
            const errText = await response.text();
            mainWindow?.webContents.send("summarize-error", { streamId, error: `API error (${response.status}): ${errText}` });
            activeSummarizeStreams.delete(streamId);
            return;
          }

          const reader = response.body?.getReader();
          if (!reader) {
            mainWindow?.webContents.send("summarize-error", { streamId, error: "No response body" });
            activeSummarizeStreams.delete(streamId);
            return;
          }

          const decoder = new TextDecoder();
          let buffer = "";

          while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            buffer += decoder.decode(value, { stream: true });
            const lines = buffer.split("\n");
            buffer = lines.pop() || ""; // keep incomplete line

            for (const line of lines) {
              const trimmed = line.trim();
              if (!trimmed || !trimmed.startsWith("data: ")) continue;

              const jsonStr = trimmed.slice(6);
              if (jsonStr === "[DONE]") {
                mainWindow?.webContents.send("summarize-done", { streamId });
                activeSummarizeStreams.delete(streamId);
                return;
              }

              try {
                const parsed = JSON.parse(jsonStr);
                const text = parsed.choices?.[0]?.delta?.content;
                if (text) {
                  mainWindow?.webContents.send("summarize-chunk", { streamId, text });
                }
              } catch {
                // Skip malformed JSON lines
              }
            }
          }

          // Stream ended without [DONE]
          mainWindow?.webContents.send("summarize-done", { streamId });
          activeSummarizeStreams.delete(streamId);
        } catch (err: unknown) {
          if ((err as Error).name === "AbortError") {
            // Cancelled — clean up silently
          } else {
            mainWindow?.webContents.send("summarize-error", { streamId, error: `Network error: ${(err as Error).message}` });
          }
          activeSummarizeStreams.delete(streamId);
        }
      })();

      return { streamId };
    } catch (error) {
      console.error("[Summarize] Error:", error);
      return { error: `Failed to start summarization: ${(error as Error).message}` };
    }
  });

  ipcMain.on("summarize-cancel", (_event, streamId: string) => {
    const controller = activeSummarizeStreams.get(streamId);
    if (controller) {
      controller.abort();
      activeSummarizeStreams.delete(streamId);
    }
  });

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

  ipcMain.on("open-path", async (event, filePath: string) => {
    try {
      await shell.openPath(filePath);
    } catch (error) {
      console.error("[DEBUG] Failed to open file:", error);
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

  ipcMain.on("disconnect-client", () => {
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
    connectedClients.forEach((client) => {
      cleanupFileReassembly(client);
      if (client.keyExchangeTimer) {
        clearTimeout(client.keyExchangeTimer);
      }
    });
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
        sendFileEncrypted(client, destPath, fileName, messageType);
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
}

/**
 * Send a file via encrypted chunked WebSocket transfer.
 */
function sendFileEncrypted(
  client: ClientInfo,
  filePath: string,
  fileName: string,
  messageType: string,
) {
  try {
    const fileBuffer = fs.readFileSync(filePath);
    const fileSize = fileBuffer.length;
    const mimeType = getMimeType(fileName);
    const checksum = CryptoManager.sha256(fileBuffer);

    // Send file-start
    sendEncrypted(client, {
      type: "file-start",
      filename: fileName,
      fileSize,
      mimeType,
    });

    // Send file-chunks
    let offset = 0;
    let seq = 0;
    while (offset < fileSize) {
      const end = Math.min(offset + FILE_CHUNK_SIZE, fileSize);
      const chunk = fileBuffer.subarray(offset, end);
      sendEncrypted(client, {
        type: "file-chunk",
        seq,
        data: chunk.toString("base64"),
      });
      offset = end;
      seq++;
    }

    // Send file-end
    sendEncrypted(client, {
      type: "file-end",
      filename: fileName,
      checksum,
    });

    console.log(
      `[DEBUG] File sent via encrypted WS: ${fileName} (${fileSize} bytes, ${seq} chunks)`,
    );
  } catch (error) {
    console.error(`[DEBUG] Failed to send file via encrypted WS: ${error}`);
  }
}

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

// --- Electron Window ---
function createWindow() {
  mainWindow = new BrowserWindow({
    width: 900,
    height: 600,
    frame: false,
    transparent: false,
    backgroundColor: "#242424",
    resizable: true,
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
