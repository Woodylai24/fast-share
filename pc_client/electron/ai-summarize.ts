import { ipcMain, safeStorage } from "electron";
import path from "path";
import fs from "fs";
import os from "os";
import crypto from "crypto";
import { CryptoManager } from "./crypto";
import { getMimeType } from "./file-transfer";

// eslint-disable-next-line @typescript-eslint/no-require-imports
const ElectronStore = require("electron-store").default;
// eslint-disable-next-line @typescript-eslint/no-require-imports
const pdfParse = require("pdf-parse");
// eslint-disable-next-line @typescript-eslint/no-require-imports
const mammoth = require("mammoth");

// --- Active Summarize Streams ---
const activeSummarizeStreams = new Map<string, AbortController>();

// Supported text file extensions for summarization
const SUMMARIZABLE_EXTENSIONS = new Set([
  ".txt", ".md", ".json", ".csv", ".log", ".xml", ".yaml", ".yml", ".ini", ".conf",
  ".cfg", ".toml", ".env", ".sh", ".bat", ".py", ".js", ".ts", ".html", ".css",
  ".sql", ".rb", ".go", ".rs", ".java", ".c", ".cpp", ".h", ".hpp", ".tsx",
  ".jsx", ".vue", ".svelte", ".dart", ".php", ".r", ".swift", ".kt",
  ".pdf", ".docx",
]);

const IMAGE_EXTENSIONS = new Set([
  ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".svg",
]);

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const aiSettingsStore: { get: (key: string) => any; set: (key: string, value: any) => void } = new ElectronStore({
  name: "fastshare-ai-settings",
  defaults: {
    apiKeyEncrypted: "",
    provider: "openrouter",
    model: "openrouter/auto",
  },
}) as any;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type GetMainWindowFn = () => any;

function registerAIHandlers(ipcMainInstance: typeof ipcMain, getMainWindow: GetMainWindowFn) {
  // --- fetch-models IPC handler ---
  ipcMainInstance.handle("fetch-models", async () => {
    try {
      // Decrypt API key if available
      const apiKeyEncrypted = aiSettingsStore.get("apiKeyEncrypted") as string;
      let apiKey = "";
      if (apiKeyEncrypted) {
        if (safeStorage.isEncryptionAvailable()) {
          try {
            apiKey = safeStorage.decryptString(Buffer.from(apiKeyEncrypted, "base64"));
          } catch {
            // Fallback: might be stored as plaintext
            apiKey = apiKeyEncrypted;
          }
        } else {
          apiKey = apiKeyEncrypted;
        }
      }

      const headers: Record<string, string> = {
        "Content-Type": "application/json",
      };
      if (apiKey) {
        headers["Authorization"] = `Bearer ${apiKey}`;
      }

      const response = await fetch("https://openrouter.ai/api/v1/models", {
        method: "GET",
        headers,
      });

      if (!response.ok) {
        return { error: `Failed to fetch models (HTTP ${response.status})` };
      }

      const data = await response.json();
      const models = (data.data || []).map(
        (m: { id: string; name?: string; architecture?: { input_modalities?: string[]; modality?: string } }) => {
          const inputModalities = m.architecture?.input_modalities || [];
          const modality = m.architecture?.modality || "";
          const hasVision = inputModalities.includes("image") || modality.includes("image");
          return {
            id: m.id,
            name: m.name || m.id,
            vision: hasVision,
          };
        }
      ).sort((a: { id: string }, b: { id: string }) => a.id.localeCompare(b.id));

      return models;
    } catch (error) {
      console.error("[AI Settings] Failed to fetch models:", error);
      return { error: "Failed to fetch models from OpenRouter" };
    }
  });

  // --- summarize-content IPC handler ---
  ipcMainInstance.handle("summarize-content", async (_event, data: { type: string; content: string; filename?: string; filePath?: string }) => {
    try {
      // Decrypt API key
      const apiKeyEncrypted = aiSettingsStore.get("apiKeyEncrypted") as string;
      let apiKey = "";
      if (apiKeyEncrypted) {
        if (safeStorage.isEncryptionAvailable()) {
          try {
            apiKey = safeStorage.decryptString(Buffer.from(apiKeyEncrypted, "base64"));
          } catch {
            apiKey = apiKeyEncrypted;
          }
        } else {
          apiKey = apiKeyEncrypted;
        }
      }

      if (!apiKey) {
        return { error: "no-api-key" };
      }

      const model = (aiSettingsStore.get("model") as string) || "openrouter/auto";

      // Prepare content — text or multimodal
      let textContent: string | null = null;
      let imageContent: { type: string; image_url: { url: string } } | null = null;

      if (data.type === "text") {
        textContent = data.content;
      } else {
        // File type — check extension
        const filename = data.filename || "";
        const ext = path.extname(filename).toLowerCase();
        const isImage = IMAGE_EXTENSIONS.has(ext);

        if (!SUMMARIZABLE_EXTENSIONS.has(ext) && !isImage) {
          return { error: "unsupported-type" };
        }

        // Resolve file path: prefer filePath from renderer, else ~/FastShare/<filename>
        const filePath = data.filePath || path.join(os.homedir(), "FastShare", filename);
        if (!fs.existsSync(filePath)) {
          return { error: "File not found: " + filename };
        }

        if (ext === ".pdf") {
          try {
            const fileBuffer = fs.readFileSync(filePath);
            const pdfData = await pdfParse(fileBuffer);
            let extracted = pdfData.text || "";
            if (!extracted.trim()) {
              return { error: "Could not extract text from PDF — it may be a scanned/image-based PDF" };
            }
            const MAX_BYTES = 100 * 1024;
            if (Buffer.byteLength(extracted, "utf-8") > MAX_BYTES) {
              extracted = extracted.substring(0, MAX_BYTES) + "\n\n[Content truncated, showing first 100KB]";
            }
            textContent = extracted;
          } catch (pdfErr) {
            console.error("[Summarize] PDF parse error:", pdfErr);
            return { error: "Could not extract text from PDF" };
          }
        } else if (ext === ".docx") {
          try {
            const result = await mammoth.extractRawText({ path: filePath });
            let extracted = result.value || "";
            const MAX_BYTES = 100 * 1024;
            if (Buffer.byteLength(extracted, "utf-8") > MAX_BYTES) {
              extracted = extracted.substring(0, MAX_BYTES) + "\n\n[Content truncated, showing first 100KB]";
            }
            textContent = extracted;
          } catch {
            return { error: "Could not extract text from DOCX" };
          }
        } else if (isImage) {
          // Check if model supports vision
          try {
            const headers: Record<string, string> = { "Content-Type": "application/json" };
            if (apiKey) headers["Authorization"] = `Bearer ${apiKey}`;
            const modelsResp = await fetch("https://openrouter.ai/api/v1/models", { headers });
            if (modelsResp.ok) {
              const modelsData = await modelsResp.json();
              const modelObj = (modelsData.data || []).find(
                (m: { id: string }) => m.id === model
              );
              if (modelObj) {
                const inputModalities: string[] = modelObj.architecture?.input_modalities || [];
                const modality: string = modelObj.architecture?.modality || "";
                const hasVision = inputModalities.includes("image") || modality.includes("image");
                if (!hasVision) {
                  return { error: "model-unsupported" };
                }
              }
              // If model not found in list, allow attempt (e.g. openrouter/auto)
            }
          } catch {
            // If model list fetch fails, allow attempt
          }

          const fileBuffer = fs.readFileSync(filePath);
          const base64Data = fileBuffer.toString("base64");
          const mimeType = getMimeType(filename);
          imageContent = {
            type: "image_url",
            image_url: { url: `data:${mimeType};base64,${base64Data}` },
          };
        } else {
          // Plain text file
          const stat = fs.statSync(filePath);
          let fileContent = fs.readFileSync(filePath, "utf-8");
          const MAX_BYTES = 100 * 1024;
          if (stat.size > MAX_BYTES) {
            fileContent = fileContent.substring(0, MAX_BYTES) + "\n\n[Content truncated, showing first 100KB]";
          }
          textContent = fileContent;
        }
      }

      // Generate stream ID
      const streamId = crypto.randomUUID();
      const abortController = new AbortController();
      activeSummarizeStreams.set(streamId, abortController);

      // Make streaming request to OpenRouter (fire and forget — we handle response async)
      (async () => {
        try {
          const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
            method: "POST",
            headers: {
              "Authorization": `Bearer ${apiKey}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              model,
              messages: [{
                role: "user",
                content: imageContent
                  ? [{ type: "text", text: "Summarize the following image concisely:" }, imageContent]
                  : "Summarize the following content concisely:\n\n" + textContent,
              }],
              stream: true,
            }),
            signal: abortController.signal,
          });

          if (!response.ok) {
            const errText = await response.text();
            getMainWindow()?.webContents.send("summarize-error", { streamId, error: `API error (${response.status}): ${errText}` });
            activeSummarizeStreams.delete(streamId);
            return;
          }

          const reader = response.body?.getReader();
          if (!reader) {
            getMainWindow()?.webContents.send("summarize-error", { streamId, error: "No response body" });
            activeSummarizeStreams.delete(streamId);
            return;
          }

          const decoder = new TextDecoder();
          let buffer = "";

          while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            buffer += decoder.decode(value, { stream: true });
            const lines = buffer.split("\n");
            buffer = lines.pop() || ""; // keep incomplete line

            for (const line of lines) {
              const trimmed = line.trim();
              if (!trimmed || !trimmed.startsWith("data: ")) continue;

              const jsonStr = trimmed.slice(6);
              if (jsonStr === "[DONE]") {
                getMainWindow()?.webContents.send("summarize-done", { streamId });
                activeSummarizeStreams.delete(streamId);
                return;
              }

              try {
                const parsed = JSON.parse(jsonStr);
                const text = parsed.choices?.[0]?.delta?.content;
                if (text) {
                  getMainWindow()?.webContents.send("summarize-chunk", { streamId, text });
                }
              } catch {
                // Skip malformed JSON lines
              }
            }
          }

          // Stream ended without [DONE]
          getMainWindow()?.webContents.send("summarize-done", { streamId });
          activeSummarizeStreams.delete(streamId);
        } catch (err: unknown) {
          if ((err as Error).name === "AbortError") {
            // Cancelled — clean up silently
          } else {
            getMainWindow()?.webContents.send("summarize-error", { streamId, error: `Network error: ${(err as Error).message}` });
          }
          activeSummarizeStreams.delete(streamId);
        }
      })();

      return { streamId };
    } catch (error) {
      console.error("[Summarize] Error:", error);
      return { error: `Failed to start summarization: ${(error as Error).message}` };
    }
  });

  ipcMainInstance.on("summarize-cancel", (_event, streamId: string) => {
    const controller = activeSummarizeStreams.get(streamId);
    if (controller) {
      controller.abort();
      activeSummarizeStreams.delete(streamId);
    }
  });
}

export { registerAIHandlers, aiSettingsStore };
