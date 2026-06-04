import { WebSocketServer, WebSocket } from "ws";

const WS_PORT = 8080;

const wss = new WebSocketServer({ port: WS_PORT });

wss.on("listening", () => {
  console.log(`[TEST-SERVER] WebSocket Server is LISTENING on port ${WS_PORT}`);
});

wss.on("connection", (ws: WebSocket) => {
  console.log("[TEST-SERVER] Client connected");

  ws.on("message", (message: string) => {
    console.log("[TEST-SERVER] Received:", message.toString());
    try {
      const data = JSON.parse(message.toString());
      if (data.type === "handshake") {
        console.log("[TEST-SERVER] Handshake received:", data.deviceId);
      }
    } catch (e) {
      console.error("[TEST-SERVER] Parse error");
    }
  });

  // Send handshake to client
  ws.send(JSON.stringify({ type: "handshake", message: "Connected to PC" }));
});

console.log("[TEST-SERVER] Starting...");
