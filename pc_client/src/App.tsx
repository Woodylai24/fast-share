import { useState, useEffect, useRef, useCallback } from "react";
import { QRCodeSVG } from "qrcode.react";
import Linkify from "react-linkify";
import { TitleBar } from "./TitleBar";
import { AISettings } from "./AISettings";
import { SummaryPopup } from "./SummaryPopup";
import "./App.css";

// Message types as const object
const MessageType = {
  TEXT: "text",
  FILE: "file",
  IMAGE: "image",
  SYSTEM: "system",
} as const;

type MessageType = (typeof MessageType)[keyof typeof MessageType];

// Message interface
interface Message {
  id: string;
  type: MessageType;
  content: string;
  sender: "Mobile" | "Me" | "System";
  timestamp: Date;
  url?: string;
  filename?: string;
}

// Stored message interface for JSON parsing
interface StoredMessage {
  id: string;
  type: MessageType;
  content: string;
  sender: "Mobile" | "Me" | "System";
  timestamp: string;
  url?: string;
  filename?: string;
}

// Generate unique ID
const generateId = (): string => {
  return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
};

// Format timestamp for display
const formatTime = (date: Date): string => {
  return date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
};

// Format date for day separator
const formatDate = (date: Date): string => {
  const today = new Date();
  const yesterday = new Date(today);
  yesterday.setDate(yesterday.getDate() - 1);

  if (date.toDateString() === today.toDateString()) {
    return "Today";
  } else if (date.toDateString() === yesterday.toDateString()) {
    return "Yesterday";
  } else {
    return date.toLocaleDateString([], {
      weekday: "long",
      month: "short",
      day: "numeric",
    });
  }
};

// Message persistence service
const MessageStorage = {
  STORAGE_KEY: "fastshare_messages",

  save(messages: Message[]): void {
    try {
      const data: StoredMessage[] = messages.map((msg) => ({
        ...msg,
        timestamp: msg.timestamp.toISOString(),
      }));
      localStorage.setItem(this.STORAGE_KEY, JSON.stringify(data));
    } catch (e) {
      console.error("Failed to save messages:", e);
    }
  },

  load(): Message[] {
    try {
      const data = localStorage.getItem(this.STORAGE_KEY);
      if (!data) return [];
      const parsed: StoredMessage[] = JSON.parse(data);
      return parsed.map((msg) => ({
        ...msg,
        timestamp: new Date(msg.timestamp),
      }));
    } catch (e) {
      console.error("Failed to load messages:", e);
      return [];
    }
  },

  clear(): void {
    localStorage.removeItem(this.STORAGE_KEY);
  },
};

// Context menu component
interface ContextMenuProps {
  x: number;
  y: number;
  message: Message;
  onClose: () => void;
  onCopy: (message: Message) => void;
  onDelete: (message: Message) => void;
  onOpen: (message: Message) => void;
  onSummarize: (message: Message) => void;
  hasApiKey: boolean;
}

function ContextMenu({
  x,
  y,
  message,
  onClose,
  onCopy,
  onDelete,
  onOpen,
  onSummarize,
  hasApiKey,
}: ContextMenuProps) {
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        onClose();
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, [onClose]);

  return (
    <div
      ref={menuRef}
      className="context-menu"
      style={{ top: y, left: x }}
      onClick={(e) => e.stopPropagation()}
    >
      {(message.type === MessageType.FILE ||
        message.type === MessageType.IMAGE) &&
        message.url && (
          <button
            className="context-menu-item"
            onClick={() => {
              onOpen(message);
              onClose();
            }}
          >
            🔗 Open
          </button>
        )}
      {message.type === MessageType.TEXT && (
        <button
          className="context-menu-item"
          onClick={() => {
            onCopy(message);
            onClose();
          }}
        >
          📋 Copy
        </button>
      )}
      <button
        className="context-menu-item"
        disabled={!hasApiKey}
        title={!hasApiKey ? "Set up API key in Settings" : undefined}
        onClick={() => {
          onSummarize(message);
          onClose();
        }}
      >
        🤖 Summarize
      </button>
      <button
        className="context-menu-item delete"
        onClick={() => {
          onDelete(message);
          onClose();
        }}
      >
        🗑️ Delete
      </button>
    </div>
  );
}

// Message bubble component
interface MessageBubbleProps {
  message: Message;
  onContextMenu: (e: React.MouseEvent, message: Message) => void;
  onClick: (message: Message) => void;
  previousMessage?: Message;
}

function MessageBubble({
  message,
  onContextMenu,
  onClick,
  previousMessage,
}: MessageBubbleProps) {
  const isMe = message.sender === "Me";
  const isSystem = message.sender === "System";

  // Check if we need to show day separator
  const showDaySeparator =
    !previousMessage ||
    message.timestamp.toDateString() !==
      previousMessage.timestamp.toDateString();

  // Check if we need to show timestamp (every 5 minutes gap)
  const showTimestamp = true; // Always show timestamp on every message

  if (isSystem) {
    return (
      <>
        {showDaySeparator && (
          <div className="day-separator">{formatDate(message.timestamp)}</div>
        )}
        <div className="message-system">
          <span>{message.content}</span>
        </div>
      </>
    );
  }

  const renderContent = () => {
    switch (message.type) {
      case MessageType.IMAGE:
        return (
          <div className="message-image">
            <img
              src={message.url}
              alt={message.filename || "Image"}
              onClick={(e) => {
                e.stopPropagation();
                onClick(message);
              }}
              onError={(e) => {
                const target = e.target as HTMLImageElement;
                target.style.display = "none";
                target.parentElement!.innerHTML =
                  '<div class="image-error"><span>📷</span><span>Image not available</span></div>';
              }}
            />
            {message.filename && (
              <span className="message-filename">{message.filename}</span>
            )}
          </div>
        );
      case MessageType.FILE:
        return (
          <div
            className="message-file"
            onClick={(e) => {
              e.stopPropagation();
              onClick(message);
            }}
          >
            <div className="file-icon">📄</div>
            <div className="file-info">
              <span className="file-name">{message.filename || "File"}</span>
              <span className="file-action">Click to download</span>
            </div>
          </div>
        );
      default:
        return (
          <Linkify
            componentDecorator={(
              decoratedHref: string,
              decoratedText: string,
              key: number,
            ) => (
              <a
                key={key}
                href={decoratedHref}
                onClick={(e) => {
                  e.preventDefault();
                  window.electronAPI.openExternal(decoratedHref);
                }}
                style={{ color: "inherit", textDecoration: "underline" }}
              >
                {decoratedText}
              </a>
            )}
          >
            <span className="message-text">{message.content}</span>
          </Linkify>
        );
    }
  };

  return (
    <>
      {showDaySeparator && (
        <div className="day-separator">{formatDate(message.timestamp)}</div>
      )}
      <div
        className={`message-bubble ${isMe ? "message-mine" : "message-other"}`}
        onContextMenu={(e) => onContextMenu(e, message)}
        onClick={() =>
          message.type === MessageType.TEXT ? null : onClick(message)
        }
      >
        {!isMe && <div className="message-sender">{message.sender}</div>}
        {renderContent()}
        {showTimestamp && (
          <div className="message-time">{formatTime(message.timestamp)}</div>
        )}
      </div>
    </>
  );
}

// Initial messages from storage
const initialMessages = MessageStorage.load();

function App() {
  const [showAISettings, setShowAISettings] = useState(false);
  const [summaryPopup, setSummaryPopup] = useState<{ isOpen: boolean; message: Message | null }>({ isOpen: false, message: null });
  const [hasApiKey, setHasApiKey] = useState(false);
  const [connectionInfo, setConnectionInfo] = useState<{
    ips: string[];
    wsPort: number;
    httpPort: number;
  } | null>(null);
  const [selectedIp, setSelectedIp] = useState<string>("");
  const [messages, setMessages] = useState<Message[]>(initialMessages);
  const [inputText, setInputText] = useState("");
  const [isConnected, setIsConnected] = useState(false);
  const [isDragging, setIsDragging] = useState(false);
  const [contextMenu, setContextMenu] = useState<{
    x: number;
    y: number;
    message: Message;
  } | null>(null);
  const messageListRef = useRef<HTMLDivElement>(null);

  // Save messages when they change
  useEffect(() => {
    if (messages.length > 0) {
      MessageStorage.save(messages);
    }
  }, [messages]);

  // Auto-scroll to bottom when new messages arrive
  useEffect(() => {
    if (messageListRef.current) {
      messageListRef.current.scrollTop = messageListRef.current.scrollHeight;
    }
  }, [messages]);

  useEffect(() => {
    // Get connection info from Electron Main
    window.electronAPI.getConnectionInfo().then((info) => {
      setConnectionInfo(info);
      if (info.ips.length > 0) {
        // Prefer 192.168... if available
        const pref = info.ips.find((ip) => ip.startsWith("192.168."));
        setSelectedIp(pref || info.ips[0]);
      }
    });

    // Listen for messages - returns cleanup function
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
        // Connection established - no system message needed
      } else if (data.type === "ping") {
        // Respond to ping with pong
        window.electronAPI.sendPong();
      } else if (data.type === "disconnect") {
        // Mobile client disconnected
        setIsConnected(false);
        // No system message needed
      } else if (data.type === "image") {
        // Handle image from mobile - skip if we'll receive it via file-received
        // The image is sent via HTTP upload, so we'll get it via onFileReceived
        console.log(
          "[DEBUG] Image message received via WS, waiting for HTTP upload",
        );
      } else if (data.type === "file") {
        // Handle file from mobile - skip if we'll receive it via file-received
        console.log(
          "[DEBUG] File message received via WS, waiting for HTTP upload",
        );
      }
    });

    // Listen for disconnect events from backend - returns cleanup function
    const cleanupWsDisconnect = window.electronAPI.onWsDisconnect((data) => {
      console.log("[DEBUG] Disconnect event received:", data);
      setIsConnected(false);
      // No system message needed
    });

    // Listen for files (received via encrypted WS from mobile)
    const cleanupFileReceived = window.electronAPI.onFileReceived((file) => {
      // Determine if it's an image
      const isImage = /\.(jpg|jpeg|png|gif|webp|bmp)$/i.test(file.filename);
      const msgId = generateId();

      // Use localhost-only URL (HTTP server bound to 127.0.0.1)
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

    // Cleanup all listeners on unmount
    return () => {
      cleanupWsMessage();
      cleanupWsDisconnect();
      cleanupFileReceived();
    };
  }, [connectionInfo?.httpPort, selectedIp]);

  const handleSendText = () => {
    if (inputText.trim()) {
      window.electronAPI.sendText(inputText);
      const newMessage: Message = {
        id: generateId(),
        type: MessageType.TEXT,
        content: inputText,
        sender: "Me",
        timestamp: new Date(),
      };
      setMessages((prev) => [...prev, newMessage]);
      setInputText("");
    }
  };

  const handleDisconnect = () => {
    window.electronAPI.disconnectClient();
    setIsConnected(false);
    // No system message needed
  };

  const handleClearHistory = () => {
    setMessages([]);
    MessageStorage.clear();
  };

  const getQrData = () => {
    if (!connectionInfo || !selectedIp) return "";
    return JSON.stringify({
      ip: selectedIp,
      port: connectionInfo.wsPort,
      httpPort: connectionInfo.httpPort,
    });
  };

  const handleDrop = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);

    if (!isConnected) return;

    const files = Array.from(e.dataTransfer.files);
    if (files.length > 0) {
      files.forEach((file) => {
        // Electron exposes 'path' on File object
        const filePath = window.electronAPI.getPathForFile(file);
        if (filePath) {
          window.electronAPI.offerFile(filePath, selectedIp);
          const isImage = /\.(jpg|jpeg|png|gif|webp|bmp)$/i.test(file.name);
          const httpPort = connectionInfo?.httpPort || 8081;
          const fileUrl = `http://localhost:${httpPort}/files/${encodeURIComponent(file.name)}`;
          const newMessage: Message = {
            id: generateId(),
            type: isImage ? MessageType.IMAGE : MessageType.FILE,
            content: file.name,
            sender: "Me",
            timestamp: new Date(),
            url: fileUrl,
            filename: file.name,
          };
          setMessages((prev) => [...prev, newMessage]);
        }
      });
    }
  };

  const handleBrowseFiles = async () => {
    const filePaths = await window.electronAPI.selectFile();
    if (filePaths && filePaths.length > 0) {
      filePaths.forEach((filePath) => {
        window.electronAPI.offerFile(filePath, selectedIp);
        // Extract filename from path for display
        const fileName = filePath.split(/[/\\]/).pop() || filePath;
        const isImage = /\.(jpg|jpeg|png|gif|webp|bmp)$/i.test(fileName);
        const httpPort = connectionInfo?.httpPort || 8081;
        const fileUrl = `http://localhost:${httpPort}/files/${encodeURIComponent(fileName)}`;
        const newMessage: Message = {
          id: generateId(),
          type: isImage ? MessageType.IMAGE : MessageType.FILE,
          content: fileName,
          sender: "Me",
          timestamp: new Date(),
          url: fileUrl,
          filename: fileName,
        };
        setMessages((prev) => [...prev, newMessage]);
      });
    }
  };

  const handleDragOver = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
  };

  const handleDragEnter = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    if (!isConnected) return;
    setIsDragging(true);
  };

  const handleDragLeave = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    if (!isConnected) return;
    // Only set false if we left the main container, not just entered a child
    if (e.currentTarget.contains(e.relatedTarget as Node)) return;
    setIsDragging(false);
  };

  const handleContextMenu = (e: React.MouseEvent, message: Message) => {
    e.preventDefault();
    e.stopPropagation();
    setContextMenu({
      x: e.clientX,
      y: e.clientY,
      message,
    });
  };

  const handleOpenMessage = useCallback((message: Message) => {
    if (message.url) {
      window.electronAPI.openExternal(message.url);
    }
  }, []);

  const handleCopyMessage = useCallback((message: Message) => {
    navigator.clipboard.writeText(message.content);
  }, []);

  const checkApiKey = useCallback(async () => {
    try {
      const settings = await window.electronAPI.getAISettings();
      setHasApiKey(!!settings.apiKey);
    } catch {
      setHasApiKey(false);
    }
  }, []);

  useEffect(() => { checkApiKey(); }, [checkApiKey]);

  const handleSummarize = useCallback((message: Message) => {
    setSummaryPopup({ isOpen: true, message });
  }, []);

  const handleCloseSummary = useCallback(() => {
    setSummaryPopup({ isOpen: false, message: null });
    checkApiKey();
  }, [checkApiKey]);

  const handleDeleteMessage = useCallback((message: Message) => {
    setMessages((prev) => prev.filter((m) => m.id !== message.id));
  }, []);

  const closeContextMenu = useCallback(() => {
    setContextMenu(null);
  }, []);

  return (
    <>
      <TitleBar onSettingsClick={() => setShowAISettings(true)} />
      <div
        className={`container ${isDragging ? "dragging" : ""}`}
        onDrop={handleDrop}
        onDragOver={handleDragOver}
        onDragEnter={handleDragEnter}
        onDragLeave={handleDragLeave}
      >
        {isConnected && (
          <>
            <p style={{ color: "#aaa" }}>Drag & Drop files here to share</p>
            <button
              onClick={handleBrowseFiles}
              style={{ marginBottom: "1rem" }}
            >
              Browse Files
            </button>
          </>
        )}

        <div className="card">
          {connectionInfo ? (
            <div className="qr-section">
              {connectionInfo.ips.length > 1 && (
                <div style={{ marginBottom: "1rem" }}>
                  <label>Select Network: </label>
                  <select
                    title="network-selector"
                    value={selectedIp}
                    onChange={(e) => setSelectedIp(e.target.value)}
                    style={{ padding: "5px" }}
                  >
                    {connectionInfo.ips.map((ip) => (
                      <option key={ip} value={ip}>
                        {ip}
                      </option>
                    ))}
                  </select>
                </div>
              )}

              <QRCodeSVG value={getQrData()} size={200} />
              <p>Scan with Mobile App to Connect</p>
              <p className="mono">
                {selectedIp}:{connectionInfo.wsPort}
              </p>
            </div>
          ) : (
            <p>Loading connection info...</p>
          )}

          <div
            className={`status ${isConnected ? "connected" : "disconnected"}`}
          >
            {isConnected
              ? "Status: Mobile Connected"
              : "Status: Waiting for connection..."}
          </div>
        </div>

        {isConnected && (
          <div className="messages-area">
            <div className="messages-header">
              <h3>Activity Log</h3>
              <button
                className="clear-history-btn"
                onClick={handleClearHistory}
                title="Clear message history"
              >
                🗑️ Clear
              </button>
            </div>
            <div className="message-list" ref={messageListRef}>
              {messages.map((msg, idx) => (
                <MessageBubble
                  key={msg.id}
                  message={msg}
                  onContextMenu={handleContextMenu}
                  onClick={handleOpenMessage}
                  previousMessage={idx > 0 ? messages[idx - 1] : undefined}
                />
              ))}
            </div>
          </div>
        )}

        {isConnected && (
          <div className="input-area">
            <input
              type="text"
              value={inputText}
              onChange={(e) => setInputText(e.target.value)}
              placeholder="Type text to send..."
              onKeyDown={(e) => e.key === "Enter" && handleSendText()}
            />
            <button onClick={handleSendText}>Send</button>
            <button
              onClick={handleDisconnect}
              style={{ marginLeft: "0.5rem", backgroundColor: "#dc3545" }}
            >
              Disconnect
            </button>
          </div>
        )}

        {/* AI Settings Panel */}
        <AISettings isOpen={showAISettings} onClose={() => { setShowAISettings(false); checkApiKey(); }} />

        {/* Context Menu */}
        {contextMenu && (
          <ContextMenu
            x={contextMenu.x}
            y={contextMenu.y}
            message={contextMenu.message}
            onClose={closeContextMenu}
            onCopy={handleCopyMessage}
            onDelete={handleDeleteMessage}
            onOpen={handleOpenMessage}
            onSummarize={handleSummarize}
            hasApiKey={hasApiKey}
          />
        )}

        {/* Summary Popup */}
        <SummaryPopup
          isOpen={summaryPopup.isOpen}
          message={summaryPopup.message}
          onClose={handleCloseSummary}
        />
      </div>
    </>
  );
}

export default App;
