import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage app settings persisted via SharedPreferences.
class SettingsService {
  // Preference keys
  static const String _startupOnBootKey = 'startup_on_boot';
  static const String _autoConnectOnLaunchKey = 'auto_connect_on_launch';
  static const String _autoReconnectKey = 'auto_reconnect';
  static const String _clipboardSyncKey = 'clipboard_sync';
  static const String _themeKey = 'theme';

  // Default values
  static const bool _defaultStartupOnBoot = false;
  static const bool _defaultAutoConnectOnLaunch = true;
  static const bool _defaultAutoReconnect = true;
  static const String _defaultClipboardSync = 'notify';
  static const String _defaultTheme = 'system';

  static Future<SharedPreferences> get _prefs async {
    return await SharedPreferences.getInstance();
  }

  // --- startupOnBoot ---

  /// Whether the app should start on device boot.
  static Future<bool> getStartupOnBoot() async {
    final prefs = await _prefs;
    return prefs.getBool(_startupOnBootKey) ?? _defaultStartupOnBoot;
  }

  /// Set whether the app should start on device boot.
  static Future<void> setStartupOnBoot(bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(_startupOnBootKey, value);
  }

  // --- autoConnectOnLaunch ---

  /// Whether the app should automatically connect when launched.
  static Future<bool> getAutoConnectOnLaunch() async {
    final prefs = await _prefs;
    return prefs.getBool(_autoConnectOnLaunchKey) ??
        _defaultAutoConnectOnLaunch;
  }

  /// Set whether the app should automatically connect when launched.
  static Future<void> setAutoConnectOnLaunch(bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(_autoConnectOnLaunchKey, value);
  }

  // --- autoReconnect ---

  /// Whether the app should automatically reconnect when disconnected.
  static Future<bool> getAutoReconnect() async {
    final prefs = await _prefs;
    return prefs.getBool(_autoReconnectKey) ?? _defaultAutoReconnect;
  }

  /// Set whether the app should automatically reconnect when disconnected.
  static Future<void> setAutoReconnect(bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(_autoReconnectKey, value);
  }

  // --- clipboardSync ---

  /// Clipboard sync mode: 'none', 'notify', or 'auto'.
  static Future<String> getClipboardSync() async {
    final prefs = await _prefs;
    return prefs.getString(_clipboardSyncKey) ?? _defaultClipboardSync;
  }

  /// Set clipboard sync mode. Valid values: 'none', 'notify', 'auto'.
  static Future<void> setClipboardSync(String value) async {
    assert(
      value == 'none' || value == 'notify' || value == 'auto',
      'clipboardSync must be one of: none, notify, auto',
    );
    final prefs = await _prefs;
    await prefs.setString(_clipboardSyncKey, value);
  }

  // --- theme ---

  /// Theme preference: 'system', 'light', or 'dark'.
  static Future<String> getTheme() async {
    final prefs = await _prefs;
    return prefs.getString(_themeKey) ?? _defaultTheme;
  }

  /// Set theme preference. Valid values: 'system', 'light', 'dark'.
  static Future<void> setTheme(String value) async {
    assert(
      value == 'system' || value == 'light' || value == 'dark',
      'theme must be one of: system, light, dark',
    );
    final prefs = await _prefs;
    await prefs.setString(_themeKey, value);
  }

  // --- Reset ---

  /// Reset all settings to their default values.
  static Future<void> resetAll() async {
    final prefs = await _prefs;
    await prefs.remove(_startupOnBootKey);
    await prefs.remove(_autoConnectOnLaunchKey);
    await prefs.remove(_autoReconnectKey);
    await prefs.remove(_clipboardSyncKey);
    await prefs.remove(_themeKey);
  }
}
