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
          title="AI Settings"
        >
          <svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor">
            <path d="M8 4.754a3.246 3.246 0 1 0 0 6.492 3.246 3.246 0 0 0 0-6.492zM5.754 8a2.246 2.246 0 1 1 4.492 0 2.246 2.246 0 0 1-4.492 0z"/>
            <path d="M9.796 1.343a.5.5 0 0 1-.57.421 3.6 3.6 0 0 0-2.452 0 .5.5 0 0 1-.57-.421l-.338-1.677a.5.5 0 0 0-.611-.372 6.5 6.5 0 0 0-2.49 1.44.5.5 0 0 0-.076.72l1.084 1.324a.5.5 0 0 1-.057.721 3.6 3.6 0 0 0-1.226 2.125.5.5 0 0 1-.47.417l-1.693.139a.5.5 0 0 0-.455.5 6.5 6.5 0 0 0 .42 2.87.5.5 0 0 0 .614.338l1.617-.496a.5.5 0 0 1 .664.322 3.6 3.6 0 0 0 1.226 1.226.5.5 0 0 1 .322.664l-.496 1.617a.5.5 0 0 0 .338.614 6.5 6.5 0 0 0 2.87.42.5.5 0 0 0 .5-.455l.139-1.693a.5.5 0 0 1 .417-.47 3.6 3.6 0 0 0 2.125-1.226.5.5 0 0 1 .721-.057l1.324 1.084a.5.5 0 0 0 .72-.076 6.5 6.5 0 0 0 1.44-2.49.5.5 0 0 0-.372-.611l-1.677-.338a.5.5 0 0 1-.421-.57 3.6 3.6 0 0 0 0-2.452.5.5 0 0 1 .421-.57l1.677-.338a.5.5 0 0 0 .372-.611 6.5 6.5 0 0 0-1.44-2.49.5.5 0 0 0-.72-.076l-1.324 1.084a.5.5 0 0 1-.721-.057 3.6 3.6 0 0 0-2.125-1.226.5.5 0 0 1-.417-.47l-.139-1.693a.5.5 0 0 0-.5-.455 6.5 6.5 0 0 0-2.87.42.5.5 0 0 0-.338.614l.496 1.617a.5.5 0 0 1-.322.664 3.6 3.6 0 0 0-1.226 1.226.5.5 0 0 1-.664.322l-1.617-.496a.5.5 0 0 0-.614.338 6.5 6.5 0 0 0-.42 2.87.5.5 0 0 0 .455.5l1.693.139a.5.5 0 0 1 .47.417 3.6 3.6 0 0 0 1.226 2.125.5.5 0 0 1 .057.721l-1.084 1.324a.5.5 0 0 0 .076.72 6.5 6.5 0 0 0 2.49 1.44.5.5 0 0 0 .611-.372l.338-1.677z"/>
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
