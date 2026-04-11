import { useState, useEffect, useRef } from "react";
import "./SummaryPopup.css";

interface Message {
  type: string;
  content: string;
  filename?: string;
}

interface SummaryPopupProps {
  isOpen: boolean;
  message: Message | null;
  onClose: () => void;
}

export function SummaryPopup({ isOpen, message, onClose }: SummaryPopupProps) {
  const [text, setText] = useState("");
  const [isStreaming, setIsStreaming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [model, setModel] = useState<string>("");
  const streamIdRef = useRef<string | null>(null);
  const contentRef = useRef<HTMLDivElement>(null);

  // Cleanup listeners on unmount or close
  useEffect(() => {
    if (!isOpen) {
      setText("");
      setIsStreaming(false);
      setError(null);
      setModel("");
      streamIdRef.current = null;
      return;
    }

    if (!message) return;

    // Start summarization
    setText("");
    setError(null);
    setIsStreaming(true);

    let cleanupChunk: (() => void) | undefined;
    let cleanupDone: (() => void) | undefined;
    let cleanupError: (() => void) | undefined;

    (async () => {
      // Get current model for display
      try {
        const settings = await window.electronAPI.getAISettings();
        if (settings.model) setModel(settings.model);
      } catch { /* ignore */ }

      const result = await window.electronAPI.summarizeContent({
        type: message.type,
        content: message.content,
        filename: message.filename,
      });

      if ("error" in result) {
        if (result.error === "no-api-key") {
          setError("Please set up your OpenRouter API key in ⚙️ Settings");
        } else if (result.error === "unsupported-type") {
          setError("This file type is not yet supported for summarization.");
        } else if (result.error === "model-unsupported") {
          setError("Current model does not support image input. Please select a vision-capable model.");
        } else {
          setError(result.error);
        }
        setIsStreaming(false);
        return;
      }

      streamIdRef.current = result.streamId;

      cleanupChunk = window.electronAPI.onSummarizeChunk((data) => {
        if (data.streamId === streamIdRef.current) {
          setText((prev) => prev + data.text);
        }
      });

      cleanupDone = window.electronAPI.onSummarizeDone((data) => {
        if (data.streamId === streamIdRef.current) {
          setIsStreaming(false);
          streamIdRef.current = null;
        }
      });

      cleanupError = window.electronAPI.onSummarizeError((data) => {
        if (data.streamId === streamIdRef.current) {
          setError(data.error);
          setIsStreaming(false);
          streamIdRef.current = null;
        }
      });
    })();

    return () => {
      cleanupChunk?.();
      cleanupDone?.();
      cleanupError?.();
    };
  }, [isOpen, message]);

  // Auto-scroll content
  useEffect(() => {
    if (contentRef.current) {
      contentRef.current.scrollTop = contentRef.current.scrollHeight;
    }
  }, [text]);

  const handleCancel = () => {
    if (streamIdRef.current) {
      window.electronAPI.summarizeCancel(streamIdRef.current);
      streamIdRef.current = null;
    }
    setIsStreaming(false);
  };

  if (!isOpen) return null;

  // Determine subtitle based on type
  const isImage = message?.filename ? /\.(jpg|jpeg|png|gif|webp|bmp|svg)$/i.test(message.filename) : false;
  const subtitle = message?.filename
    ? (isImage ? `📷 ${message.filename}` : `📄 ${message.filename}`)
    : (message?.type === "text" ? "Clipboard Text" : "Content");

  return (
    <div className="summary-backdrop" onClick={onClose}>
      <div className="summary-modal" onClick={(e) => e.stopPropagation()}>
        <div className="summary-header">
          <div className="summary-title-section">
            <h3>🤖 AI Summary</h3>
            {model && <span className="summary-model">Using: {model}</span>}
          </div>
          <button className="summary-close" onClick={onClose}>✕</button>
        </div>
        <div className="summary-subtitle">{subtitle}</div>
        <div className="summary-content" ref={contentRef}>
          {error ? (
            <div className="summary-error">⚠️ {error}</div>
          ) : text ? (
            <span className={`summary-text ${isStreaming ? "streaming" : ""}`}>
              {text}
            </span>
          ) : isStreaming ? (
            <div className="summary-loading">
              <span className="loading-dots">Analyzing</span>
            </div>
          ) : null}
        </div>
        {isStreaming && (
          <div className="summary-footer">
            <button className="summary-cancel-btn" onClick={handleCancel}>
              Cancel
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
