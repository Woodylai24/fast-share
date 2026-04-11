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
  sendText: (text: string) => void;
  sendPong: () => void;
  disconnectClient: () => void;
  offerFile: (filePath: string, ip: string) => void;
  selectFile: () => Promise<string[] | undefined>;
  openExternal: (url: string) => void;
  openPath: (filePath: string) => void;
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
  getPathForFile: (file: File) => string;
  // AI Settings
  getAISettings: () => Promise<{ apiKey: string | null; provider: string; model: string }>;
  saveAISettings: (settings: { apiKey?: string; provider?: string; model?: string }) => Promise<{ success: boolean }>;
  fetchModels: () => Promise<{ id: string; name: string }[] | { error: string }>;
  // AI Summarize
  summarizeContent: (data: { type: string; content: string; filePath?: string; filename?: string }) =>
    Promise<{ streamId: string } | { error: string }>;
  summarizeCancel: (streamId: string) => void;
  onSummarizeChunk: (callback: (data: { streamId: string; text: string }) => void) => () => void;
  onSummarizeDone: (callback: (data: { streamId: string }) => void) => () => void;
  onSummarizeError: (callback: (data: { streamId: string; error: string }) => void) => () => void;
}

declare global {
  interface Window {
    electronAPI: IElectronAPI;
  }
}
