import { clipboard } from "electron";
import settingsStore from "./settings-store";

// --- Clipboard Sync ---
type ClipboardSyncMode = "none" | "notify" | "auto";

let lastClipboardText = clipboard.readText();
let clipboardInterval: ReturnType<typeof setInterval> | null = null;

type SendFn = (message: object) => void;

function getClipboardSyncMode(): ClipboardSyncMode {
  return settingsStore.get("clipboardSync", "notify") as ClipboardSyncMode;
}

function startClipboardSync(sendFn: SendFn) {
  stopClipboardSync();

  const mode = getClipboardSyncMode();
  if (mode === "none") {
    console.log("[DEBUG] Clipboard sync disabled (mode: none)");
    return;
  }

  lastClipboardText = clipboard.readText();
  clipboardInterval = setInterval(() => {
    const currentText = clipboard.readText();
    if (currentText && currentText !== lastClipboardText) {
      lastClipboardText = currentText;
      if (mode === "auto") {
        sendFn({ type: "clipboard", content: currentText });
      } else {
        // 'notify' mode — send as regular text message
        sendFn({ type: "text", content: currentText });
      }
      console.log(
        `[DEBUG] Clipboard changed, broadcasting to clients (mode: ${mode})`,
      );
    }
  }, 1000);
}

function stopClipboardSync() {
  if (clipboardInterval) {
    clearInterval(clipboardInterval);
    clipboardInterval = null;
  }
}

/** Stop and restart clipboard sync with current settings */
function restartClipboardSync(sendFn: SendFn) {
  startClipboardSync(sendFn);
}

// Allow updating lastClipboardText from outside (e.g. when receiving clipboard from mobile)
function setLastClipboardText(text: string) {
  lastClipboardText = text;
}

export {
  startClipboardSync,
  stopClipboardSync,
  restartClipboardSync,
  setLastClipboardText,
  getClipboardSyncMode,
};
