# Fast-Share: Settings Page + Dark/Light Theme Implementation Plan

> **Covers:** GitHub issues #15 (Settings Page) and #16 (Dark/Light Theme)
> **Scope:** Both PC Client (Electron/React) and Mobile Client (Flutter)
> **Status:** Approved — executing

---

## Summary of Changes

### Settings Pages

| Setting | PC Client | Mobile Client |
|---------|-----------|---------------|
| **Startup on boot** | ✅ Electron `app.setLoginItemSettings` | ✅ `RECEIVE_BOOT_COMPLETED` (default OFF) |
| **Minimize to tray** | ✅ Tray icon + context menu (PC exclusive) | N/A |
| **Auto-connect on app launch** | N/A | ✅ Reconnect to last server (default ON) |
| **Auto-reconnect on disconnect** | N/A | ✅ Auto retry WebSocket (default ON) |
| **Clipboard sync** | 3 options: No sync / Auto send as message (default) / Auto sync | Same 3 options |
| **Sound on new message** | ✅ Toggle (default ON) | N/A (uses system notification settings) |
| **Windows notifications** | ✅ Toggle (default ON) | N/A |
| **Theme** | 3 options: System Default (default) / Light / Dark | Same 3 options |
| **AI Settings** | Move existing AISettings content into Settings page | Same — nest into Settings |
| **About** | Version display at bottom | Same |

### Theme System
- **PC:** CSS custom properties on `:root`, `.theme-light` / `.theme-dark` classes, `ThemeContext` + React context, persisted via `electron-store`, OS detection via `window.matchMedia('(prefers-color-scheme: dark)')`
- **Mobile:** `ThemeNotifier` (ChangeNotifier), light + dark `ThemeData`, persisted via `SharedPreferences`, OS detection via `MediaQuery.platformBrightness`

---

## Execution Order

### Phase 1 — Infrastructure (no visible changes yet)
1. Task 1: PC settings store (`electron/settings-store.ts`)
2. Task 11: Mobile settings service (`lib/services/settings_service.dart`)
3. Task 6: PC CSS theme variables (`index.css`, `App.css`, `TitleBar.css`, `AISettings.css`, `SummaryPopup.css`)

### Phase 2 — Theme system
4. Task 7: PC ThemeContext (`src/contexts/ThemeContext.tsx`)
5. Task 12: Mobile ThemeNotifier (`lib/services/theme_notifier.dart`)
6. Task 13: Mobile AppTheme (`lib/theme/app_theme.dart`)
7. Task 14: Mobile main.dart wiring

### Phase 3 — Settings pages (visible!)
8. Task 2: PC tray (`electron/tray.ts` + main.ts)
9. Task 3: PC clipboard modes (clipboard-sync.ts + server.ts + ipc-handlers.ts)
10. Task 4: PC settings IPC handlers
11. Task 5: PC preload update
12. Task 8: PC Settings.tsx + Settings.css
13. Task 9: PC App.tsx wiring
14. Task 10: PC delete AISettings.tsx/.css
15. Task 15: Mobile Settings screen
16. Task 16: Mobile home screen button
17. Task 17: Mobile chat app bar update
18. Task 21: Mobile delete AISettings

### Phase 4 — Wire behaviors
19. Task 18: Mobile startup on boot (Android)
20. Task 19: Mobile auto-connect/reconnect
21. Task 20: Mobile clipboard sync modes

### Phase 5 — Testing & cleanup
- Manual test both clients in light/dark/system themes
- Test all settings persist across restart
- Test tray behavior (PC)
- Test clipboard sync in all 3 modes
- Build both clients
