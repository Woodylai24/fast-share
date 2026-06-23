export type WsMessage =
  | { type: "text"; content: string }
  | { type: "handshake"; message: string; device?: string }
  | { type: "file"; filename: string; url: string }
  | { type: "image"; filename: string; url: string }
  | { type: "file_offer"; filename: string; url: string }
  | { type: "ping" }
  | { type: "disconnect"; reason?: string }
  | { type: string; [key: string]: unknown };

export interface IElectronAPI {
  getConnectionInfo: () => Promise<{
    ips: string[];
    wsPort: number;
    httpPort: number;
  }>;
  getAppVersion: () => Promise<string>;
  sendText: (text: string, messageId: string) => void;
  sendPong: () => void;
  disconnectClient: () => void;
  offerFile: (filePath: string, ip: string, messageId: string) => void;
  selectFile: () => Promise<string[] | undefined>;
  openExternal: (url: string) => void;
  openPath: (filePath: string) => void;
  openFolder: () => void;
  // Window controls
  windowMinimize: () => void;
  windowMaximize: () => void;
  windowClose: () => void;
  windowIsMaximized: () => Promise<boolean>;
  onWsMessage: (callback: (data: WsMessage) => void) => () => void;
  onWsDisconnect: (callback: (data: { reason?: string }) => void) => () => void;
  onFileReceived: (
    callback: (file: { filename: string; path: string }) => void,
  ) => () => void;
  onFileReceivedStart: (
    callback: (data: { filename: string; fileSize: number; mimeType: string }) => void,
  ) => () => void;
  onFileProgress: (
    callback: (data: { filename: string; receivedBytes: number; totalBytes: number; direction: string; failed?: boolean }) => void,
  ) => () => void;
  onFileSentStart: (
    callback: (data: { filename: string; fileSize: number; mimeType: string }) => void,
  ) => () => void;
  onFileSentComplete: (
    callback: (data: { filename: string; failed?: boolean }) => void,
  ) => () => void;
  getPathForFile: (file: File) => string;
  // AI Settings
  getAISettings: () => Promise<{ apiKey: string | null; provider: string; model: string }>;
  saveAISettings: (settings: { apiKey?: string; provider?: string; model?: string }) => Promise<{ success: boolean }>;
  fetchModels: () => Promise<{ id: string; name: string; vision: boolean }[] | { error: string }>;
  // AI Summarize
  summarizeContent: (data: { type: string; content: string; filePath?: string; filename?: string }) =>
    Promise<{ streamId: string } | { error: string }>;
  summarizeCancel: (streamId: string) => void;
  onSummarizeChunk: (callback: (data: { streamId: string; text: string }) => void) => () => void;
  onSummarizeDone: (callback: (data: { streamId: string }) => void) => () => void;
  onSummarizeError: (callback: (data: { streamId: string; error: string }) => void) => () => void;
  // General settings (theme, etc.)
  getSettings: () => Promise<{ theme?: string; [key: string]: unknown }>;
  saveSettings: (settings: { theme?: string; [key: string]: unknown }) => Promise<{ success: boolean }>;
  onSettingsChanged: (callback: (settings: Record<string, unknown>) => void) => () => void;
  onPlayNotificationSound: (callback: () => void) => () => void;
  // Last connected device info
  getLastConnected: () => Promise<{ device: string; at: string }>;
  // Paired device management
  getPairedDevices: () => Promise<Record<string, { fcmToken: string; name: string; pairedAt: string; lastSeenAt: string }>>;
  unpairDevice: (deviceId: string) => Promise<void>;
  onDeliveryStatus: (callback: (data: { messageId: string; status: string }) => void) => () => void;
}

declare global {
  interface Window {
    electronAPI: IElectronAPI;
  }
}
