import { useState, useEffect } from "react";
import "./TitleBar.css";

interface TitleBarProps {
  onSettingsClick?: () => void;
  onQrClick?: () => void;
  onUploadClick?: () => void;
}

export function TitleBar({ onSettingsClick, onQrClick, onUploadClick }: TitleBarProps) {
  const [isMaximized, setIsMaximized] = useState(false);

  useEffect(() => {
    // Check initial maximize state
    window.electronAPI.windowIsMaximized().then((maximized) => {
      setIsMaximized(maximized);
    });
  }, []);

  const handleMinimize = () => {
    window.electronAPI.windowMinimize();
  };

  const handleMaximize = () => {
    window.electronAPI.windowMaximize();
    setIsMaximized(!isMaximized);
  };

  const handleClose = () => {
    window.electronAPI.windowClose();
  };

  return (
    <div className="title-bar">
      <div className="title-bar-drag-area">
        <span className="title-bar-title">Fast Share</span>
      </div>
      <div className="title-bar-actions">
        {onUploadClick && (
          <button
            className="title-bar-button upload"
            onClick={onUploadClick}
            title="Upload File"
          >
            <svg viewBox="0 0 20 20" width="14" height="14" fill="currentColor">
              <path d="M10 15a1 1 0 0 0-1-1V5.414L6.707 7.707a1 1 0 0 1-1.414-1.414l4-4a1 1 0 0 1 1.414 0l4 4a1 1 0 0 1-1.414 1.414L11 5.414V14a1 1 0 0 1-1 1zM4 15a1 1 0 0 1 1 1v1h10v-1a1 1 0 1 1 2 0v2a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-2a1 1 0 0 1 1-1z"/>
            </svg>
          </button>
        )}
        {onQrClick && (
          <button
            className="title-bar-button qr"
            onClick={onQrClick}
            title="Pair Device / QR Code"
          >
            <svg viewBox="0 0 20 20" width="14" height="14" fill="currentColor">
              <path d="M2 2h6v6H2V2zm2 2v2h2V4H4zm8-2h6v6h-6V2zm2 2v2h2V4h-2zM2 12h6v6H2v-6zm2 2v2h2v-2H4zm8-2h2v2h-2v-2zm2 2h2v2h-2v-2zm-2 2h2v2h-2v-2zm4-2h2v2h-2v-2zm0 2h2v2h-2v-2z"/>
            </svg>
          </button>
        )}
        <button
          className="title-bar-button folder"
          onClick={() => window.electronAPI.openFolder()}
          title="Open FastShare Folder"
        >
          <svg viewBox="0 0 20 20" width="14" height="14" fill="currentColor">
            <path d="M2 4a2 2 0 012-2h4l2 2h6a2 2 0 012 2v10a2 2 0 01-2 2H4a2 2 0 01-2-2V4z"/>
          </svg>
        </button>
        <button
          className="title-bar-button settings"
          onClick={onSettingsClick}
          title="Settings"
        >
          <svg viewBox="0 0 20 20" width="14" height="14" fill="currentColor">
            <path d="M10 13a3 3 0 1 0 0-6 3 3 0 0 0 0 6zm0-2a1 1 0 1 1 0-2 1 1 0 0 1 0 2z"/>
            <path d="M17.3 8.3l-1.2-.2c-.1-.3-.2-.5-.4-.8l.7-1a.5.5 0 0 0-.1-.7l-1.9-1.9a.5.5 0 0 0-.7-.1l-1 .7c-.3-.2-.5-.3-.8-.4l-.2-1.2a.5.5 0 0 0-.5-.4H9.6a.5.5 0 0 0-.5.4l-.2 1.2c-.3.1-.5.2-.8.4l-1-.7a.5.5 0 0 0-.7.1L4.5 5.7a.5.5 0 0 0-.1.7l.7 1c-.2.3-.3.5-.4.8l-1.2.2a.5.5 0 0 0-.4.5v2.7c0 .2.2.4.4.5l1.2.2c.1.3.2.5.4.8l-.7 1a.5.5 0 0 0 .1.7l1.9 1.9c.2.2.5.2.7.1l1-.7c.3.2.5.3.8.4l.2 1.2c0 .2.2.4.5.4h2.7c.2 0 .4-.2.5-.4l.2-1.2c.3-.1.5-.2.8-.4l1 .7c.2.2.5.1.7-.1l1.9-1.9c.2-.2.2-.5.1-.7l-.7-1c.2-.3.3-.5.4-.8l1.2-.2c.2 0 .4-.2.4-.5V8.8c0-.3-.2-.5-.4-.5zM10 15a5 5 0 1 1 0-10 5 5 0 0 1 0 10z"/>
          </svg>
        </button>
      </div>
      <div className="title-bar-controls">
        <button
          className="title-bar-button minimize"
          onClick={handleMinimize}
          title="Minimize"
        >
          <svg viewBox="0 0 12 12" width="12" height="12">
            <rect width="10" height="1" x="1" y="6" fill="currentColor" />
          </svg>
        </button>
        <button
          className="title-bar-button maximize"
          onClick={handleMaximize}
          title={isMaximized ? "Restore" : "Maximize"}
        >
          {isMaximized ? (
            <svg viewBox="0 0 12 12" width="12" height="12">
              <rect
                width="7"
                height="7"
                x="1"
                y="4"
                fill="none"
                stroke="currentColor"
                strokeWidth="1"
              />
              <rect width="7" height="7" x="4" y="1" fill="currentColor" />
            </svg>
          ) : (
            <svg viewBox="0 0 12 12" width="12" height="12">
              <rect
                width="9"
                height="9"
                x="1.5"
                y="1.5"
                fill="none"
                stroke="currentColor"
                strokeWidth="1"
              />
            </svg>
          )}
        </button>
        <button
          className="title-bar-button close"
          onClick={handleClose}
          title="Close"
        >
          <svg viewBox="0 0 12 12" width="12" height="12">
            <path
              d="M 2 2 L 10 10 M 10 2 L 2 10"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.5"
            />
          </svg>
        </button>
      </div>
    </div>
  );
}
