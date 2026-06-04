import 'package:flutter/material.dart';
import 'package:fast_share_mobile/services/settings_service.dart';

/// A [ChangeNotifier] that manages the app's theme preference.
///
/// On initialization it loads the persisted theme string from
/// [SettingsService] and converts it to a [ThemeMode]. Consumers can call
/// [setTheme] to change the preference – the new value is saved to
/// [SettingsService] and all listeners are notified.
class ThemeNotifier extends ChangeNotifier {
  // ── State ─────────────────────────────────────────────────────────────

  ThemeMode _mode = ThemeMode.system;
  bool _initialized = false;

  // ── Public getters ────────────────────────────────────────────────────

  /// The current [ThemeMode] (system / light / dark).
  ThemeMode get mode => _mode;

  /// Whether [init] has completed.
  bool get initialized => _initialized;

  // ── Resolved themes ───────────────────────────────────────────────────

  /// Light theme definition (Material 3).
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    colorSchemeSeed: Colors.blue,
    useMaterial3: true,
  );

  /// Dark theme definition (Material 3).
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    colorSchemeSeed: Colors.blue,
    useMaterial3: true,
  );

  /// Returns the resolved [ThemeData] based on [_mode].
  ThemeData get theme {
    switch (_mode) {
      case ThemeMode.light:
        return lightTheme;
      case ThemeMode.dark:
        return darkTheme;
      case ThemeMode.system:
        // When using system mode the MaterialApp resolves the theme
        // automatically based on the platform brightness, so we return light
        // as a fallback for direct consumption.
        return lightTheme;
    }
  }

  // ── Initialisation ────────────────────────────────────────────────────

  /// Loads the persisted theme preference from [SettingsService].
  ///
  /// Call this once (e.g. before `runApp`) so that the notifier is ready
  /// before the first frame.
  Future<void> init() async {
    final String stored = await SettingsService.getTheme();
    _mode = _stringToMode(stored);
    _initialized = true;
    notifyListeners();
  }

  // ── Mutation ──────────────────────────────────────────────────────────

  /// Persists [mode] via [SettingsService] and notifies listeners.
  Future<void> setTheme(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    await SettingsService.setTheme(_modeToString(mode));
  }

  /// Convenience overload that accepts a raw string ('system' | 'light' |
  /// 'dark') and delegates to [setTheme].
  Future<void> setThemeString(String value) async {
    await setTheme(_stringToMode(value));
  }

  // ── Conversion helpers ────────────────────────────────────────────────

  static ThemeMode _stringToMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  static String _modeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
