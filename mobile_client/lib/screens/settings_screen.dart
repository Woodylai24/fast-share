import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fast_share_mobile/ai_service.dart';
import 'package:fast_share_mobile/services/settings_service.dart';
import 'package:fast_share_mobile/services/theme_notifier.dart';

/// Full settings page with General, Appearance, Connection, Notifications,
/// AI, and About sections.
class SettingsScreen extends StatefulWidget {
  final ThemeNotifier themeNotifier;

  const SettingsScreen({super.key, required this.themeNotifier});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ── General state ────────────────────────────────────────────────────
  bool _startupOnBoot = false;
  bool _autoConnectOnLaunch = true;
  bool _autoReconnect = true;
  bool _settingsLoaded = false;

  // ── Appearance state ─────────────────────────────────────────────────
  String _themeMode = 'system'; // 'system' | 'light' | 'dark'

  // ── Connection state ─────────────────────────────────────────────────
  String _clipboardSync = 'auto-message'; // 'none' | 'auto-message' | 'auto-sync'

  // ── AI state (same as AISettingsPage) ────────────────────────────────
  final TextEditingController _apiKeyController = TextEditingController();
  bool _showApiKey = false;
  bool _apiKeySaved = false;
  bool _hasApiKey = false;
  String _selectedModel = 'openrouter/auto';
  List<AIModel> _models = [];
  bool _loadingModels = false;
  String? _fetchError;

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  // ── Load settings ────────────────────────────────────────────────────

  Future<void> _loadAllSettings() async {
    final results = await Future.wait<dynamic>([
      SettingsService.getStartupOnBoot(),
      SettingsService.getAutoConnectOnLaunch(),
      SettingsService.getAutoReconnect(),
      SettingsService.getClipboardSync(),
      SettingsService.getTheme(),
      AISettingsService.getApiKey(),
      AISettingsService.getModel(),
    ]);

    setState(() {
      _startupOnBoot = results[0] as bool;
      _autoConnectOnLaunch = results[1] as bool;
      _autoReconnect = results[2] as bool;
      _clipboardSync = results[3] as String;
      _themeMode = results[4] as String;

      final apiKey = results[5] as String?;
      if (apiKey != null && apiKey.isNotEmpty) {
        _hasApiKey = true;
        _apiKeyController.text = '••••••••';
      }
      _selectedModel = results[6] as String;

      _settingsLoaded = true;
    });

    if (_hasApiKey) {
      _fetchModels();
    }
  }

  // ── AI helpers ───────────────────────────────────────────────────────

  Future<void> _saveApiKey() async {
    final keyToSave = _apiKeyController.text;
    if (keyToSave.isEmpty || keyToSave == '••••••••') return;

    await AISettingsService.saveApiKey(keyToSave);
    AIService.clearModelCache();
    setState(() {
      _hasApiKey = true;
      _apiKeyController.text = '••••••••';
      _apiKeySaved = true;
    });
    _fetchModels();

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _apiKeySaved = false);
      }
    });
  }

  Future<void> _fetchModels() async {
    final apiKey = await AISettingsService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) return;

    setState(() {
      _loadingModels = true;
      _fetchError = null;
    });

    try {
      final models = await AIService.fetchModels(apiKey);
      if (mounted) {
        setState(() {
          _models = models;
          _loadingModels = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fetchError = 'Failed to fetch models';
          _loadingModels = false;
        });
      }
    }
  }

  Future<void> _saveModel(String model) async {
    await AISettingsService.saveModel(model);
    setState(() => _selectedModel = model);
  }

  // ── Notification helper ──────────────────────────────────────────────

  Future<void> _openNotificationSettings() async {
    try {
      const channel = MethodChannel('fast_share/settings');
      await channel.invokeMethod('openNotificationSettings');
    } on PlatformException catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open notification settings'),
          ),
        );
      }
    }
  }

  // ── Clipboard sync description ────────────────────────────────────

  String _clipboardSyncDescription(String value) {
    switch (value) {
      case 'none':
        return 'Clipboard changes on this device will not be shared.';
      case 'auto-message':
        return 'Clipboard changes will be sent as regular text messages.';
      case 'auto-sync':
        return 'Clipboard changes will be sent to the other device and auto-copied.';
      default:
        return '';
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _settingsLoaded
          ? ListView(
              children: [
                // ═══════════════════════════════════════════════════════════
                // GENERAL
                // ═══════════════════════════════════════════════════════════
                _SectionHeader(title: 'General', icon: Icons.settings_outlined),
                SwitchListTile(
                  secondary: const Icon(Icons.power_settings_new),
                  title: const Text('Startup on boot'),
                  subtitle: const Text('Launch the app when the device starts'),
                  value: _startupOnBoot,
                  onChanged: (value) async {
                    await SettingsService.setStartupOnBoot(value);
                    // Enable/disable the BootReceiver via platform channel
                    try {
                      const channel = MethodChannel('fast_share/settings');
                      await channel.invokeMethod('setStartupOnBoot', {'enabled': value});
                    } on PlatformException catch (_) {
                      // Silently ignore on non-Android platforms
                    }
                    setState(() => _startupOnBoot = value);
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.link),
                  title: const Text('Auto-connect on app launch'),
                  subtitle: const Text('Automatically connect when the app opens'),
                  value: _autoConnectOnLaunch,
                  onChanged: (value) async {
                    await SettingsService.setAutoConnectOnLaunch(value);
                    setState(() => _autoConnectOnLaunch = value);
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.sync),
                  title: const Text('Auto-reconnect on disconnect'),
                  subtitle: const Text('Reconnect automatically when disconnected'),
                  value: _autoReconnect,
                  onChanged: (value) async {
                    await SettingsService.setAutoReconnect(value);
                    setState(() => _autoReconnect = value);
                  },
                ),

                const Divider(indent: 16, endIndent: 16),

                // ═══════════════════════════════════════════════════════════
                // APPEARANCE
                // ═══════════════════════════════════════════════════════════
                _SectionHeader(
                    title: 'Appearance', icon: Icons.palette_outlined),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'system',
                        label: Text('System'),
                        icon: Icon(Icons.brightness_auto),
                      ),
                      ButtonSegment(
                        value: 'light',
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode),
                      ),
                      ButtonSegment(
                        value: 'dark',
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode),
                      ),
                    ],
                    selected: {_themeMode},
                    onSelectionChanged: (selection) async {
                      final value = selection.first;
                      await widget.themeNotifier.setThemeString(value);
                      setState(() => _themeMode = value);
                    },
                  ),
                ),

                const Divider(indent: 16, endIndent: 16),

                // ═══════════════════════════════════════════════════════════
                // CONNECTION
                // ═══════════════════════════════════════════════════════════
                _SectionHeader(
                    title: 'Connection', icon: Icons.cable_outlined),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Clipboard sync',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'none',
                            label: Text('No sync'),
                          ),
                          ButtonSegment(
                            value: 'auto-message',
                            label: Text('Auto send'),
                          ),
                          ButtonSegment(
                            value: 'auto-sync',
                            label: Text('Auto sync'),
                          ),
                        ],
                        selected: {_clipboardSync},
                        onSelectionChanged: (selection) async {
                          final value = selection.first;
                          await SettingsService.setClipboardSync(value);
                          setState(() => _clipboardSync = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _clipboardSyncDescription(_clipboardSync),
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(indent: 16, endIndent: 16),

                // ═══════════════════════════════════════════════════════════
                // NOTIFICATIONS
                // ═══════════════════════════════════════════════════════════
                _SectionHeader(
                    title: 'Notifications',
                    icon: Icons.notifications_outlined),
                ListTile(
                  leading: const Icon(Icons.settings_applications),
                  title: const Text('Open system notification settings'),
                  subtitle: const Text(
                    'Manage notification permissions for this app',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openNotificationSettings,
                ),

                const Divider(indent: 16, endIndent: 16),

                // ═══════════════════════════════════════════════════════════
                // AI
                // ═══════════════════════════════════════════════════════════
                _SectionHeader(
                    title: 'AI', icon: Icons.smart_toy_outlined),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Provider
                      const SizedBox(height: 8),
                      Text(
                        'Provider',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: 'openrouter',
                        items: const [
                          DropdownMenuItem(
                            value: 'openrouter',
                            child: Text('OpenRouter'),
                          ),
                        ],
                        onChanged: null, // disabled – only OpenRouter
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Select provider',
                        ),
                      ),

                      const SizedBox(height: 16),

                      // API Key
                      Text(
                        'API Key',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _apiKeyController,
                              obscureText: !_showApiKey,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                hintText: 'sk-or-...',
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _showApiKey
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () => setState(
                                      () => _showApiKey = !_showApiKey),
                                ),
                              ),
                              onChanged: (_) =>
                                  setState(() => _apiKeySaved = false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: (_apiKeyController.text.isNotEmpty &&
                                    _apiKeyController.text != '••••••••')
                                ? _saveApiKey
                                : null,
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                      if (_apiKeySaved)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('✓ Saved',
                              style: TextStyle(color: Colors.green)),
                        ),

                      const SizedBox(height: 16),

                      // Model
                      Row(
                        children: [
                          Text(
                            'Default Model',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            onPressed: _hasApiKey ? _fetchModels : null,
                            tooltip: 'Refresh models',
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _hasApiKey ? _selectedModel : null,
                        items: [
                          if (!_hasApiKey)
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Enter API key first'),
                            ),
                          if (_hasApiKey && _models.isEmpty && !_loadingModels)
                            const DropdownMenuItem(
                              value: 'openrouter/auto',
                              child: Text('Auto (openrouter/auto)'),
                            ),
                          ..._models.map(
                            (m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(
                                m.displayName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: _hasApiKey && !_loadingModels
                            ? (value) {
                                if (value != null) _saveModel(value);
                              }
                            : null,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Select model',
                        ),
                      ),
                      if (_loadingModels)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('Loading models...'),
                            ],
                          ),
                        ),
                      if (_fetchError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _fetchError!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),

                      const SizedBox(height: 8),
                      Text(
                        'API key is stored securely on your device.',
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),

                const Divider(indent: 16, endIndent: 16),

                // ═══════════════════════════════════════════════════════════
                // ABOUT
                // ═══════════════════════════════════════════════════════════
                _SectionHeader(title: 'About', icon: Icons.info_outline),
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
                ListTile(
                  leading: const Icon(Icons.new_releases_outlined),
                  title: const Text('Version'),
                  subtitle: const Text('1.0.0'),
                ),
                const SizedBox(height: 24),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

// ── Reusable section header widget ─────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
