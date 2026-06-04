import { useState, useEffect, useCallback } from "react";
import { type ConnectionInfo, type Message, MessageType } from "../types";
import { generateId, isImageFile } from "../utils";

export function useConnection() {
  const [connectionInfo, setConnectionInfo] = useState<ConnectionInfo | null>(
    null,
  );
  const [selectedIp, setSelectedIp] = useState<string>("");
  const [isConnected, setIsConnected] = useState(false);
  const [messages, setMessages] = useState<Message[]>([]);

  // Get connection info from Electron Main
  useEffect(() => {
    window.electronAPI.getConnectionInfo().then((info) => {
      setConnectionInfo(info);
      if (info.ips.length > 0) {
        // Prefer 192.168... if available
        const pref = info.ips.find((ip) => ip.startsWith("192.168."));
        setSelectedIp(pref || info.ips[0]);
      }
    });
  }, []);

  // Listen for WS messages, disconnects, and file transfers
  useEffect(() => {
    const cleanupWsMessage = window.electronAPI.onWsMessage((data) => {
      if (data.type === "text") {
        const content = (data as { content: string }).content || "";
        const newMessage: Message = {
          id: generateId(),
          type: MessageType.TEXT,
          content: content,
          sender: "Mobile",
          timestamp: new Date(),
        };
        setMessages((prev) => [...prev, newMessage]);
      } else if (data.type === "handshake") {
        setIsConnected(true);
      } else if (data.type === "ping") {
        window.electronAPI.sendPong();
      } else if (data.type === "disconnect") {
        setIsConnected(false);
      } else if (data.type === "image") {
        console.log(
          "[DEBUG] Image message received via WS, waiting for HTTP upload",
        );
      } else if (data.type === "file") {
        console.log(
          "[DEBUG] File message received via WS, waiting for HTTP upload",
        );
      }
    });

    const cleanupWsDisconnect = window.electronAPI.onWsDisconnect(() => {
      console.log("[DEBUG] Disconnect event received");
      setIsConnected(false);
    });

    const cleanupFileReceived = window.electronAPI.onFileReceived((file) => {
      const isImage = isImageFile(file.filename);
      const msgId = generateId();
      const httpPort = connectionInfo?.httpPort || 8081;
      const fileUrl = `http://localhost:${httpPort}/files/${encodeURIComponent(file.filename)}`;

      const newMessage: Message = {
        id: msgId,
        type: isImage ? MessageType.IMAGE : MessageType.FILE,
        content: file.filename,
        sender: "Mobile",
        timestamp: new Date(),
        url: fileUrl,
        filename: file.filename,
      };
      setMessages((prev) => [...prev, newMessage]);
    });

    return () => {
      cleanupWsMessage();
      cleanupWsDisconnect();
      cleanupFileReceived();
    };
  }, [connectionInfo?.httpPort]);

  const disconnect = useCallback(() => {
    window.electronAPI.disconnectClient();
    setIsConnected(false);
  }, []);

  const getQrData = useCallback(() => {
    if (!connectionInfo || !selectedIp) return "";
    return JSON.stringify({
      ip: selectedIp,
      port: connectionInfo.wsPort,
      httpPort: connectionInfo.httpPort,
    });
  }, [connectionInfo, selectedIp]);

  return {
    connectionInfo,
    selectedIp,
    setSelectedIp,
    isConnected,
    setIsConnected,
    messages,
    setMessages,
    disconnect,
    getQrData,
  };
}
