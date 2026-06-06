import { useState, useEffect } from "react";
import "./TitleBar.css";

interface TitleBarProps {
  onSettingsClick?: () => void;
}

export function TitleBar({ onSettingsClick }: TitleBarProps) {
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
