import Linkify from "react-linkify";
import { type Message, MessageType, type TransferState } from "../types";
import { formatTime, formatDate } from "../utils";

interface MessageBubbleProps {
  message: Message;
  onContextMenu: (e: React.MouseEvent, message: Message) => void;
  onClick: (message: Message) => void;
  previousMessage?: Message;
}

function isTransferring(state?: TransferState): boolean {
  return state === "pending" || state === "transferring";
}

function TransferProgressBar({ message }: { message: Message }) {
  const { transferState, transferProgress = 0 } = message;
  const isSending = message.sender === "Me";
  const percent = Math.round(transferProgress);

  if (transferState === "failed") {
    return (
      <div className="transfer-failed">
        <span className="transfer-failed-icon">✕</span>
        <span>Transfer failed</span>
      </div>
    );
  }

  const label =
    transferState === "pending"
      ? isSending
        ? "Preparing..."
        : "Waiting..."
      : isSending
        ? `Sending... ${percent}%`
        : `Receiving... ${percent}%`;

  return (
    <div className="transfer-progress">
      <div className="transfer-progress-label">{label}</div>
      <div className="transfer-progress-bar-track">
        <div
          className="transfer-progress-bar-fill"
          style={{ width: `${percent}%` }}
        />
      </div>
    </div>
  );
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
            {isTransferring(message.transferState) ||
            message.transferState === "failed" ? (
              // Show filename + progress while transferring
              <>
                <div className="message-file">
                  <div className="file-icon">📷</div>
                  <div className="file-info">
                    <span className="file-name">
                      {message.filename || "Image"}
                    </span>
                  </div>
                </div>
                <TransferProgressBar message={message} />
              </>
            ) : (
              <>
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
                  <span className="message-filename">
                    {message.filename}
                  </span>
                )}
                {message.transferState === "complete" && (
                  <div className="transfer-complete-label">
                    {isMe ? "Sent" : "Received"}
                  </div>
                )}
              </>
            )}
          </div>
        );
      case MessageType.FILE:
        return (
          <div
            className="message-file"
            onClick={(e) => {
              if (!isTransferring(message.transferState)) {
                e.stopPropagation();
                onClick(message);
              }
            }}
          >
            <div className="file-icon">📄</div>
            <div className="file-info">
              <span className="file-name">{message.filename || "File"}</span>
              {isTransferring(message.transferState) ||
              message.transferState === "failed" ? (
                <TransferProgressBar message={message} />
              ) : message.transferState === "complete" ? (
                <span className="file-action">
                  {isMe ? "Sent" : "Received"} — Click to open
                </span>
              ) : (
                <span className="file-action">Click to download</span>
              )}
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
