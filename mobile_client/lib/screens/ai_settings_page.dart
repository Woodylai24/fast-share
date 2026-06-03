import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fast_share_mobile/ai_service.dart';

class AISettingsPage extends StatefulWidget {
  const AISettingsPage({super.key});

  @override
  State<AISettingsPage> createState() => _AISettingsPageState();
}

class _AISettingsPageState extends State<AISettingsPage> {
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
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final apiKey = await AISettingsService.getApiKey();
    final model = await AISettingsService.getModel();

    setState(() {
      if (apiKey != null && apiKey.isNotEmpty) {
        _hasApiKey = true;
        _apiKeyController.text = '••••••••';
        _fetchModels();
      }
      _selectedModel = model;
    });
  }

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
      setState(() {
        _models = models;
        _loadingModels = false;
      });
    } catch (e) {
      setState(() {
        _fetchError = 'Failed to fetch models';
        _loadingModels = false;
      });
    }
  }

  Future<void> _saveModel(String model) async {
    await AISettingsService.saveModel(model);
    setState(() => _selectedModel = model);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _hasApiKey ? _fetchModels : null,
            tooltip: 'Refresh models',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Provider',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
              onChanged: null,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Select provider',
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'API Key',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                          _showApiKey ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () =>
                            setState(() => _showApiKey = !_showApiKey),
                      ),
                    ),
                    onChanged: (_) => setState(() => _apiKeySaved = false),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed:
                      (_apiKeyController.text.isNotEmpty &&
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
                child: Text('✓ Saved', style: TextStyle(color: Colors.green)),
              ),
            const SizedBox(height: 24),
            const Text(
              'Default Model',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                    child: Text(m.displayName, overflow: TextOverflow.ellipsis),
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
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'API key is stored securely on your device.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
