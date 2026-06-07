import { contextBridge, ipcRenderer, webUtils } from "electron";

contextBridge.exposeInMainWorld("electronAPI", {
  getConnectionInfo: () => ipcRenderer.invoke("get-connection-info"),
  sendText: (text: string) => ipcRenderer.send("send-text", text),
  sendPong: () => ipcRenderer.send("send-pong"),
  disconnectClient: () => ipcRenderer.send("disconnect-client"),
  offerFile: (filePath: string, ip: string) =>
    ipcRenderer.send("offer-file", filePath, ip),
  selectFile: () => ipcRenderer.invoke("select-file"),
  openExternal: (url: string) => ipcRenderer.send("open-external", url),
  openPath: (filePath: string) => ipcRenderer.send("open-path", filePath),
  openFolder: () => ipcRenderer.send("open-folder"),
  // Window controls
  windowMinimize: () => ipcRenderer.send("window-minimize"),
  windowMaximize: () => ipcRenderer.send("window-maximize"),
  windowClose: () => ipcRenderer.send("window-close"),
  windowIsMaximized: () => ipcRenderer.invoke("window-is-maximized"),
  onWsMessage: (callback: (data: unknown) => void) => {
    const listener = (_event: Electron.IpcRendererEvent, value: unknown) =>
      callback(value);
    ipcRenderer.on("ws-message", listener);
    return () => ipcRenderer.removeListener("ws-message", listener);
  },
  onWsDisconnect: (callback: (data: { reason?: string }) => void) => {
    const listener = (
      _event: Electron.IpcRendererEvent,
      value: { reason?: string },
    ) => callback(value);
    ipcRenderer.on("ws-disconnect", listener);
    return () => ipcRenderer.removeListener("ws-disconnect", listener);
  },
  onFileReceived: (
    callback: (file: { filename: string; path: string }) => void,
  ) => {
    const listener = (
      _event: Electron.IpcRendererEvent,
      value: { filename: string; path: string },
    ) => callback(value);
    ipcRenderer.on("file-received", listener);
    return () => ipcRenderer.removeListener("file-received", listener);
  },
  onFileReceivedStart: (
    callback: (data: { filename: string; fileSize: number; mimeType: string }) => void,
  ) => {
    const listener = (
      _event: Electron.IpcRendererEvent,
      value: { filename: string; fileSize: number; mimeType: string },
    ) => callback(value);
    ipcRenderer.on("file-received-start", listener);
    return () => ipcRenderer.removeListener("file-received-start", listener);
  },
  onFileProgress: (
    callback: (data: { filename: string; receivedBytes: number; totalBytes: number; direction: string; failed?: boolean }) => void,
  ) => {
    const listener = (
      _event: Electron.IpcRendererEvent,
      value: { filename: string; receivedBytes: number; totalBytes: number; direction: string; failed?: boolean },
    ) => callback(value);
    ipcRenderer.on("file-progress", listener);
    return () => ipcRenderer.removeListener("file-progress", listener);
  },
  onFileSentStart: (
    callback: (data: { filename: string; fileSize: number; mimeType: string }) => void,
  ) => {
    const listener = (
      _event: Electron.IpcRendererEvent,
      value: { filename: string; fileSize: number; mimeType: string },
    ) => callback(value);
    ipcRenderer.on("file-sent-start", listener);
    return () => ipcRenderer.removeListener("file-sent-start", listener);
  },
  onFileSentComplete: (
    callback: (data: { filename: string; failed?: boolean }) => void,
  ) => {
    const listener = (
      _event: Electron.IpcRendererEvent,
      value: { filename: string; failed?: boolean },
    ) => callback(value);
    ipcRenderer.on("file-sent-complete", listener);
    return () => ipcRenderer.removeListener("file-sent-complete", listener);
  },
  getPathForFile: (file: File) => webUtils.getPathForFile(file),
  // AI Settings
  getAISettings: () => ipcRenderer.invoke("get-ai-settings"),
  saveAISettings: (settings: { apiKey?: string; provider?: string; model?: string }) =>
    ipcRenderer.invoke("save-ai-settings", settings),
  fetchModels: () => ipcRenderer.invoke("fetch-models"),
  // AI Summarize
  summarizeContent: (data: { type: string; content: string; filePath?: string; filename?: string }) =>
    ipcRenderer.invoke("summarize-content", data),
  summarizeCancel: (streamId: string) => ipcRenderer.send("summarize-cancel", streamId),
  onSummarizeChunk: (callback: (data: { streamId: string; text: string }) => void) => {
    const listener = (_event: Electron.IpcRendererEvent, value: { streamId: string; text: string }) => callback(value);
    ipcRenderer.on("summarize-chunk", listener);
    return () => ipcRenderer.removeListener("summarize-chunk", listener);
  },
  onSummarizeDone: (callback: (data: { streamId: string }) => void) => {
    const listener = (_event: Electron.IpcRendererEvent, value: { streamId: string }) => callback(value);
    ipcRenderer.on("summarize-done", listener);
    return () => ipcRenderer.removeListener("summarize-done", listener);
  },
  onSummarizeError: (callback: (data: { streamId: string; error: string }) => void) => {
    const listener = (_event: Electron.IpcRendererEvent, value: { streamId: string; error: string }) => callback(value);
    ipcRenderer.on("summarize-error", listener);
    return () => ipcRenderer.removeListener("summarize-error", listener);
  },
  // General Settings
  getSettings: () => ipcRenderer.invoke("get-settings"),
  saveSettings: (
    settings: Partial<{
      startupOnBoot: boolean;
      minimizeToTray: boolean;
      clipboardSync: string;
      soundOnMessage: boolean;
      notificationsEnabled: boolean;
      theme: string;
    }>,
  ) => ipcRenderer.invoke("save-settings", settings),
  onSettingsChanged: (callback: (settings: Record<string, unknown>) => void) => {
    const listener = (_event: Electron.IpcRendererEvent, value: Record<string, unknown>) => callback(value);
    ipcRenderer.on("settings-changed", listener);
    return () => ipcRenderer.removeListener("settings-changed", listener);
  },
  onPlayNotificationSound: (callback: () => void) => {
    const listener = () => callback();
    ipcRenderer.on("play-notification-sound", listener);
    return () => ipcRenderer.removeListener("play-notification-sound", listener);
  },
});
