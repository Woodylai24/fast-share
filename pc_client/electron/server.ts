import path from "path";
import fs from "fs";
import os from "os";
import ip from "ip";
import express from "express";
import cors from "cors";
import http from "http";
import { WebSocketServer, WebSocket } from "ws";
import { CryptoManager, isUnencryptedType } from "./crypto";
import { processFileMessage, cleanupFileReassembly, FILE_CHUNK_SIZE } from "./file-transfer";
import { startClipboardSync } from "./clipboard-sync";
import settingsStore from "./settings-store";
import { pairDevice, updateDeviceLastSeen } from "./settings-store";

// --- Configuration ---
const WS_PORT = 8080;
const HTTP_PORT = 8081;
const KEY_EXCHANGE_TIMEOUT_MS = 5000; // 5 seconds
const PING_INTERVAL = 30_000; // 30 seconds
const PONG_TIMEOUT = 10_000; // 10 seconds to respond

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
function startServers(options: { getMainWindow: GetMainWindowFn }) {
  const { getMainWindow } = options;
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
      getMainWindow()?.webContents.send("file-received", {
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
      "DEBUG] HTTP Server listening on ALL interfaces (0.0.0.0):" + HTTP_PORT,
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

            // Update pairing info (FCM token may have rotated)
            pairDevice(data.deviceId, {
              fcmToken: data.fcmToken,
              name: data.device || 'Unknown',
            });
          }
          // Re-do key exchange on reconnect — send new public key
          const newClientInfo: ClientInfo = {
            ws,
            deviceId: clientInfo.deviceId,
            crypto: new CryptoManager(),
            keyExchangeComplete: false,
            pongPending: false,
          };
          // Replace the client info in the set
          // Clear the original key exchange timer — it was set on initial connection
          // and will fire after 5s, killing this WebSocket before reconnect completes
          if (clientInfo.keyExchangeTimer) {
            clearTimeout(clientInfo.keyExchangeTimer);
            clientInfo.keyExchangeTimer = undefined;
          }
          stopHeartbeat(clientInfo);
          connectedClients.delete(clientInfo);
          connectedClients.add(newClientInfo);

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

        if (data.type === "pong") {
          clientInfo.pongPending = false;
          if (clientInfo.pongTimeout) {
            clearTimeout(clientInfo.pongTimeout);
            clientInfo.pongTimeout = undefined;
          }
          return;
        }

        if (data.type === "disconnect") {
          console.log("[DEBUG] Client sent disconnect message:", data.reason);
          stopHeartbeat(clientInfo);
          getMainWindow()?.webContents.send("ws-disconnect", {
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
      cleanupFileReassembly(clientInfo);
      connectedClients.delete(clientInfo);

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
      cleanupFileReassembly(clientInfo);
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
  wss,
  WS_PORT,
  HTTP_PORT,
  FILE_CHUNK_SIZE,
};
