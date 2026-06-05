# First-Run Onboarding Experience — Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add a 5-step onboarding flow shown on first launch for both PC (Electron/React) and Mobile (Flutter) clients. Each flow includes a step reminding the user to download the companion client. Users can replay onboarding from Settings.

**Architecture:** Full-screen overlay (PC: CSS modal, Mobile: full-screen route pushed before HomeScreen). Persistence via existing mechanisms — `electron-store` on PC, `SharedPreferences` on Mobile. No new dependencies needed.

**Tech Stack:** React + Electron (PC), Flutter + SharedPreferences (Mobile), url_launcher (Mobile, already a dependency).

**Branch:** `feature/onboarding`

---

## PC Client

### Task 1: Add `onboardingComplete` to settings store

**Objective:** Add the persistence key for onboarding state.

**Files:**
- Modify: `pc_client/electron/settings-store.ts`

**Steps:**
1. Add `onboardingComplete: false` to the `defaults` object in `settings-store.ts`.

The defaults block should become:
```ts
defaults: {
  startupOnBoot: false,
  minimizeToTray: false,
  clipboardSync: "auto-message",
  soundOnMessage: true,
  notificationsEnabled: true,
  theme: "system",
  onboardingComplete: false,
},
```

2. Commit: `git commit -m "feat(pc): add onboardingComplete key to settings store"`

---

### Task 2: Create `Onboarding.css`

**Objective:** Full-screen overlay styles for the onboarding modal.

**Files:**
- Create: `pc_client/src/Onboarding.css`

**Steps:**
1. Create the CSS file with these styles:

```css
/* ================================================================
   Onboarding full-screen overlay
   ================================================================ */

.onboarding-backdrop {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: var(--bg-primary);
  z-index: 20000;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  animation: onboardingFadeIn 0.3s ease;
}

@keyframes onboardingFadeIn {
  from { opacity: 0; }
  to   { opacity: 1; }
}

.onboarding-content {
  max-width: 480px;
  width: 100%;
  padding: 40px;
  text-align: center;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 24px;
}

.onboarding-icon {
  font-size: 64px;
  line-height: 1;
}

.onboarding-title {
  margin: 0;
  font-size: 24px;
  font-weight: 700;
  color: var(--text-primary);
}

.onboarding-description {
  margin: 0;
  font-size: 15px;
  line-height: 1.6;
  color: var(--text-secondary);
}

.onboarding-features {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
  width: 100%;
  text-align: left;
}

.onboarding-feature {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  padding: 12px;
  border-radius: 8px;
  background: var(--bg-secondary);
  border: 1px solid var(--border-secondary);
}

.onboarding-feature-icon {
  font-size: 20px;
  flex-shrink: 0;
}

.onboarding-feature-text {
  font-size: 13px;
  color: var(--text-secondary);
  line-height: 1.4;
}

.onboarding-feature-text strong {
  display: block;
  color: var(--text-primary);
  font-size: 14px;
  margin-bottom: 2px;
}

.onboarding-download-btn {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 12px 24px;
  border-radius: 8px;
  border: 1px solid #007bff;
  background: rgba(0, 123, 255, 0.1);
  color: #007bff;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  transition: background 0.15s;
  text-decoration: none;
}

.onboarding-download-btn:hover {
  background: rgba(0, 123, 255, 0.2);
}

/* Navigation */
.onboarding-nav {
  display: flex;
  align-items: center;
  gap: 16px;
  margin-top: 16px;
}

.onboarding-dots {
  display: flex;
  gap: 8px;
}

.onboarding-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--border-secondary);
  border: none;
  padding: 0;
  cursor: pointer;
  transition: background 0.15s, width 0.2s;
}

.onboarding-dot.active {
  background: #007bff;
  width: 24px;
  border-radius: 4px;
}

.onboarding-btn {
  padding: 8px 20px;
  border-radius: 6px;
  border: 1px solid var(--border-secondary);
  background: var(--bg-secondary);
  color: var(--text-primary);
  font-size: 14px;
  cursor: pointer;
  transition: background 0.15s;
}

.onboarding-btn:hover {
  background: var(--bg-hover);
}

.onboarding-btn.primary {
  background: #007bff;
  color: #fff;
  border-color: #007bff;
}

.onboarding-btn.primary:hover {
  background: #0056b3;
}

.onboarding-btn:disabled {
  opacity: 0.4;
  cursor: default;
}

.onboarding-skip {
  position: absolute;
  top: 20px;
  right: 20px;
  padding: 6px 14px;
  border-radius: 6px;
  border: none;
  background: transparent;
  color: var(--text-muted);
  font-size: 13px;
  cursor: pointer;
  transition: color 0.15s;
}

.onboarding-skip:hover {
  color: var(--text-primary);
}
```

2. Commit: `git commit -m "feat(pc): add onboarding CSS styles"`

---

### Task 3: Create `Onboarding.tsx` component

**Objective:** Build the 5-step onboarding overlay component.

**Files:**
- Create: `pc_client/src/Onboarding.tsx`

**Steps:**
1. Create the component:

```tsx
import { useState } from "react";
import "./Onboarding.css";

interface OnboardingProps {
  onComplete: () => void;
}

const STEPS = [
  {
    icon: "🚀",
    title: "Welcome to Fast Share",
    description:
      "Share files, text, and clipboard between your PC and phone — fast, private, and over your local network.",
  },
  {
    icon: "📱",
    title: "How It Works",
    description:
      "Your PC creates a local server. Scan the QR code with your phone to connect. No internet required — everything stays on your network.",
  },
  {
    icon: "✨",
    title: "What You Can Do",
    description: null,
    features: [
      { icon: "📁", title: "File Sharing", desc: "Drag & drop files of any size" },
      { icon: "💬", title: "Text Messages", desc: "Send quick text messages" },
      { icon: "📋", title: "Clipboard Sync", desc: "Copy & paste across devices" },
      { icon: "🔒", title: "Encrypted", desc: "End-to-end encryption built in" },
    ],
  },
  {
    icon: "📲",
    title: "Get the Mobile App",
    description:
      "You'll need the Fast Share app on your phone to connect. Download it and come back!",
    downloadUrl: "https://github.com/Woodylai24/fast-share/releases",
    downloadLabel: "Download for Android",
  },
  {
    icon: "🎉",
    title: "You're All Set!",
    description:
      "Scan the QR code on the next screen with your phone to connect. Happy sharing!",
  },
];

export function Onboarding({ onComplete }: OnboardingProps) {
  const [step, setStep] = useState(0);
  const current = STEPS[step];
  const isFirst = step === 0;
  const isLast = step === STEPS.length - 1;

  const next = () => {
    if (isLast) {
      onComplete();
    } else {
      setStep((s) => s + 1);
    }
  };

  const prev = () => {
    if (!isFirst) setStep((s) => s - 1);
  };

  return (
    <div className="onboarding-backdrop">
      <button className="onboarding-skip" onClick={onComplete}>
        Skip
      </button>

      <div className="onboarding-content">
        <div className="onboarding-icon">{current.icon}</div>
        <h1 className="onboarding-title">{current.title}</h1>

        {current.description && (
          <p className="onboarding-description">{current.description}</p>
        )}

        {current.features && (
          <div className="onboarding-features">
            {current.features.map((f) => (
              <div className="onboarding-feature" key={f.title}>
                <span className="onboarding-feature-icon">{f.icon}</span>
                <span className="onboarding-feature-text">
                  <strong>{f.title}</strong>
                  {f.desc}
                </span>
              </div>
            ))}
          </div>
        )}

        {current.downloadUrl && (
          <button
            className="onboarding-download-btn"
            onClick={() => {
              if (current.downloadUrl) {
                window.electronAPI.openExternal(current.downloadUrl);
              }
            }}
          >
            <span>⬇️</span>
            {current.downloadLabel}
          </button>
        )}

        <div className="onboarding-nav">
          <button
            className="onboarding-btn"
            onClick={prev}
            disabled={isFirst}
          >
            Back
          </button>

          <div className="onboarding-dots">
            {STEPS.map((_, i) => (
              <button
                key={i}
                className={`onboarding-dot ${i === step ? "active" : ""}`}
                onClick={() => setStep(i)}
                aria-label={`Step ${i + 1}`}
              />
            ))}
          </div>

          <button className="onboarding-btn primary" onClick={next}>
            {isLast ? "Get Started" : "Next"}
          </button>
        </div>
      </div>
    </div>
  );
}
```

2. Commit: `git commit -m "feat(pc): add Onboarding component with 5 steps"`

---

### Task 4: Wire Onboarding into `App.tsx`

**Objective:** Show onboarding overlay on first launch.

**Files:**
- Modify: `pc_client/src/App.tsx`

**Steps:**
1. Add import: `import { Onboarding } from "./Onboarding";`
2. Add state: `const [showOnboarding, setShowOnboarding] = useState(false);`
3. Add a `useEffect` that checks `onboardingComplete` on mount:
```tsx
const checkOnboarding = useCallback(async () => {
  try {
    const settings = await window.electronAPI.getSettings();
    if (!settings.onboardingComplete) {
      setShowOnboarding(true);
    }
  } catch {
    // default: don't show
  }
}, []);

useEffect(() => {
  checkOnboarding();
}, [checkOnboarding]);
```
4. Add a handler for completing onboarding:
```tsx
const handleOnboardingComplete = useCallback(async () => {
  setShowOnboarding(false);
  await window.electronAPI.saveSettings({ onboardingComplete: true });
}, []);
```
5. Render the onboarding overlay inside the JSX, right before the closing `</div>` of the container or after the `<ThemeProvider>` opening tag (before `<TitleBar>`):
```tsx
{showOnboarding && <Onboarding onComplete={handleOnboardingComplete} />}
```

Note: Place it right after `<ThemeProvider>` and before `<TitleBar>` so it sits above everything.

6. Commit: `git commit -m "feat(pc): wire onboarding overlay into App"`

---

### Task 5: Add "Replay Onboarding" to Settings

**Objective:** Let users replay onboarding from the Settings panel.

**Files:**
- Modify: `pc_client/src/Settings.tsx`

**Steps:**
1. Add a new "Replay onboarding" button in the **About** section (before the Version row). Use the same pattern as other settings rows:

```tsx
<button
  className="settings-replay-btn"
  onClick={async () => {
    await window.electronAPI.saveSettings({ onboardingComplete: false });
    window.location.reload();
  }}
>
  Replay onboarding
</button>
```

2. Add minimal CSS for the button in `Settings.css`:
```css
.settings-replay-btn {
  width: 100%;
  padding: 8px 16px;
  border-radius: 6px;
  border: 1px solid var(--border-secondary);
  background: var(--bg-tertiary);
  color: var(--text-primary);
  font-size: 14px;
  cursor: pointer;
  transition: background 0.15s;
}

.settings-replay-btn:hover {
  background: var(--bg-hover);
}
```

3. Commit: `git commit -m "feat(pc): add replay onboarding option to Settings"`

---

## Mobile Client

### Task 6: Add `onboardingComplete` to `SettingsService`

**Objective:** Add the persistence key for onboarding state on mobile.

**Files:**
- Modify: `mobile_client/lib/services/settings_service.dart`

**Steps:**
1. Add the key constant and getter/setter to `SettingsService`:

```dart
static const String _onboardingCompleteKey = 'onboarding_complete';
static const bool _defaultOnboardingComplete = false;

/// Whether the user has completed the onboarding flow.
static Future<bool> getOnboardingComplete() async {
  final prefs = await _prefs;
  return prefs.getBool(_onboardingCompleteKey) ?? _defaultOnboardingComplete;
}

/// Mark onboarding as complete.
static Future<void> setOnboardingComplete(bool value) async {
  final prefs = await _prefs;
  await prefs.setBool(_onboardingCompleteKey, value);
}
```

2. Add `_onboardingCompleteKey` to the `resetAll()` method's remove calls.
3. Commit: `git commit -m "feat(mobile): add onboardingComplete to SettingsService"`

---

### Task 7: Create `OnboardingScreen`

**Objective:** Build the 5-step onboarding screen widget.

**Files:**
- Create: `mobile_client/lib/screens/onboarding_screen.dart`

**Steps:**
1. Create the file with a `PageView`-based onboarding flow:

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fast_share_mobile/services/settings_service.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _steps = [
    {
      'icon': Icons.rocket_launch_rounded,
      'title': 'Welcome to Fast Share',
      'description':
          'Share files, text, and clipboard between your PC and phone — fast, private, and over your local network.',
    },
    {
      'icon': Icons.qr_code_scanner,
      'title': 'How to Connect',
      'description':
          'Open Fast Share on your PC. Scan the QR code shown on the screen, or enter the IP address manually.',
    },
    {
      'icon': Icons.share,
      'title': 'What You Can Do',
      'description':
          'Send files of any size, share text messages, sync your clipboard, and more — all encrypted over your local network.',
      'features': true,
    },
    {
      'icon': Icons.laptop,
      'title': 'Get the PC Client',
      'description':
          'You\'ll need Fast Share on your PC to connect. Download it and get started!',
      'download_url': 'https://github.com/Woodylai24/fast-share/releases',
      'download_label': 'Download for PC',
    },
    {
      'icon': Icons.check_circle_outline,
      'title': 'You\'re All Set!',
      'description':
          'Connect to your PC and start sharing. Happy transferring!',
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _complete();
    }
  }

  Future<void> _complete() async {
    await SettingsService.setOnboardingComplete(true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isLast = _currentPage == _steps.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: _complete,
                  child: const Text('Skip'),
                ),
              ),
            ),
            // Page content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _steps.length,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemBuilder: (context, index) {
                  final step = _steps[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          step['icon'] as IconData,
                          size: 80,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(height: 32),
                        Text(
                          step['title'] as String,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          step['description'] as String,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (step['features'] == true) ...[
                          const SizedBox(height: 24),
                          _FeatureGrid(theme: theme),
                        ],
                        if (step['download_url'] != null) ...[
                          const SizedBox(height: 24),
                          OutlinedButton.icon(
                            onPressed: () {
                              final url = Uri.parse(step['download_url'] as String);
                              launchUrl(url, mode: LaunchMode.externalApplication);
                            },
                            icon: const Icon(Icons.download),
                            label: Text(step['download_label'] as String),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            // Navigation
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back button
                  if (_currentPage > 0)
                    TextButton(
                      onPressed: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                      child: const Text('Back'),
                    )
                  else
                    const SizedBox(width: 70),
                  // Dots
                  Row(
                    children: List.generate(_steps.length, (index) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? colorScheme.primary
                              : colorScheme.onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  // Next / Get Started
                  ElevatedButton(
                    onPressed: _nextPage,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: Text(isLast ? 'Get Started' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  final ThemeData theme;

  const _FeatureGrid({required this.theme});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.5,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        _FeatureCard(
          icon: Icons.folder_outlined,
          title: 'File Sharing',
          desc: 'Any size',
          theme: theme,
        ),
        _FeatureCard(
          icon: Icons.message_outlined,
          title: 'Messages',
          desc: 'Quick text',
          theme: theme,
        ),
        _FeatureCard(
          icon: Icons.content_copy,
          title: 'Clipboard',
          desc: 'Copy & paste',
          theme: theme,
        ),
        _FeatureCard(
          icon: Icons.lock_outline,
          title: 'Encrypted',
          desc: 'E2EE built-in',
          theme: theme,
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final ThemeData theme;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Icon(icon, size: 24, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text(desc, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
            ],
          ),
        ],
      ),
    );
  }
}
```

2. Commit: `git commit -m "feat(mobile): add OnboardingScreen with 5 steps"`

---

### Task 8: Wire OnboardingScreen into `main.dart`

**Objective:** Show onboarding on first launch before HomeScreen.

**Files:**
- Modify: `mobile_client/lib/main.dart`

**Steps:**
1. Add import: `import 'package:fast_share_mobile/screens/onboarding_screen.dart';`
2. Change `FastShareApp` to a `StatefulWidget` (it's currently `StatelessWidget`).
3. In the state, add a `bool _onboardingComplete = false;` field and load it in `initState`:

```dart
class _FastShareAppState extends State<FastShareApp> {
  bool _onboardingComplete = false;

  @override
  void initState() {
    super.initState();
    _loadOnboardingState();
  }

  Future<void> _loadOnboardingState() async {
    final complete = await SettingsService.getOnboardingComplete();
    if (mounted) {
      setState(() => _onboardingComplete = complete);
    }
  }
```

4. In the `build` method, conditionally show onboarding or home:

```dart
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.themeNotifier,
      builder: (context, child) {
        return MaterialApp(
          title: 'Fast Share Mobile',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: widget.themeNotifier.mode,
          home: _onboardingComplete
              ? HomeScreen(themeNotifier: widget.themeNotifier)
              : OnboardingScreen(
                  onComplete: () {
                    setState(() => _onboardingComplete = true);
                  },
                ),
        );
      },
    );
  }
```

5. Add import: `import 'package:fast_share_mobile/services/settings_service.dart';`
6. Commit: `git commit -m "feat(mobile): wire onboarding screen into app startup"`

---

### Task 9: Add "Reset Onboarding" to Settings screen

**Objective:** Let users replay onboarding from the Settings screen.

**Files:**
- Modify: `mobile_client/lib/screens/settings_screen.dart`

**Steps:**
1. Add a "Reset onboarding" `ListTile` in the **About** section (before the Version tile):

```dart
ListTile(
  leading: const Icon(Icons.replay),
  title: const Text('Reset onboarding'),
  subtitle: const Text('Show the onboarding flow again on next launch'),
  onTap: () async {
    await SettingsService.setOnboardingComplete(false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Onboarding will show on next app launch'),
        ),
      );
    }
  },
),
```

2. Commit: `git commit -m "feat(mobile): add reset onboarding option to Settings"`

---

## Build Verification

### Task 10: Verify both builds compile clean

**PC client:**
```bash
cd pc_client
npm run build
```
Expected: Builds with no TypeScript errors.

**Mobile client:**
```bash
cd mobile_client
flutter analyze
```
Expected: No issues found (warnings are OK).

---

## Notes

- Download links are stubs pointing to `https://github.com/Woodylai24/fast-share/releases` — can be updated later.
- PC onboarding uses `window.electronAPI.openExternal()` to open the download link in the system browser.
- Mobile uses `url_launcher` package (already a dependency).
- The PC overlay z-index is `20000` (above Settings at `10000`).
- Both clients use emoji icons to avoid the need for custom icon assets.
- The "Skip" button is on the top-right of the screen on both platforms for users who don't want the tour.
