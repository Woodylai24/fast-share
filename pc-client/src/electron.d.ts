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
}

declare global {
  interface Window {
    electronAPI: IElectronAPI;
  }
}
