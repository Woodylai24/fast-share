import { Tray, Menu, nativeImage, app, BrowserWindow } from "electron";
import path from "path";
import settingsStore from "./settings-store";

let tray: Tray | null = null;
let isQuitting = false;

export function shouldQuit(): boolean {
  return isQuitting;
}

export function createTray(getMainWindowFn: () => BrowserWindow | null) {
  const iconPath = path.join(__dirname, "../public/icon.ico");
  const icon = nativeImage.createFromPath(iconPath);

  tray = new Tray(icon);
  tray.setToolTip("Fast Share");

  const contextMenu = Menu.buildFromTemplate([
    {
      label: "Open",
      click: () => {
        const win = getMainWindowFn();
        if (win) {
          win.show();
          win.focus();
        }
      },
    },
    { type: "separator" },
    {
      label: "Quit",
      click: () => {
        isQuitting = true;
        app.quit();
      },
    },
  ]);

  tray.setContextMenu(contextMenu);

  tray.on("double-click", () => {
    const win = getMainWindowFn();
    if (win) {
      win.show();
      win.focus();
    }
  });
}

export function shouldMinimizeToTray(): boolean {
  return !isQuitting && settingsStore.get("minimizeToTray", false) as boolean;
}
