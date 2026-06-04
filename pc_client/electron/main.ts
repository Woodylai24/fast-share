import { app, BrowserWindow } from "electron";
import path from "path";
import { startServers } from "./server";
import { registerIpcHandlers } from "./ipc-handlers";
import { registerAIHandlers } from "./ai-summarize";

// Enable remote debugging for VS Code to attach to Renderer
app.commandLine.appendSwitch("remote-debugging-port", "9222");

let mainWindow: BrowserWindow | null = null;

function getMainWindow() {
  return mainWindow;
}

// --- Electron Window ---
function createWindow() {
  mainWindow = new BrowserWindow({
    width: 900,
    height: 600,
    frame: false,
    transparent: false,
    backgroundColor: "#242424",
    resizable: true,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      nodeIntegration: false,
      contextIsolation: true,
    },
  });

  if (!app.isPackaged) {
    mainWindow.loadURL("http://localhost:5173");
    mainWindow.webContents.openDevTools();
  } else {
    mainWindow.loadFile(path.join(__dirname, "../dist/index.html"));
  }
}

app.whenReady().then(() => {
  const { ipcMain } = require("electron");
  registerIpcHandlers(ipcMain, getMainWindow);
  registerAIHandlers(ipcMain, getMainWindow);
  startServers({ getMainWindow });
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});
