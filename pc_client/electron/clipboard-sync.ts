import { clipboard } from "electron";

// --- Clipboard Sync ---
let lastClipboardText = clipboard.readText();
let clipboardInterval: ReturnType<typeof setInterval> | null = null;

type SendFn = (message: object) => void;

function startClipboardSync(sendFn: SendFn) {
  lastClipboardText = clipboard.readText();
  clipboardInterval = setInterval(() => {
    const currentText = clipboard.readText();
    if (currentText && currentText !== lastClipboardText) {
      lastClipboardText = currentText;
      sendFn({ type: "clipboard", content: currentText });
      console.log("[DEBUG] Clipboard changed, broadcasting to clients (encrypted)");
    }
  }, 1000);
}

function stopClipboardSync() {
  if (clipboardInterval) {
    clearInterval(clipboardInterval);
    clipboardInterval = null;
  }
}

// Allow updating lastClipboardText from outside (e.g. when receiving clipboard from mobile)
function setLastClipboardText(text: string) {
  lastClipboardText = text;
}

export { startClipboardSync, stopClipboardSync, setLastClipboardText };
