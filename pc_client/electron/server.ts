import path from "path";
import fs from "fs";
import os from "os";
import ip from "ip";
import express from "express";
import cors from "cors";
import http from "http";
import net from "net";
import { WebSocketServer, WebSocket } from "ws";
import { CryptoManager, isUnencryptedType } from "./crypto";
import { processFileMessage } from "./file-transfer";
import { startClipboardSync } from "./clipboard-sync";
import settingsStore from "./settings-store";
import { pairDevice, updateDeviceLastSeen, removePairedDevice } from "./settings-store";

// --- Configuration ---
let WS_PORT = 8080;
let HTTP_PORT = 8081;
const KEY_EXCHANGE_TIMEOUT_MS = 5000; // 5 seconds
const PING_INTERVAL = 30_000; // 30 seconds
const PONG_TIMEOUT = 10_000; // 10 seconds to respond
const ACK_TIMEOUT_MS = 15_000; // 15 seconds for text messages
export const FILE_ACK_TIMEOUT_MS = 120_000; // 120 seconds for file transfers

// --- Client Tracking ---
interface ClientInfo {
  ws: WebSocket;
  deviceId?: string;
  crypto: CryptoManager;
  keyExchangeComplete: boolean;
  keyExchangeTimer?: ReturnType<typeof setTimeout>;
  // Heartbeat state
  pongPending: boolean;
  pingTimer?: ReturnType<typeof setInterval>;
  pongTimeout?: ReturnType<typeof setTimeout>;
  // File chunk reassembly state
  incomingFile?: {
    filename: string;
    fileSize: number;
    mimeType: string;
    chunks: Buffer[];
    receivedBytes: number;
    lastNotifiedPct: number;
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
  // For file retransfer: the local path on the PC. When present, the flush
  // logic encrypts the file once and serves it via an HTTP download URL
  // instead of sending the queued data directly (mobile can't reach the
  // stale URL reference that was queued).
  filePath?: string;
  messageType?: string;
}

// Map of device ID -> array of queued messages
const messageQueue: Map<string, QueuedMessage[]> = new Map();

let wss: WebSocketServer | null = null;
let httpServer: http.Server | null = null;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type GetMainWindowFn = () => any;

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

function findAvailablePort(startPort: number, maxAttempts = 10): Promise<number> {
  return new Promise((resolve, reject) => {
    let port = startPort;
    let attempts = 0;

    const tryPort = () => {
      const tester = net.createServer();
      tester.once("error", (err: NodeJS.ErrnoException) => {
        if (err.code === "EADDRINUSE") {
          attempts++;
          if (attempts >= maxAttempts) {
            reject(
              new Error(
                `No available port found after ${maxAttempts} attempts (starting from ${startPort})`,
              ),
            );
          } else {
            port++;
            tryPort();
          }
        } else {
          reject(err);
        }
      });
      tester.once("listening", () => {
        tester.close(() => resolve(port));
      });
      tester.listen(port);
    };

    tryPort();
  });
}

// --- Message Queuing Functions ---
function queueMessage(
  deviceId: string,
  type: string,
  data: QueuedMessage["data"],
  filePath?: string,
  messageType?: string,
) {
  if (!messageQueue.has(deviceId)) {
    messageQueue.set(deviceId, []);
  }
  const queue = messageQueue.get(deviceId);
  if (queue) {
    queue.push({ type, data, timestamp: Date.now(), filePath, messageType });
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

// --- Message ACK Tracking ---
// When a message is sent over WebSocket, we track it here. If no ACK
// arrives within ACK_TIMEOUT_MS, the message is queued + pushed via FCM.
interface PendingAck {
  timer: ReturnType<typeof setTimeout>;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  message: any;
  deviceId: string;
  // For file transfers: the local file path so ACK timeout can queue
  // a proper chunked retransfer instead of a URL reference.
  filePath?: string;
  messageType?: string;
}

const pendingAcks: Map<string, PendingAck> = new Map();
const MAX_RECENT_IDS = 200;
const recentMessageIds: Set<string> = new Set();

// Token-based encrypted file transfer registry.
// PC→Mobile: token → { encryptedPath, cleanup() }
// Mobile→PC: token → { key, nonce, tag, filename, fileSize, mimeType, messageId, savePath, deviceId, uploaded, decrypted }
const fileTransferRegistry = new Map<string, Record<string, unknown>>();

function generateMessageId(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 11)}`;
}

type GetMainWindowFnForAck = () => { webContents: { send: (channel: string, ...args: unknown[]) => void } } | null;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function trackPendingAck(messageId: string, message: any, deviceId: string, getMainWindow?: GetMainWindowFnForAck, filePath?: string, messageType?: string, timeoutMs?: number) {
  // Clear any existing entry for this messageId (shouldn't happen normally)
  clearPendingAck(messageId);

  const timer = setTimeout(() => {
    handleAckTimeout(messageId, getMainWindow);
  }, timeoutMs ?? ACK_TIMEOUT_MS);

  pendingAcks.set(messageId, { timer, message, deviceId, filePath, messageType });
}

function clearPendingAck(messageId: string) {
  const entry = pendingAcks.get(messageId);
  if (entry) {
    clearTimeout(entry.timer);
    pendingAcks.delete(messageId);
  }
}

function handleAckTimeout(messageId: string, getMainWindow?: GetMainWindowFnForAck) {
  const entry = pendingAcks.get(messageId);
  if (!entry) return; // Already cleared (ACK received)

  pendingAcks.delete(messageId);
  const { message, deviceId } = entry;
  console.log(`[DEBUG] ACK timeout for message ${messageId} — queuing + pushing`);

  // Queue for next reconnect
  queueMessage(deviceId, message.type || "text", message, entry.filePath, entry.messageType);

  // Send FCM push notification
  const { sendPushNotification } = require("./firebase");
  const text = typeof message.content === "string" ? message.content : "New message";
  sendPushNotification(deviceId, {
    title: "New Message",
    body: text.length > 50 ? text.substring(0, 50) + "..." : text,
    data: { type: message.type || "text" },
  }).catch((err: unknown) => console.error("[DEBUG] Push notification failed:", err));

  // Notify renderer — message stays at 'sent' (queued, will deliver on reconnect)
  // The UI already shows 'sent', no status change needed
  void getMainWindow;
}

function addRecentMessageId(messageId: string) {
  if (recentMessageIds.size >= MAX_RECENT_IDS) {
    // Remove oldest entry (Sets iterate in insertion order)
    const oldest = recentMessageIds.values().next().value;
    if (oldest) recentMessageIds.delete(oldest);
  }
  recentMessageIds.add(messageId);
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

// --- Heartbeat (ping/pong) ---
function startHeartbeat(client: ClientInfo) {
  if (client.pingTimer) return; // already running

  client.pingTimer = setInterval(() => {
    if (client.ws.readyState !== WebSocket.OPEN) return;

    client.ws.send(JSON.stringify({ type: "ping" }));
    client.pongPending = true;

    // Clear any previous pong timeout
    if (client.pongTimeout) {
      clearTimeout(client.pongTimeout);
    }

    client.pongTimeout = setTimeout(() => {
      if (client.pongPending) {
        console.error("[DEBUG] Heartbeat timeout — terminating connection");
        client.ws.terminate();
      }
    }, PONG_TIMEOUT);
  }, PING_INTERVAL);
}

function stopHeartbeat(client: ClientInfo) {
  if (client.pingTimer) {
    clearInterval(client.pingTimer);
    client.pingTimer = undefined;
  }
  if (client.pongTimeout) {
    clearTimeout(client.pongTimeout);
    client.pongTimeout = undefined;
  }
}

// --- Server Setup ---
async function startServers(options: { getMainWindow: GetMainWindowFn }) {
  const { getMainWindow } = options;
  WS_PORT = await findAvailablePort(8080);
  HTTP_PORT = await findAvailablePort(WS_PORT + 1);
  console.log(`[DEBUG] Using WebSocket port: ${WS_PORT}, HTTP port: ${HTTP_PORT}`);
  const allIps = getLocalIps();
  console.log("=== SERVER STARTUP DIAGNOSTICS ===");
  console.log("[DEBUG] Available network interfaces:", allIps);
  console.log("[DEBUG] WebSocket Port:", WS_PORT);
  console.log("[DEBUG] HTTP Port:", HTTP_PORT);

  // Start clipboard sync with send function callback
  startClipboardSync((message: object) => sendEncryptedToClients(message));

  // 1. HTTP Server (fallback for file transfer)
  const expressApp = express();
  expressApp.use(cors());
  expressApp.use(express.json());

  const sharedDir = path.join(os.homedir(), "FastShare");
  if (!fs.existsSync(sharedDir)) fs.mkdirSync(sharedDir, { recursive: true });
  console.log("[DEBUG] Shared directory:", sharedDir);

  // --- PC→Mobile: serve encrypted file blob by token ---
  expressApp.get("/encrypted-file/:token", (req, res) => {
    const token = req.params.token;
    const entry = fileTransferRegistry.get(token);
    if (!entry || !entry.encryptedPath) {
      return res.status(404).send("File not found or expired");
    }
    const encPath = entry.encryptedPath as string;
    if (!fs.existsSync(encPath)) {
      fileTransferRegistry.delete(token);
      return res.status(404).send("File not found");
    }
    res.sendFile(encPath);
  });

  // --- Mobile→PC: receive encrypted file blob by token ---
  expressApp.post("/encrypted-upload/:token", (req, res) => {
    const token = req.params.token;
    const entry = fileTransferRegistry.get(token);
    if (!entry || !entry.savePath) {
      return res.status(404).send("Invalid or expired upload token");
    }

    const savePath = entry.savePath as string;
    const fileStream = fs.createWriteStream(savePath);
    req.pipe(fileStream);

    fileStream.on("finish", () => {
      console.log(`[DEBUG] Encrypted upload saved to ${savePath}`);
      entry.uploaded = true;
      tryDecryptUpload(token, getMainWindow);
      res.status(200).send("Upload complete");
    });

    fileStream.on("error", (err) => {
      console.error("[DEBUG] Upload write error:", err);
      res.status(500).send("Write error");
    });
  });

  // Endpoint to serve files to Mobile (legacy HTTP fallback)
  expressApp.use("/files", express.static(sharedDir));

  httpServer = expressApp.listen(HTTP_PORT, "0.0.0.0", () => {
    console.log(
      `[DEBUG] HTTP Server running on http://${getLocalIp()}:${HTTP_PORT}`,
    );
    console.log(
      "DEBUG] HTTP Server listening on ALL interfaces (0.0.0.0):" + HTTP_PORT,
    );
  });
  console.log("[DEBUG] HTTP Server address:", httpServer.address());

  function tryDecryptUpload(token: string, getMainWindowFn: GetMainWindowFn) {
    const entry = fileTransferRegistry.get(token);
    if (!entry || !entry.uploaded || entry.decrypted) return;

    const key = entry.key as Buffer;
    const nonce = entry.nonce as Buffer;
    const tag = entry.tag as Buffer;
    const filename = entry.filename as string;
    const savePath = entry.savePath as string;
    const messageId = entry.messageId as string;
    const deviceId = entry.deviceId as string;

    const encryptedData = fs.readFileSync(savePath);
    const decrypted = CryptoManager.decryptFile(encryptedData, key, nonce, tag);
    if (!decrypted) {
      console.error("[DEBUG] File decryption failed for upload:", filename);
      getMainWindowFn()?.webContents.send("file-received", { filename, path: "", failed: true });
      fileTransferRegistry.delete(token);
      try { fs.unlinkSync(savePath); } catch { /* ignore */ }
      return;
    }

    // Overwrite temp encrypted file with decrypted content
    fs.writeFileSync(savePath, decrypted);
    entry.decrypted = true;
    console.log(`[DEBUG] File decrypted and saved: ${savePath}`);

    getMainWindowFn()?.webContents.send("file-received", { filename, path: savePath });

    // Send ACK to mobile — file fully received
    if (messageId) {
      const client = Array.from(connectedClients).find(c => c.deviceId === deviceId);
      if (client && client.ws.readyState === WebSocket.OPEN) {
        client.ws.send(JSON.stringify({ type: "message-ack", messageId }));
        console.log("[DEBUG] Sent ACK for uploaded file:", messageId);
      }
    }

    fileTransferRegistry.delete(token);
  }

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
      pongPending: false,
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

            settingsStore.set('lastConnectedDevice', data.deviceId || 'Unknown');
            settingsStore.set('lastConnectedAt', new Date().toISOString());

            // Persist device pairing (with FCM token if provided)
            pairDevice(data.deviceId, {
              fcmToken: data.fcmToken,
              name: data.device || 'Unknown',
            });

            // Queued messages are flushed after key exchange completes
            // (see key-exchange handler below)
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
          getMainWindow()?.webContents.send("ws-message", {
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
            // Start heartbeat now that the connection is fully established
            startHeartbeat(clientInfo);

            // Flush queued messages now that encryption is established.
            // Previously these were sent as plaintext during handshake/reconnect
            // (before key exchange), which meant mobile couldn't decrypt them.
            // Now they're sent encrypted + tracked with ACKs.
            if (clientInfo.deviceId) {
              const queuedMessages = getQueuedMessages(clientInfo.deviceId);
              if (queuedMessages.length > 0) {
                console.log(
                  "[DEBUG] Sending",
                  queuedMessages.length,
                  "queued messages after key exchange",
                );
                queuedMessages.forEach((msg) => {
                  if (msg.filePath) {
                    const cryptoModule = require("crypto");
                    const fileBuffer = fs.readFileSync(msg.filePath);
                    const { encrypted, key: encKey, nonce: encNonce, tag: encTag } = CryptoManager.encryptFile(fileBuffer);
                    const downloadToken = cryptoModule.randomBytes(16).toString("hex");
                    const tempDir = path.join(os.tmpdir(), "fastshare");
                    if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });
                    const encryptedPath = path.join(tempDir, `${downloadToken}.enc`);
                    fs.writeFileSync(encryptedPath, encrypted);
                    fileTransferRegistry.set(downloadToken, {
                      encryptedPath,
                      cleanup: () => { try { fs.unlinkSync(encryptedPath); } catch { /* ignore */ } },
                    });
                    const downloadUrl = `http://${getLocalIp()}:${HTTP_PORT}/encrypted-file/${downloadToken}`;
                    const fileName = path.basename(msg.filePath);
                    const msgId = msg.data?.messageId;
                    sendEncrypted(clientInfo, {
                      type: "file-start",
                      filename: fileName,
                      fileSize: fileBuffer.length,
                      mimeType: msg.messageType || "application/octet-stream",
                      downloadUrl,
                      key: encKey.toString("base64"),
                      nonce: encNonce.toString("base64"),
                      tag: encTag.toString("base64"),
                      messageId: msgId,
                    });
                    if (msgId) {
                      trackPendingAck(msgId, msg.data, clientInfo.deviceId!, getMainWindow, msg.filePath, msg.messageType, FILE_ACK_TIMEOUT_MS);
                    }
                  } else {
                    sendEncrypted(clientInfo, msg.data);
                    if (msg.data?.messageId) {
                      trackPendingAck(msg.data.messageId, msg.data, clientInfo.deviceId!, getMainWindow);
                    }
                  }
                });
              }
            }
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

            // Update pairing info — only refresh FCM token, don't overwrite name.
            // The name is set during initial handshake. Reconnect doesn't send it,
            // so data.device is undefined and would overwrite the stored name with
            // 'Unknown'.
            pairDevice(data.deviceId, {
              fcmToken: data.fcmToken,
              name: data.device,  // undefined → pairDevice keeps existing name
            });
          }
          // Reset clientInfo in-place for reconnect.
          // We must NOT create a new object — the ws.on('message') closure
          // captures the original clientInfo reference. If we swap it out,
          // the key-exchange response from mobile updates the OLD object,
          // and the new object's keyExchangeTimer fires after 5s killing the socket.
          stopHeartbeat(clientInfo);
          if (clientInfo.keyExchangeTimer) {
            clearTimeout(clientInfo.keyExchangeTimer);
            clientInfo.keyExchangeTimer = undefined;
          }
          clientInfo.crypto = new CryptoManager();
          clientInfo.keyExchangeComplete = false;
          clientInfo.pongPending = false;

          // Save last-connected info for reconnect
          if (data.deviceId) {
            settingsStore.set('lastConnectedDevice', data.deviceId || 'Unknown');
            settingsStore.set('lastConnectedAt', new Date().toISOString());
          }

          // Send handshake confirmation for reconnect
          ws.send(
            JSON.stringify({
              type: "handshake",
              message: "Reconnected to PC",
            }),
          );

          // Notify renderer that mobile has reconnected
          getMainWindow()?.webContents.send("ws-message", {
            type: "handshake",
            message: "Mobile Reconnected",
          });

          // Set key exchange timeout for reconnected client
          clientInfo.keyExchangeTimer = setTimeout(() => {
            if (!clientInfo.keyExchangeComplete) {
              console.error("[DEBUG] Key exchange timeout on reconnect — closing connection");
              ws.close(4001, "Key exchange timeout");
            }
          }, KEY_EXCHANGE_TIMEOUT_MS);

          ws.send(
            JSON.stringify({
              type: "key-exchange",
              publicKey: clientInfo.crypto.getPublicKeyBase64(),
            }),
          );
          console.log("[DEBUG] Sent new key-exchange for reconnect");
          return;
        }

        // --- Unencrypted: message-ack (delivery confirmation) ---
        if (data.type === "message-ack") {
          console.log("[DEBUG] Received ACK for message:", data.messageId);
          clearPendingAck(data.messageId);
          getMainWindow()?.webContents.send("delivery-status", {
            messageId: data.messageId,
            status: "delivered",
          });
          return;
        }

        if (data.type === "pong") {
          clientInfo.pongPending = false;
          if (clientInfo.pongTimeout) {
            clearTimeout(clientInfo.pongTimeout);
            clientInfo.pongTimeout = undefined;
          }
          return;
        }

        if (data.type === "unpair") {
          console.log("[DEBUG] Client unpairing:", data.deviceId);
          if (data.deviceId) {
            removePairedDevice(data.deviceId);
          }
          stopHeartbeat(clientInfo);
          connectedClients.delete(clientInfo);
          // Notify renderer — device was explicitly unpaired
          getMainWindow()?.webContents.send("ws-message", {
            type: "unpaired",
            deviceId: data.deviceId,
          });
          ws.close();
          return;
        }

        if (data.type === "disconnect") {
          console.log("[DEBUG] Client sent disconnect message:", data.reason);
          stopHeartbeat(clientInfo);
          getMainWindow()?.webContents.send("ws-disconnect", {
            reason: data.reason || "Mobile client disconnected",
          });
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

          // Handle file upload signaling BEFORE ACK — ACK is delayed until file is decrypted
          if (inner.type === "file-upload-request") {
            const cryptoModule = require("crypto");
            const uploadToken = cryptoModule.randomBytes(16).toString("hex");
            const { filename, fileSize, mimeType, key, nonce, tag, messageId } = inner;

            const sharedDir = path.join(os.homedir(), "FastShare");
            if (!fs.existsSync(sharedDir)) fs.mkdirSync(sharedDir, { recursive: true });
            const savePath = path.join(sharedDir, filename);

            fileTransferRegistry.set(uploadToken, {
              key: Buffer.from(key, "base64"),
              nonce: Buffer.from(nonce, "base64"),
              tag: Buffer.from(tag, "base64"),
              filename, fileSize, mimeType, messageId,
              savePath, uploaded: false, decrypted: false,
              deviceId: clientInfo.deviceId,
            });

            // Notify renderer
            getMainWindow()?.webContents.send("file-received-start", { filename, fileSize, mimeType });

            // Tell mobile to start uploading
            sendEncrypted(clientInfo, {
              type: "file-upload-ready",
              requestId: messageId,
              uploadUrl: `http://${getLocalIp()}:${HTTP_PORT}/encrypted-upload/${uploadToken}`,
            });
            console.log("[DEBUG] File upload request from mobile:", filename);
            return;
          }

          // Normal ACK + dedup for all other messages
          if (inner.messageId) {
            if (ws.readyState === WebSocket.OPEN) {
              ws.send(JSON.stringify({ type: "message-ack", messageId: inner.messageId }));
            }
            if (recentMessageIds.has(inner.messageId)) {
              return;
            }
            addRecentMessageId(inner.messageId);
          }

          processFileMessage(clientInfo, inner, getMainWindow);
          return;
        }

        // Any other plaintext message (legacy fallback for pre-key-exchange)
        console.log("[DEBUG] Processing plaintext message:", data.type);
        processFileMessage(clientInfo, data, getMainWindow);
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
      stopHeartbeat(clientInfo);
      if (clientInfo.keyExchangeTimer) {
        clearTimeout(clientInfo.keyExchangeTimer);
      }
      connectedClients.delete(clientInfo);

      // Flush pending ACKs for this device into the offline queue.
      // Without this, messages sent just before disconnect sit in pendingAcks
      // for up to 15s. If the device reconnects within that window, the
      // key-exchange flush only processes messageQueue (not pendingAcks), so
      // those messages are stranded until the NEXT reconnect.
      if (clientInfo.deviceId) {
        const idsToFlush: string[] = [];
        pendingAcks.forEach((entry, msgId) => {
          if (entry.deviceId === clientInfo.deviceId) {
            idsToFlush.push(msgId);
          }
        });
        idsToFlush.forEach((msgId) => {
          const entry = pendingAcks.get(msgId);
          if (!entry) return;
          clearTimeout(entry.timer);
          pendingAcks.delete(msgId);
          queueMessage(
            entry.deviceId,
            entry.message.type || "text",
            entry.message,
            entry.filePath,
            entry.messageType,
          );
          console.log(
            `[DEBUG] Flushed pending ACK ${msgId} to queue on disconnect`,
          );
        });
      }

      // Update lastSeenAt for paired device
      if (clientInfo.deviceId) {
        updateDeviceLastSeen(clientInfo.deviceId);
      }

      // Always notify renderer — no more special casing for 1006
      const isIntentional = code === 1000 || code === 1001 || code === 4000;
      getMainWindow()?.webContents.send("ws-disconnect", {
        reason: code === 4000
          ? "Mobile went to background"
          : isIntentional
            ? "Connection closed"
            : `Connection lost (code: ${code})`,
        deviceId: clientInfo.deviceId,
        code,
      });
    });

    ws.on("error", (error) => {
      console.error("[DEBUG] WebSocket ERROR:", error);
      stopHeartbeat(clientInfo);
      if (clientInfo.keyExchangeTimer) {
        clearTimeout(clientInfo.keyExchangeTimer);
      }
      connectedClients.delete(clientInfo);
    });
  });

  console.log(
    `[DEBUG] WebSocket Server initialized on ws://${getLocalIp()}:${WS_PORT}`,
  );
  console.log("=== END SERVER STARTUP ===");
}

export {
  startServers,
  getLocalIps,
  getLocalIp,
  connectedClients,
  sendEncrypted,
  sendEncryptedToClients,
  broadcastToClients,
  queueMessage,
  stopHeartbeat,
  generateMessageId,
  trackPendingAck,
  clearPendingAck,
  wss,
  WS_PORT,
  HTTP_PORT,
  fileTransferRegistry,
};
