import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage app settings persisted via SharedPreferences.
class SettingsService {
  // Preference keys
  static const String _startupOnBootKey = 'startup_on_boot';
  static const String _autoConnectOnLaunchKey = 'auto_connect_on_launch';
  static const String _autoReconnectKey = 'auto_reconnect';
  static const String _clipboardSyncKey = 'clipboard_sync';
  static const String _themeKey = 'theme';
  static const String _onboardingCompleteKey = 'onboarding_complete';

  // Last successful pairing (used to skip HomeScreen on subsequent launches)
  static const String _lastConnIpKey = 'last_conn_ip';
  static const String _lastConnPortKey = 'last_conn_port';
  static const String _lastConnHttpPortKey = 'last_conn_http_port';

  // Default values
  static const bool _defaultStartupOnBoot = false;
  static const bool _defaultAutoConnectOnLaunch = true;
  static const bool _defaultAutoReconnect = true;
  static const String _defaultClipboardSync = 'auto-message';
  static const String _defaultTheme = 'system';
  static const bool _defaultOnboardingComplete = false;

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

  /// Clipboard sync mode: 'none', 'auto-message', or 'auto-sync'.
  static Future<String> getClipboardSync() async {
    final prefs = await _prefs;
    return prefs.getString(_clipboardSyncKey) ?? _defaultClipboardSync;
  }

  /// Set clipboard sync mode. Valid values: 'none', 'auto-message', 'auto-sync'.
  static Future<void> setClipboardSync(String value) async {
    assert(
      value == 'none' || value == 'auto-message' || value == 'auto-sync',
      'clipboardSync must be one of: none, auto-message, auto-sync',
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

  // --- onboardingComplete ---

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

  // --- lastConnection (last successful pairing) ---

  /// Returns the last paired connection, or null if none is saved.
  /// On subsequent launches this is used to open ChatScreen directly.
  static Future<({String ip, int port, int httpPort})?> getLastConnection() async {
    final prefs = await _prefs;
    final ip = prefs.getString(_lastConnIpKey);
    final port = prefs.getInt(_lastConnPortKey);
    final httpPort = prefs.getInt(_lastConnHttpPortKey);
    if (ip == null || port == null || httpPort == null) return null;
    return (ip: ip, port: port, httpPort: httpPort);
  }

  /// Save the connection info from a successful pairing so the app can
  /// reopen straight to ChatScreen on the next launch.
  static Future<void> setLastConnection(
    String ip,
    int port,
    int httpPort,
  ) async {
    final prefs = await _prefs;
    await prefs.setString(_lastConnIpKey, ip);
    await prefs.setInt(_lastConnPortKey, port);
    await prefs.setInt(_lastConnHttpPortKey, httpPort);
  }

  /// Forget the last pairing. Next launch returns to HomeScreen.
  static Future<void> clearLastConnection() async {
    final prefs = await _prefs;
    await prefs.remove(_lastConnIpKey);
    await prefs.remove(_lastConnPortKey);
    await prefs.remove(_lastConnHttpPortKey);
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
    await prefs.remove(_onboardingCompleteKey);
    await clearLastConnection();
  }
}
