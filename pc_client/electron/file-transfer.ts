import path from "path";
import fs from "fs";
import os from "os";
import { CryptoManager } from "./crypto";

// --- File Transfer Constants ---
const FILE_CHUNK_SIZE = 64 * 1024; // 64KB chunks
const CHUNK_REASSEMBLY_TIMEOUT_MS = 30000; // 30 seconds

// --- Incoming File Transfer State ---
interface IncomingFileTransfer {
  filename: string;
  fileSize: number;
  mimeType: string;
  chunks: Buffer[];
  receivedBytes: number;
  lastNotifiedPct: number;
  timer: ReturnType<typeof setTimeout>;
}

// ClientInfo must have an incomingFile property — we use this interface internally
interface FileTransferClient {
  incomingFile?: IncomingFileTransfer;
}

// --- File chunk reassembly cleanup ---
function cleanupFileReassembly(client: FileTransferClient) {
  if (client.incomingFile) {
    clearTimeout(client.incomingFile.timer);
    client.incomingFile = undefined;
  }
}

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
type SendEncryptedFn = (client: any, data: object) => void;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type GetMainWindowFn = () => any;

/** Tell the renderer to play the notification sound via IPC. */
function playNotificationSound(getMainWindow: GetMainWindowFn) {
  getMainWindow()?.webContents.send("play-notification-sound");
}

/**
 * Process a decrypted (or plaintext legacy) message from a mobile client.
 * Handles file-start, file-chunk, file-end, clipboard, text, file, image, and default messages.
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
        lastNotifiedPct: -1,
        timer: setTimeout(() => {
          console.error(
            `[DEBUG] File chunk reassembly timeout for ${clientInfo.incomingFile?.filename}`,
          );
          cleanupFileReassembly(clientInfo);
        }, CHUNK_REASSEMBLY_TIMEOUT_MS),
      };

      // Notify renderer that a file transfer is starting (create placeholder)
      getMainWindow()?.webContents.send("file-received-start", {
        filename: data.filename,
        fileSize: data.fileSize,
        mimeType: data.mimeType || "application/octet-stream",
      });
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

      // Throttled progress update: notify every ~5% change
      const totalBytes = clientInfo.incomingFile.fileSize;
      if (totalBytes > 0) {
        const currentPct = Math.floor(
          (clientInfo.incomingFile.receivedBytes / totalBytes) * 100,
        );
        if (currentPct - clientInfo.incomingFile.lastNotifiedPct >= 5) {
          clientInfo.incomingFile.lastNotifiedPct = currentPct;
          getMainWindow()?.webContents.send("file-progress", {
            filename: clientInfo.incomingFile.filename,
            receivedBytes: clientInfo.incomingFile.receivedBytes,
            totalBytes,
            direction: "receive",
          });
        }
      }

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
        // Notify renderer of failure
        getMainWindow()?.webContents.send("file-progress", {
          filename: fileTransfer.filename,
          receivedBytes: fileTransfer.receivedBytes,
          totalBytes: fileTransfer.fileSize,
          direction: "receive",
          failed: true,
        });
        clientInfo.incomingFile = undefined;
        return;
      }

      // Save file to shared directory
      const sharedDir = path.join(os.homedir(), "FastShare");
      const savePath = path.join(sharedDir, fileTransfer.filename);
      fs.writeFileSync(savePath, assembled);

      console.log(`[DEBUG] File received via encrypted WS: ${savePath}`);

      // Notify renderer
      getMainWindow()?.webContents.send("file-received", {
        filename: fileTransfer.filename,
        path: savePath,
      });

      clientInfo.incomingFile = undefined;
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

/**
 * Send a file via encrypted chunked WebSocket transfer.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function sendFileEncrypted(client: any, filePath: string, fileName: string, messageType: string, sendEncrypted: SendEncryptedFn, getMainWindow: GetMainWindowFn, messageId?: string) {
  try {
    const fileBuffer = fs.readFileSync(filePath);
    const fileSize = fileBuffer.length;
    const mimeType = getMimeType(fileName);
    const checksum = CryptoManager.sha256(fileBuffer);

    // Notify renderer that a file send is starting
    getMainWindow()?.webContents.send("file-sent-start", {
      filename: fileName,
      fileSize,
      mimeType,
    });

    // Send file-start
    sendEncrypted(client, {
      type: "file-start",
      filename: fileName,
      fileSize,
      mimeType,
    });

    // Send file-chunks with progress
    let offset = 0;
    let seq = 0;
    let lastNotifiedPct = -1;
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

      // Throttled progress update: notify every ~5% change
      const currentPct = Math.floor((offset / fileSize) * 100);
      if (currentPct - lastNotifiedPct >= 5 || offset >= fileSize) {
        lastNotifiedPct = currentPct;
        getMainWindow()?.webContents.send("file-progress", {
          filename: fileName,
          receivedBytes: offset,
          totalBytes: fileSize,
          direction: "send",
        });
      }
    }

    // Send file-end
    const fileEndMsg: Record<string, unknown> = {
      type: "file-end",
      filename: fileName,
      checksum,
    };
    if (messageId) {
      fileEndMsg.messageId = messageId;
    }
    sendEncrypted(client, fileEndMsg);

    // Notify renderer that send is complete
    getMainWindow()?.webContents.send("file-sent-complete", {
      filename: fileName,
    });

    console.log(
      `[DEBUG] File sent via encrypted WS: ${fileName} (${fileSize} bytes, ${seq} chunks)`,
    );
  } catch (error) {
    console.error(`[DEBUG] Failed to send file via encrypted WS: ${error}`);
    // Notify renderer of failure
    getMainWindow()?.webContents.send("file-sent-complete", {
      filename: fileName,
      failed: true,
    });
  }
}

export {
  processFileMessage,
  sendFileEncrypted,
  cleanupFileReassembly,
  FILE_CHUNK_SIZE,
  CHUNK_REASSEMBLY_TIMEOUT_MS,
  getMimeType,
};
