import { app, BrowserWindow } from "electron";
import path from "path";
import { startServers } from "./server";
import { registerIpcHandlers } from "./ipc-handlers";
import { registerAIHandlers } from "./ai-summarize";
import { createTray, shouldMinimizeToTray } from "./tray";
import settingsStore from "./settings-store";

// Enable remote debugging for VS Code to attach to Renderer
app.commandLine.appendSwitch("remote-debugging-port", "9222");

let mainWindow: BrowserWindow | null = null;

function getMainWindow() {
  return mainWindow;
}

// --- Electron Window ---
function createWindow() {
  mainWindow = new BrowserWindow({
    width: 800,
    height: 600,
    frame: false,
    transparent: false,
    backgroundColor: "#242424",
    resizable: true,
    icon: path.join(__dirname, "../public/icon.ico"),
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

  mainWindow.on("close", (event) => {
    if (shouldMinimizeToTray()) {
      event.preventDefault();
      mainWindow!.hide();
    }
  });
}

app.whenReady().then(() => {
  const { ipcMain } = require("electron");
  startServers({ getMainWindow });

  const { restartClipboardSync } = require("./clipboard-sync") as typeof import("./clipboard-sync");
  const { sendEncryptedToClients } = require("./server") as typeof import("./server");
  registerIpcHandlers(ipcMain, getMainWindow, {
    onClipboardSettingChanged: () => {
      restartClipboardSync((message: object) => sendEncryptedToClients(message));
    },
  });
  registerAIHandlers(ipcMain, getMainWindow);
  createWindow();
  createTray(getMainWindow);

  // Startup on boot
  const startupOnBoot = settingsStore.get("startupOnBoot", false) as boolean;
  app.setLoginItemSettings({ openAtLogin: startupOnBoot });

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
