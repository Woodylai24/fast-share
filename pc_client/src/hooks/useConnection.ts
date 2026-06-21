import { useState, useEffect, useCallback } from "react";
import { type ConnectionInfo, type Message, MessageType } from "../types";
import { generateId, isImageFile } from "../utils";

export function useConnection() {
  const [connectionInfo, setConnectionInfo] = useState<ConnectionInfo | null>(
    null,
  );
  const [selectedIp, setSelectedIp] = useState<string>("");

  // Two independent booleans — single source of truth for each concern.
  // hasPairedDevice: identity (loaded once, updated only on pair/unpair)
  // isConnected: transport (set directly by WS events, no async queries)
  const [hasPairedDevice, setHasPairedDevice] = useState(false);
  const [isConnected, setIsConnected] = useState(false);
  const [pairedDevice, setPairedDevice] = useState<{ id: string; name: string; lastSeenAt: string } | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [lastConnected, setLastConnected] = useState<{ device: string; at: string } | null>(null);

  // Get connection info and initial paired-device state from Electron Main.
  // These run ONCE on mount — no async queries inside event handlers.
  useEffect(() => {
    window.electronAPI.getConnectionInfo().then((info) => {
      setConnectionInfo(info);
      if (info.ips.length > 0) {
        // Prefer 192.168... if available
        const pref = info.ips.find((ip) => ip.startsWith("192.168."));
        setSelectedIp(pref || info.ips[0]);
      }
    });

    window.electronAPI.getLastConnected().then(setLastConnected);

    // Load paired device state ONCE — this is the only place we query it.
    // Subsequent updates come from WS events, not async queries.
    window.electronAPI.getPairedDevices().then((devices) => {
      const entries = Object.entries(devices);
      if (entries.length > 0) {
        const [id, info] = entries[0];
        setPairedDevice({ id, name: info.name, lastSeenAt: info.lastSeenAt });
        setHasPairedDevice(true);
      }
    });
  }, []);

  // Listen for WS messages, disconnects, and file transfers.
  // State transitions are SYNCHRONOUS — no async getPairedDevices() calls.
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
        // Connection established — direct, no async query
        setIsConnected(true);
        window.electronAPI.getLastConnected().then(setLastConnected);
      } else if (data.type === "ping") {
        window.electronAPI.sendPong();
      } else if (data.type === "disconnect") {
        // Mobile went to background — connection lost
        setIsConnected(false);
      } else if (data.type === "unpaired") {
        // Mobile explicitly unpaired — remove from paired state
        setHasPairedDevice(false);
        setIsConnected(false);
        setPairedDevice(null);
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
      // Connection lost — direct, no async query
      setIsConnected(false);
      window.electronAPI.getLastConnected().then(setLastConnected);
    });

    // --- Incoming file transfer: create placeholder on start ---
    const cleanupFileReceivedStart =
      window.electronAPI.onFileReceivedStart((data) => {
        const isImage = isImageFile(data.filename);
        const placeholder: Message = {
          id: generateId(),
          type: isImage ? MessageType.IMAGE : MessageType.FILE,
          content: data.filename,
          sender: "Mobile",
          timestamp: new Date(),
          filename: data.filename,
          transferState: "pending",
          transferProgress: 0,
        };
        setMessages((prev) => [...prev, placeholder]);
      });

    // --- File progress updates (both send and receive) ---
    const cleanupFileProgress = window.electronAPI.onFileProgress((data) => {
      setMessages((prev) =>
        prev.map((msg) => {
          if (msg.filename !== data.filename) return msg;
          // Don't update messages that are already complete
          if (msg.transferState === "complete") return msg;

          if (data.failed) {
            return { ...msg, transferState: "failed" as const };
          }

          const progress =
            data.totalBytes > 0
              ? Math.round((data.receivedBytes / data.totalBytes) * 100)
              : 0;

          return {
            ...msg,
            transferState: "transferring" as const,
            transferProgress: progress,
          };
        }),
      );
    });

    // --- Incoming file transfer: finalize on complete ---
    const cleanupFileReceived = window.electronAPI.onFileReceived((file) => {
      const isImage = isImageFile(file.filename);
      const httpPort = connectionInfo?.httpPort || 8081;
      const fileUrl = `http://localhost:${httpPort}/files/${encodeURIComponent(file.filename)}`;

      setMessages((prev) => {
        // Find and update the placeholder message
        const existingIdx = prev.findIndex(
          (m) =>
            m.filename === file.filename &&
            m.transferState !== undefined &&
            m.transferState !== "complete",
        );

        if (existingIdx >= 0) {
          const updated = [...prev];
          updated[existingIdx] = {
            ...updated[existingIdx],
            type: isImage ? MessageType.IMAGE : MessageType.FILE,
            url: fileUrl,
            transferState: "complete",
            transferProgress: 100,
          };
          return updated;
        }

        // No placeholder found — create a new message (legacy fallback)
        const newMessage: Message = {
          id: generateId(),
          type: isImage ? MessageType.IMAGE : MessageType.FILE,
          content: file.filename,
          sender: "Mobile",
          timestamp: new Date(),
          url: fileUrl,
          filename: file.filename,
        };
        return [...prev, newMessage];
      });
    });

    // --- Outgoing file transfer: mark existing message as pending ---
    const cleanupFileSentStart = window.electronAPI.onFileSentStart((data) => {
      setMessages((prev) =>
        prev.map((msg) => {
          if (msg.filename !== data.filename || msg.sender !== "Me") return msg;
          return {
            ...msg,
            transferState: "pending" as const,
            transferProgress: 0,
          };
        }),
      );
    });

    // --- Outgoing file transfer: mark complete ---
    const cleanupFileSentComplete =
      window.electronAPI.onFileSentComplete((data) => {
        setMessages((prev) =>
          prev.map((msg) => {
            if (msg.filename !== data.filename || msg.sender !== "Me") return msg;
            if (data.failed) {
              return { ...msg, transferState: "failed" as const };
            }
            return {
              ...msg,
              transferState: "complete" as const,
              transferProgress: 100,
            };
          }),
        );
      });

    // --- Delivery status (ACK) updates ---
    const cleanupDeliveryStatus = window.electronAPI.onDeliveryStatus((data) => {
      setMessages((prev) =>
        prev.map((msg) =>
          msg.id === data.messageId
            ? { ...msg, deliveryStatus: data.status as "sent" | "delivered" }
            : msg
        )
      );
    });

    return () => {
      cleanupWsMessage();
      cleanupWsDisconnect();
      cleanupFileReceivedStart();
      cleanupFileProgress();
      cleanupFileReceived();
      cleanupFileSentStart();
      cleanupFileSentComplete();
      cleanupDeliveryStatus();
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
    hasPairedDevice,
    pairedDevice,
    messages,
    setMessages,
    disconnect,
    getQrData,
    lastConnected,
  };
}
