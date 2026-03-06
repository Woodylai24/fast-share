import { useState, useEffect } from "react";
import "./TitleBar.css";

export function TitleBar() {
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
