import { useState, useEffect, useCallback } from "react";
import "./AISettings.css";

interface AISettingsProps {
  isOpen: boolean;
  onClose: () => void;
}

interface ModelOption {
  id: string;
  name: string;
}

export function AISettings({ isOpen, onClose }: AISettingsProps) {
  const [provider, setProvider] = useState("openrouter");
  const [apiKey, setApiKey] = useState("");
  const [showApiKey, setShowApiKey] = useState(false);
  const [apiKeySaved, setApiKeySaved] = useState(false);
  const [model, setModel] = useState("openrouter/auto");
  const [models, setModels] = useState<ModelOption[]>([]);
  const [loadingModels, setLoadingModels] = useState(false);
  const [fetchError, setFetchError] = useState<string | null>(null);
  const [hasApiKey, setHasApiKey] = useState(false);

  // Load settings on open
  useEffect(() => {
    if (!isOpen) return;
    const loadSettings = async () => {
      try {
        const settings = await window.electronAPI.getAISettings();
        setProvider(settings.provider || "openrouter");
        setModel(settings.model || "openrouter/auto");
        if (settings.apiKey) {
          setHasApiKey(true);
          setApiKey("••••••••");
        } else {
          setHasApiKey(false);
          setApiKey("");
        }
        setApiKeySaved(false);
        setFetchError(null);

        // Auto-fetch models if API key exists
        if (settings.apiKey) {
          fetchModels();
        }
      } catch (err) {
        console.error("Failed to load AI settings:", err);
      }
    };
    loadSettings();
  }, [isOpen]);

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
    } catch (err) {
      setFetchError("Failed to fetch models");
      setModels([]);
    } finally {
      setLoadingModels(false);
    }
  }, []);

  const handleSaveApiKey = async () => {
    try {
      // Don't save the masked placeholder
      const keyToSave = apiKey === "••••••••" ? undefined : apiKey;
      if (keyToSave) {
        await window.electronAPI.saveAISettings({ apiKey: keyToSave });
        setHasApiKey(true);
        setApiKey("••••••••");
        setApiKeySaved(true);
        // Auto-fetch models after saving API key
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

  const handleBackdropClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (e.target === e.currentTarget) {
      onClose();
    }
  };

  if (!isOpen) return null;

  const getDisplayName = (m: ModelOption) => {
    // Extract short name from id: "openai/gpt-4o" -> "GPT-4o"
    const parts = m.id.split("/");
    const shortId = parts.length > 1 ? parts.slice(1).join("/") : parts[0];
    // Capitalize first letter
    const displayName = shortId.charAt(0).toUpperCase() + shortId.slice(1);
    return `${displayName} (${m.id})`;
  };

  return (
    <div className="ai-settings-backdrop" onClick={handleBackdropClick}>
      <div className="ai-settings-panel">
        <div className="ai-settings-header">
          <h2>AI Settings</h2>
          <button className="ai-settings-close" onClick={onClose} title="Close">
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

        <div className="ai-settings-divider" />

        <div className="ai-settings-body">
          {/* Provider */}
          <div className="ai-settings-field">
            <label className="ai-settings-label">Provider</label>
            <select
              className="ai-settings-select"
              value={provider}
              disabled
              title="Only OpenRouter is supported currently"
            >
              <option value="openrouter">OpenRouter</option>
            </select>
          </div>

          {/* API Key */}
          <div className="ai-settings-field">
            <label className="ai-settings-label">API Key</label>
            <div className="ai-settings-apikey-row">
              <div className="ai-settings-apikey-input-wrap">
                <input
                  type={showApiKey ? "text" : "password"}
                  className="ai-settings-input"
                  value={apiKey}
                  onChange={(e) => {
                    setApiKey(e.target.value);
                    setApiKeySaved(false);
                  }}
                  placeholder="sk-or-..."
                />
                <button
                  className="ai-settings-eye-btn"
                  onClick={() => setShowApiKey(!showApiKey)}
                  title={showApiKey ? "Hide" : "Show"}
                  type="button"
                >
                  {showApiKey ? (
                    <svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor">
                      <path d="M8 3C4.5 3 1.7 5.5.5 8c1.2 2.5 4 5 7.5 5s6.3-2.5 7.5-5c-1.2-2.5-4-5-7.5-5zm0 8.5A3.5 3.5 0 1 1 11.5 8 3.5 3.5 0 0 1 8 11.5zM8 6a2 2 0 1 0 0 4 2 2 0 0 0 0-4z"/>
                      <path d="M1 1l14 14" stroke="currentColor" strokeWidth="1.5" fill="none"/>
                    </svg>
                  ) : (
                    <svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor">
                      <path d="M8 3C4.5 3 1.7 5.5.5 8c1.2 2.5 4 5 7.5 5s6.3-2.5 7.5-5c-1.2-2.5-4-5-7.5-5zm0 8.5A3.5 3.5 0 1 1 11.5 8 3.5 3.5 0 0 1 8 11.5zM8 6a2 2 0 1 0 0 4 2 2 0 0 0 0-4z"/>
                    </svg>
                  )}
                </button>
              </div>
              <button
                className="ai-settings-save-btn"
                onClick={handleSaveApiKey}
                disabled={!apiKey || apiKey === "••••••••"}
              >
                Save
              </button>
            </div>
            {apiKeySaved && (
              <span className="ai-settings-status">✓ Saved</span>
            )}
          </div>

          {/* Default Model */}
          <div className="ai-settings-field">
            <label className="ai-settings-label">Default Model</label>
            <div className="ai-settings-model-row">
              <select
                className="ai-settings-select"
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
                className="ai-settings-refresh-btn"
                onClick={fetchModels}
                disabled={!hasApiKey || loadingModels}
                title="Refresh model list"
                type="button"
              >
                ↻
              </button>
            </div>
            {loadingModels && (
              <span className="ai-settings-loading">Loading models...</span>
            )}
            {fetchError && (
              <span className="ai-settings-error">{fetchError}</span>
            )}
          </div>
        </div>

        <div className="ai-settings-divider" />

        <div className="ai-settings-footer">
          <span>API key is stored locally and encrypted.</span>
        </div>
      </div>
    </div>
  );
}
