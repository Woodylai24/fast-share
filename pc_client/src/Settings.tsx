import { useState, useEffect, useCallback } from "react";
import { useTheme } from "./contexts/ThemeContext";
import type { ThemeSetting } from "./contexts/ThemeContext";
import "./Settings.css";

interface SettingsProps {
  isOpen: boolean;
  onClose: () => void;
}

interface ModelOption {
  id: string;
  name: string;
  vision?: boolean;
}

interface GeneralSettings {
  startupOnBoot: boolean;
  minimizeToTray: boolean;
  clipboardSync: string;
  soundOnMessage: boolean;
  notificationsEnabled: boolean;
}

export function Settings({ isOpen, onClose }: SettingsProps) {
  const { theme, setTheme } = useTheme();

  // General
  const [startupOnBoot, setStartupOnBoot] = useState(false);
  const [minimizeToTray, setMinimizeToTray] = useState(false);

  // Connection
  const [clipboardSync, setClipboardSync] = useState("none");

  // Notifications
  const [soundOnMessage, setSoundOnMessage] = useState(true);
  const [notificationsEnabled, setNotificationsEnabled] = useState(true);

  // AI
  const [provider, setProvider] = useState("openrouter");
  const [apiKey, setApiKey] = useState("");
  const [showApiKey, setShowApiKey] = useState(false);
  const [apiKeySaved, setApiKeySaved] = useState(false);
  const [model, setModel] = useState("openrouter/auto");
  const [models, setModels] = useState<ModelOption[]>([]);
  const [loadingModels, setLoadingModels] = useState(false);
  const [fetchError, setFetchError] = useState<string | null>(null);
  const [hasApiKey, setHasApiKey] = useState(false);

  // Load all settings on open
  useEffect(() => {
    if (!isOpen) return;

    const loadSettings = async () => {
      try {
        const settings = await window.electronAPI.getSettings();
        setStartupOnBoot((settings.startupOnBoot as boolean) ?? false);
        setMinimizeToTray((settings.minimizeToTray as boolean) ?? false);
        setClipboardSync((settings.clipboardSync as string) ?? "none");
        setSoundOnMessage((settings.soundOnMessage as boolean) ?? true);
        setNotificationsEnabled(
          (settings.notificationsEnabled as boolean) ?? true
        );
      } catch (err) {
        console.error("Failed to load settings:", err);
      }
    };

    const loadAISettings = async () => {
      try {
        const aiSettings = await window.electronAPI.getAISettings();
        setProvider(aiSettings.provider || "openrouter");
        setModel(aiSettings.model || "openrouter/auto");
        if (aiSettings.apiKey) {
          setHasApiKey(true);
          setApiKey("••••••••");
        } else {
          setHasApiKey(false);
          setApiKey("");
        }
        setApiKeySaved(false);
        setFetchError(null);

        if (aiSettings.apiKey) {
          fetchModels();
        }
      } catch (err) {
        console.error("Failed to load AI settings:", err);
      }
    };

    loadSettings();
    loadAISettings();
  }, [isOpen]);

  // ---- Helpers for saving a single setting key ----
  const saveSetting = useCallback(
    (key: string, value: unknown) => {
      window.electronAPI.saveSettings({ [key]: value }).catch((err) => {
        console.error(`Failed to save ${key}:`, err);
      });
    },
    []
  );

  // ---- Toggle handlers ----
  const handleToggle = (
    key: keyof GeneralSettings,
    current: boolean,
    setter: (v: boolean) => void
  ) => {
    const next = !current;
    setter(next);
    saveSetting(key, next);
  };

  // ---- AI section helpers ----
  const fetchModels = useCallback(async () => {
    setLoadingModels(true);
    setFetchError(null);
    try {
      const result = await window.electronAPI.fetchModels();
      if ("error" in result) {
        setFetchError(result.error);
        setModels([]);
      } else {
        setModels(result);
      }
    } catch {
      setFetchError("Failed to fetch models");
      setModels([]);
    } finally {
      setLoadingModels(false);
    }
  }, []);

  const handleSaveApiKey = async () => {
    try {
      const keyToSave = apiKey === "••••••••" ? undefined : apiKey;
      if (keyToSave) {
        await window.electronAPI.saveAISettings({ apiKey: keyToSave });
        setHasApiKey(true);
        setApiKey("••••••••");
        setApiKeySaved(true);
        fetchModels();
      }
    } catch (err) {
      console.error("Failed to save API key:", err);
    }
  };

  const handleModelChange = async (selectedModel: string) => {
    setModel(selectedModel);
    try {
      await window.electronAPI.saveAISettings({ model: selectedModel });
    } catch (err) {
      console.error("Failed to save model:", err);
    }
  };

  const getDisplayName = (m: ModelOption) => {
    const parts = m.id.split("/");
    const shortId = parts.length > 1 ? parts.slice(1).join("/") : parts[0];
    const displayName = shortId.charAt(0).toUpperCase() + shortId.slice(1);
    const visionTag = m.vision ? " 👁" : "";
    return `${displayName} (${m.id})${visionTag}`;
  };

  // ---- Backdrop click ----
  const handleBackdropClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (e.target === e.currentTarget) {
      onClose();
    }
  };

  if (!isOpen) return null;

  return (
    <div className="settings-backdrop" onClick={handleBackdropClick}>
      <div className="settings-panel">
        {/* Header */}
        <div className="settings-header">
          <h2>Settings</h2>
          <button className="settings-close" onClick={onClose} title="Close">
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

        <div className="settings-divider" />

        {/* Scrollable content */}
        <div className="settings-body">
          {/* ─── GENERAL ─── */}
          <section className="settings-section">
            <h3 className="settings-section-title">General</h3>

            <div className="settings-row">
              <span className="settings-row-label">Startup on boot</span>
              <button
                className={`settings-toggle ${startupOnBoot ? "on" : ""}`}
                onClick={() =>
                  handleToggle(
                    "startupOnBoot",
                    startupOnBoot,
                    setStartupOnBoot
                  )
                }
                role="switch"
                aria-checked={startupOnBoot}
              >
                <span className="settings-toggle-thumb" />
              </button>
            </div>

            <div className="settings-row">
              <span className="settings-row-label">Minimize to tray</span>
              <button
                className={`settings-toggle ${minimizeToTray ? "on" : ""}`}
                onClick={() =>
                  handleToggle(
                    "minimizeToTray",
                    minimizeToTray,
                    setMinimizeToTray
                  )
                }
                role="switch"
                aria-checked={minimizeToTray}
              >
                <span className="settings-toggle-thumb" />
              </button>
            </div>
          </section>

          {/* ─── APPEARANCE ─── */}
          <section className="settings-section">
            <h3 className="settings-section-title">Appearance</h3>

            <div className="settings-theme-group">
              {(
                [
                  ["system", "System Default"],
                  ["light", "Light"],
                  ["dark", "Dark"],
                ] as [ThemeSetting, string][]
              ).map(([value, label]) => (
                <label className="settings-radio" key={value}>
                  <input
                    type="radio"
                    name="theme"
                    value={value}
                    checked={theme === value}
                    onChange={() => setTheme(value)}
                  />
                  <span className="settings-radio-label">{label}</span>
                </label>
              ))}
            </div>
          </section>

          {/* ─── CONNECTION ─── */}
          <section className="settings-section">
            <h3 className="settings-section-title">Connection</h3>

            <div className="settings-field">
              <label className="settings-label">Clipboard sync</label>
              <select
                className="settings-select"
                value={clipboardSync}
                onChange={(e) => {
                  setClipboardSync(e.target.value);
                  saveSetting("clipboardSync", e.target.value);
                }}
              >
                <option value="none">No sync</option>
                <option value="auto-message">Auto send as message</option>
                <option value="auto-sync">Auto sync</option>
              </select>
              <span className="settings-description">
                {clipboardSync === "none" &&
                  "Clipboard changes on this device will not be shared."}
                {clipboardSync === "auto-message" &&
                  "Clipboard changes will be sent as regular text messages."}
                {clipboardSync === "auto-sync" &&
                  "Clipboard changes will be sent to the other device and auto-copied."}
              </span>
            </div>
          </section>

          {/* ─── NOTIFICATIONS ─── */}
          <section className="settings-section">
            <h3 className="settings-section-title">Notifications</h3>

            <div className="settings-row">
              <span className="settings-row-label">Sound on new message</span>
              <button
                className={`settings-toggle ${soundOnMessage ? "on" : ""}`}
                onClick={() =>
                  handleToggle(
                    "soundOnMessage",
                    soundOnMessage,
                    setSoundOnMessage
                  )
                }
                role="switch"
                aria-checked={soundOnMessage}
              >
                <span className="settings-toggle-thumb" />
              </button>
            </div>

            <div className="settings-row">
              <span className="settings-row-label">Notifications</span>
              <button
                className={`settings-toggle ${notificationsEnabled ? "on" : ""}`}
                onClick={() =>
                  handleToggle(
                    "notificationsEnabled",
                    notificationsEnabled,
                    setNotificationsEnabled
                  )
                }
                role="switch"
                aria-checked={notificationsEnabled}
              >
                <span className="settings-toggle-thumb" />
              </button>
            </div>
          </section>

          {/* ─── AI ─── */}
          <section className="settings-section">
            <h3 className="settings-section-title">AI</h3>

            {/* Provider */}
            <div className="settings-field">
              <label className="settings-label">Provider</label>
              <select
                className="settings-select"
                value={provider}
                disabled
                title="Only OpenRouter is supported currently"
              >
                <option value="openrouter">OpenRouter</option>
              </select>
            </div>

            {/* API Key */}
            <div className="settings-field">
              <label className="settings-label">API Key</label>
              <div className="settings-apikey-row">
                <div className="settings-apikey-input-wrap">
                  <input
                    type={showApiKey ? "text" : "password"}
                    className="settings-input"
                    value={apiKey}
                    onChange={(e) => {
                      setApiKey(e.target.value);
                      setApiKeySaved(false);
                    }}
                    placeholder="sk-or-..."
                  />
                  <button
                    className="settings-eye-btn"
                    onClick={() => setShowApiKey(!showApiKey)}
                    title={showApiKey ? "Hide" : "Show"}
                    type="button"
                  >
                    {showApiKey ? (
                      <svg
                        viewBox="0 0 16 16"
                        width="16"
                        height="16"
                        fill="currentColor"
                      >
                        <path d="M8 3C4.5 3 1.7 5.5.5 8c1.2 2.5 4 5 7.5 5s6.3-2.5 7.5-5c-1.2-2.5-4-5-7.5-5zm0 8.5A3.5 3.5 0 1 1 11.5 8 3.5 3.5 0 0 1 8 11.5zM8 6a2 2 0 1 0 0 4 2 2 0 0 0 0-4z" />
                        <path
                          d="M1 1l14 14"
                          stroke="currentColor"
                          strokeWidth="1.5"
                          fill="none"
                        />
                      </svg>
                    ) : (
                      <svg
                        viewBox="0 0 16 16"
                        width="16"
                        height="16"
                        fill="currentColor"
                      >
                        <path d="M8 3C4.5 3 1.7 5.5.5 8c1.2 2.5 4 5 7.5 5s6.3-2.5 7.5-5c-1.2-2.5-4-5-7.5-5zm0 8.5A3.5 3.5 0 1 1 11.5 8 3.5 3.5 0 0 1 8 11.5zM8 6a2 2 0 1 0 0 4 2 2 0 0 0 0-4z" />
                      </svg>
                    )}
                  </button>
                </div>
                <button
                  className="settings-save-btn"
                  onClick={handleSaveApiKey}
                  disabled={!apiKey || apiKey === "••••••••"}
                >
                  Save
                </button>
              </div>
              {apiKeySaved && (
                <span className="settings-status">✓ Saved</span>
              )}
            </div>

            {/* Default Model */}
            <div className="settings-field">
              <label className="settings-label">Default Model</label>
              <div className="settings-model-row">
                <select
                  className="settings-select"
                  value={model}
                  onChange={(e) => handleModelChange(e.target.value)}
                  disabled={!hasApiKey || loadingModels}
                >
                  {!hasApiKey && (
                    <option value="" disabled>
                      Enter API key first
                    </option>
                  )}
                  {hasApiKey && models.length === 0 && !loadingModels && (
                    <option value="openrouter/auto">Auto (openrouter/auto)</option>
                  )}
                  {models.map((m) => (
                    <option key={m.id} value={m.id}>
                      {getDisplayName(m)}
                    </option>
                  ))}
                </select>
                <button
                  className="settings-refresh-btn"
                  onClick={fetchModels}
                  disabled={!hasApiKey || loadingModels}
                  title="Refresh model list"
                  type="button"
                >
                  ↻
                </button>
              </div>
              {loadingModels && (
                <span className="settings-loading">Loading models...</span>
              )}
              {fetchError && (
                <span className="settings-error">{fetchError}</span>
              )}
            </div>

            <span className="settings-hint">
              API key is stored locally and encrypted.
            </span>
          </section>

          {/* ─── ABOUT ─── */}
          <section className="settings-section">
            <h3 className="settings-section-title">About</h3>
            <button
              className="settings-replay-btn"
              onClick={async () => {
                await window.electronAPI.saveSettings({ onboardingComplete: false });
                window.location.reload();
              }}
            >
              Replay onboarding
            </button>
            <div className="settings-row">
              <span className="settings-row-label">Version</span>
              <span className="settings-version">1.0.0</span>
            </div>
          </section>
        </div>
      </div>
    </div>
  );
}
