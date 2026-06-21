import { useState, useEffect, useCallback, useRef } from "react";
import { TitleBar } from "./TitleBar";
import { PairingPanel } from "./components/PairingPanel";
import { Settings } from "./Settings";
import { ThemeProvider } from "./contexts/ThemeContext";
import { SummaryPopup } from "./SummaryPopup";
import { ContextMenu } from "./components/ContextMenu";
import { MessageBubble } from "./components/MessageBubble";
import { FileInput } from "./components/FileInput";
import { Onboarding } from "./Onboarding";
import { useConnection } from "./hooks/useConnection";
import { useMessages } from "./hooks/useMessages";
import { type Message } from "./types";
import "./App.css";



function App() {
  const [showSettings, setShowSettings] = useState(false);
  const [showQr, setShowQr] = useState(false);
  const [showOnboarding, setShowOnboarding] = useState(false);
  const [summaryPopup, setSummaryPopup] = useState<{
    isOpen: boolean;
    message: Message | null;
  }>({ isOpen: false, message: null });
  const [hasApiKey, setHasApiKey] = useState(false);
  const [isDragging, setIsDragging] = useState(false);
  const [contextMenu, setContextMenu] = useState<{
    x: number;
    y: number;
    message: Message;
  } | null>(null);

  const {
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
    pairingRefreshTrigger,
  } = useConnection();

  const {
    inputText,
    setInputText,
    sendText,
    clearHistory,
    addSentFileMessage,
    messageListRef,
  } = useMessages({ messages, setMessages, isConnected });

  // Auto-close pairing panel when a NEW device pairs (not on reconnect)
  const prevHasPaired = useRef(false);
  useEffect(() => {
    if (hasPairedDevice && !prevHasPaired.current && showQr) {
      setShowQr(false);
    }
    prevHasPaired.current = hasPairedDevice;
  }, [hasPairedDevice, showQr]);

  // Check API key
  const checkApiKey = useCallback(async () => {
    try {
      const settings = await window.electronAPI.getAISettings();
      setHasApiKey(!!settings.apiKey);
    } catch {
      setHasApiKey(false);
    }
  }, []);

  // Block Ctrl+A globally (except in input/textarea/select fields)
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (
        e.key === "a" &&
        (e.ctrlKey || e.metaKey) &&
        !(e.target instanceof HTMLInputElement) &&
        !(e.target instanceof HTMLTextAreaElement) &&
        !(e.target instanceof HTMLSelectElement)
      ) {
        e.preventDefault();
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, []);

  // Play notification sound when main process requests it
  useEffect(() => {
    const cleanup = window.electronAPI.onPlayNotificationSound(() => {
      const audio = new Audio("notification.wav");
      audio.volume = 0.5;
      audio.play().catch(() => { /* ignore playback errors */ });
    });
    return cleanup;
  }, []);

  useEffect(() => {
    checkApiKey();
  }, [checkApiKey]);

  // Check onboarding status
  const checkOnboarding = useCallback(async () => {
    try {
      const settings = await window.electronAPI.getSettings();
      if (!settings.onboardingComplete) {
        setShowOnboarding(true);
      }
    } catch {
      // default: don't show
    }
  }, []);

  useEffect(() => {
    checkOnboarding();
  }, [checkOnboarding]);

  const handleOnboardingComplete = useCallback(async () => {
    setShowOnboarding(false);
    await window.electronAPI.saveSettings({ onboardingComplete: true });
  }, []);

  // File handling
  const handleBrowseFiles = async () => {
    const filePaths = await window.electronAPI.selectFile();
    if (filePaths && filePaths.length > 0) {
      filePaths.forEach((filePath) => {
        const fileName = filePath.split(/[/\\]/).pop() || filePath;
        const httpPort = connectionInfo?.httpPort || 8081;
        const messageId = addSentFileMessage(fileName, httpPort, selectedIp);
        window.electronAPI.offerFile(filePath, selectedIp, messageId);
      });
    }
  };

  const handleDrop = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);

    if (!hasPairedDevice) return;

    const files = Array.from(e.dataTransfer.files);
    if (files.length > 0) {
      files.forEach((file) => {
        const filePath = window.electronAPI.getPathForFile(file);
        if (filePath) {
          const httpPort = connectionInfo?.httpPort || 8081;
          const messageId = addSentFileMessage(file.name, httpPort, selectedIp);
          window.electronAPI.offerFile(filePath, selectedIp, messageId);
        }
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
    if (!hasPairedDevice) return;
    setIsDragging(true);
  };

  const handleDragLeave = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    if (!hasPairedDevice) return;
    if (e.currentTarget.contains(e.relatedTarget as Node)) return;
    setIsDragging(false);
  };

  // Context menu handlers
  const handleContextMenu = (e: React.MouseEvent, message: Message) => {
    e.preventDefault();
    e.stopPropagation();
    setContextMenu({ x: e.clientX, y: e.clientY, message });
  };

  const handleOpenMessage = useCallback((message: Message) => {
    if (message.url) {
      window.electronAPI.openExternal(message.url);
    }
  }, []);

  const handleCopyMessage = useCallback((message: Message) => {
    navigator.clipboard.writeText(message.content);
  }, []);

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
    <ThemeProvider>
      {showOnboarding && <Onboarding onComplete={handleOnboardingComplete} />}
      <TitleBar
        onSettingsClick={() => setShowSettings(true)}
        onQrClick={() => setShowQr(true)}
      />
      <div
        className={`container ${isDragging ? "dragging" : ""}`}
        onDrop={handleDrop}
        onDragOver={handleDragOver}
        onDragEnter={handleDragEnter}
        onDragLeave={handleDragLeave}
      >
        {hasPairedDevice && (
          <FileInput
            isDragging={isDragging}
            onDrop={handleDrop}
            onDragOver={handleDragOver}
            onDragEnter={handleDragEnter}
            onDragLeave={handleDragLeave}
            onBrowseFiles={handleBrowseFiles}
          />
        )}

        <div className="messages-area">
          <div className="messages-header">
            <h3>Activity Log</h3>
            <button
              className="clear-history-btn"
              onClick={clearHistory}
              title="Clear message history"
            >
              🗑️ Clear
            </button>
          </div>
          <div className="message-list" ref={messageListRef}>
            {messages.length === 0 ? (
              <div style={{ textAlign: "center", color: "var(--text-secondary)", padding: "2rem", fontSize: "0.9rem" }}>
                {hasPairedDevice
                  ? "No messages yet. Start chatting!"
                  : "No device paired. Click the QR icon in the top bar to pair a device."}
              </div>
            ) : (
              messages.map((msg, idx) => (
                <MessageBubble
                  key={msg.id}
                  message={msg}
                  onContextMenu={handleContextMenu}
                  onClick={handleOpenMessage}
                  previousMessage={idx > 0 ? messages[idx - 1] : undefined}
                />
              ))
            )}
          </div>
        </div>

        <div className="input-area">
          <input
            type="text"
            value={inputText}
            onChange={(e) => setInputText(e.target.value)}
            placeholder={hasPairedDevice ? "Type text to send..." : "Pair a device to start messaging..."}
            onKeyDown={(e) => e.key === "Enter" && sendText()}
            disabled={!hasPairedDevice}
          />
          <button onClick={sendText} disabled={!hasPairedDevice}>Send</button>
          {isConnected && (
            <button
              onClick={disconnect}
              style={{ marginLeft: "0.5rem", backgroundColor: "#dc3545" }}
            >
              Disconnect
            </button>
          )}
        </div>

        {/* Settings Panel */}
        <Settings
          isOpen={showSettings}
          onClose={() => {
            setShowSettings(false);
            checkApiKey();
          }}
        />

        {/* Pairing Panel (QR code + paired devices) */}
        <PairingPanel
          isOpen={showQr}
          onClose={() => setShowQr(false)}
          connectionInfo={connectionInfo}
          selectedIp={selectedIp}
          onIpChange={setSelectedIp}
          getQrData={getQrData}
          refreshTrigger={pairingRefreshTrigger}
        />

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
    </ThemeProvider>
  );
}

export default App;
