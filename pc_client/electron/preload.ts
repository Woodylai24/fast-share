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
});
