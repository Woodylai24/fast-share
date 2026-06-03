import { useEffect, useRef } from "react";
import { type Message, MessageType } from "../types";

interface ContextMenuProps {
  x: number;
  y: number;
  message: Message;
  onClose: () => void;
  onCopy: (message: Message) => void;
  onDelete: (message: Message) => void;
  onOpen: (message: Message) => void;
  onSummarize: (message: Message) => void;
  hasApiKey: boolean;
}

export function ContextMenu({
  x,
  y,
  message,
  onClose,
  onCopy,
  onDelete,
  onOpen,
  onSummarize,
  hasApiKey,
}: ContextMenuProps) {
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        onClose();
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, [onClose]);

  return (
    <div
      ref={menuRef}
      className="context-menu"
      style={{ top: y, left: x }}
      onClick={(e) => e.stopPropagation()}
    >
      {(message.type === MessageType.FILE ||
        message.type === MessageType.IMAGE) &&
        message.url && (
          <button
            className="context-menu-item"
            onClick={() => {
              onOpen(message);
              onClose();
            }}
          >
            🔗 Open
          </button>
        )}
      {message.type === MessageType.TEXT && (
        <button
          className="context-menu-item"
          onClick={() => {
            onCopy(message);
            onClose();
          }}
        >
          📋 Copy
        </button>
      )}
      <button
        className="context-menu-item"
        disabled={!hasApiKey}
        title={!hasApiKey ? "Set up API key in Settings" : undefined}
        onClick={() => {
          onSummarize(message);
          onClose();
        }}
      >
        🤖 Summarize
      </button>
      <button
        className="context-menu-item delete"
        onClick={() => {
          onDelete(message);
          onClose();
        }}
      >
        🗑️ Delete
      </button>
    </div>
  );
}
