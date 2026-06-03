import Linkify from "react-linkify";
import { type Message, MessageType } from "../types";
import { formatTime, formatDate } from "../utils";

interface MessageBubbleProps {
  message: Message;
  onContextMenu: (e: React.MouseEvent, message: Message) => void;
  onClick: (message: Message) => void;
  previousMessage?: Message;
}

export function MessageBubble({
  message,
  onContextMenu,
  onClick,
  previousMessage,
}: MessageBubbleProps) {
  const isMe = message.sender === "Me";
  const isSystem = message.sender === "System";

  // Check if we need to show day separator
  const showDaySeparator =
    !previousMessage ||
    message.timestamp.toDateString() !==
      previousMessage.timestamp.toDateString();

  // Check if we need to show timestamp (every 5 minutes gap)
  const showTimestamp = true; // Always show timestamp on every message

  if (isSystem) {
    return (
      <>
        {showDaySeparator && (
          <div className="day-separator">{formatDate(message.timestamp)}</div>
        )}
        <div className="message-system">
          <span>{message.content}</span>
        </div>
      </>
    );
  }

  const renderContent = () => {
    switch (message.type) {
      case MessageType.IMAGE:
        return (
          <div className="message-image">
            <img
              src={message.url}
              alt={message.filename || "Image"}
              onClick={(e) => {
                e.stopPropagation();
                onClick(message);
              }}
              onError={(e) => {
                const target = e.target as HTMLImageElement;
                target.style.display = "none";
                target.parentElement!.innerHTML =
                  '<div class="image-error"><span>📷</span><span>Image not available</span></div>';
              }}
            />
            {message.filename && (
              <span className="message-filename">{message.filename}</span>
            )}
          </div>
        );
      case MessageType.FILE:
        return (
          <div
            className="message-file"
            onClick={(e) => {
              e.stopPropagation();
              onClick(message);
            }}
          >
            <div className="file-icon">📄</div>
            <div className="file-info">
              <span className="file-name">{message.filename || "File"}</span>
              <span className="file-action">Click to download</span>
            </div>
          </div>
        );
      default:
        return (
          <Linkify
            componentDecorator={(
              decoratedHref: string,
              decoratedText: string,
              key: number,
            ) => (
              <a
                key={key}
                href={decoratedHref}
                onClick={(e) => {
                  e.preventDefault();
                  window.electronAPI.openExternal(decoratedHref);
                }}
                style={{ color: "inherit", textDecoration: "underline" }}
              >
                {decoratedText}
              </a>
            )}
          >
            <span className="message-text">{message.content}</span>
          </Linkify>
        );
    }
  };

  return (
    <>
      {showDaySeparator && (
        <div className="day-separator">{formatDate(message.timestamp)}</div>
      )}
      <div
        className={`message-bubble ${isMe ? "message-mine" : "message-other"}`}
        onContextMenu={(e) => onContextMenu(e, message)}
        onClick={() =>
          message.type === MessageType.TEXT ? null : onClick(message)
        }
      >
        {!isMe && <div className="message-sender">{message.sender}</div>}
        {renderContent()}
        {showTimestamp && (
          <div className="message-time">{formatTime(message.timestamp)}</div>
        )}
      </div>
    </>
  );
}
