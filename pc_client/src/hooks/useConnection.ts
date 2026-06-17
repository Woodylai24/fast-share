import { useState, useEffect, useCallback } from "react";
import { type ConnectionInfo, type Message, MessageType } from "../types";
import { generateId, isImageFile } from "../utils";

export function useConnection() {
  const [connectionInfo, setConnectionInfo] = useState<ConnectionInfo | null>(
    null,
  );
  const [selectedIp, setSelectedIp] = useState<string>("");
  // Connection state: 'no-paired' | 'paired-offline' | 'connected'
  const [connectionState, setConnectionState] = useState<'no-paired' | 'paired-offline' | 'connected'>('no-paired');
  const [pairedDevice, setPairedDevice] = useState<{ id: string; name: string; lastSeenAt: string } | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [lastConnected, setLastConnected] = useState<{ device: string; at: string } | null>(null);

  // Derived value for backward compatibility
  const isConnected = connectionState === 'connected';

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

    window.electronAPI.getLastConnected().then(setLastConnected);

    // Check if any devices are already paired
    window.electronAPI.getPairedDevices().then((devices) => {
      const entries = Object.entries(devices);
      if (entries.length > 0) {
        const [id, info] = entries[0];
        setPairedDevice({ id, name: info.name, lastSeenAt: info.lastSeenAt });
        setConnectionState('paired-offline');
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
        setConnectionState('connected');
        window.electronAPI.getLastConnected().then(setLastConnected);
        window.electronAPI.getPairedDevices().then((devices) => {
          const entries = Object.entries(devices);
          if (entries.length > 0) {
            const [id, info] = entries[0];
            setPairedDevice({ id, name: info.name, lastSeenAt: info.lastSeenAt });
          }
        });
      } else if (data.type === "ping") {
        window.electronAPI.sendPong();
      } else if (data.type === "disconnect") {
        window.electronAPI.getPairedDevices().then((devices) => {
          const entries = Object.entries(devices);
          if (entries.length > 0) {
            const [id, info] = entries[0];
            setPairedDevice({ id, name: info.name, lastSeenAt: info.lastSeenAt });
            setConnectionState('paired-offline');
          } else {
            setConnectionState('no-paired');
          }
        });
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
      window.electronAPI.getPairedDevices().then((devices) => {
        const entries = Object.entries(devices);
        if (entries.length > 0) {
          const [id, info] = entries[0];
          setPairedDevice({ id, name: info.name, lastSeenAt: info.lastSeenAt });
          setConnectionState('paired-offline');
        } else {
          setConnectionState('no-paired');
        }
      });
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
    // When the server receives a message-ack from mobile, it notifies the
    // renderer to upgrade the message from 'sent' (✓) to 'delivered' (✓✓).
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
    setConnectionState('no-paired');
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
    connectionState,
    pairedDevice,
    messages,
    setMessages,
    disconnect,
    getQrData,
    lastConnected,
  };
}
