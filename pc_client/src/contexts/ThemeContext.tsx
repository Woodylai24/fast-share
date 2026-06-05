import React, {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from 'react';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** User-facing theme preference. 'system' defers to the OS. */
export type ThemeSetting = 'light' | 'dark' | 'system';

/** The resolved theme that is actually applied to the DOM. */
export type ResolvedTheme = 'light' | 'dark';

interface ThemeContextValue {
  /** The stored preference – may be 'system'. */
  theme: ThemeSetting;
  /** Persist a new preference to electron-store & update state. */
  setTheme: (theme: ThemeSetting) => void;
  /** The computed theme applied to the document ('light' | 'dark'). */
  resolvedTheme: ResolvedTheme;
}

// ---------------------------------------------------------------------------
// Context
// ---------------------------------------------------------------------------

const ThemeContext = createContext<ThemeContextValue | undefined>(undefined);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Detect the OS colour-scheme preference.
 * Falls back to 'dark' when matchMedia is unavailable (e.g. SSR / tests).
 */
function getSystemTheme(): ResolvedTheme {
  if (typeof window === 'undefined' || !window.matchMedia) return 'dark';
  return window.matchMedia('(prefers-color-scheme: dark)').matches
    ? 'dark'
    : 'light';
}

/** Apply the resolved theme class to <html>. */
function applyThemeClass(resolved: ResolvedTheme): void {
  const root = document.documentElement;
  root.classList.remove('theme-light', 'theme-dark');
  root.classList.add(`theme-${resolved}`);
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

export const ThemeProvider: React.FC<React.PropsWithChildren> = ({
  children,
}) => {
  const [theme, setThemeState] = useState<ThemeSetting>('system');
  const [systemTheme, setSystemTheme] = useState<ResolvedTheme>(getSystemTheme);

  // -------- Resolve theme --------
  const resolvedTheme = useMemo<ResolvedTheme>(
    () => (theme === 'system' ? systemTheme : theme),
    [theme, systemTheme],
  );

  // -------- Apply class whenever resolvedTheme changes --------
  useEffect(() => {
    applyThemeClass(resolvedTheme);
  }, [resolvedTheme]);

  // -------- Persist & update preference --------
  const setTheme = useCallback((next: ThemeSetting) => {
    setThemeState(next);
    // Fire-and-forget persist to electron-store.
    // If electronAPI isn't available yet (preload not injected), silently skip.
    try {
      window.electronAPI?.saveSettings?.({ theme: next });
    } catch {
      // Electron IPC unavailable – ignore.
    }
  }, []);

  // -------- Load persisted theme on mount --------
  useEffect(() => {
    let cancelled = false;

    async function load() {
      try {
        const settings = await window.electronAPI?.getSettings?.();
        if (!cancelled && settings?.theme) {
          setThemeState(settings.theme as ThemeSetting);
        }
      } catch {
        // IPC not ready or unavailable – keep default.
      }
    }

    load();
    return () => {
      cancelled = true;
    };
  }, []);

  // -------- Listen for OS theme changes (only when theme === 'system') --------
  useEffect(() => {
    const mql = window.matchMedia?.('(prefers-color-scheme: dark)');
    if (!mql) return;

    const handler = (e: MediaQueryListEvent) => {
      setSystemTheme(e.matches ? 'dark' : 'light');
    };

    mql.addEventListener('change', handler);
    return () => mql.removeEventListener('change', handler);
  }, []);

  // -------- Context value --------
  const value = useMemo<ThemeContextValue>(
    () => ({ theme, setTheme, resolvedTheme }),
    [theme, setTheme, resolvedTheme],
  );

  return (
    <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>
  );
};

// ---------------------------------------------------------------------------
// Hook
// ---------------------------------------------------------------------------

export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext);
  if (ctx === undefined) {
    throw new Error('useTheme must be used within a <ThemeProvider>');
  }
  return ctx;
}

export default ThemeContext;
