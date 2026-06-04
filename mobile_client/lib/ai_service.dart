import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as spdf;
import 'package:http/http.dart' as http;

class AISettingsService {
  static const _storage = FlutterSecureStorage();
  static const _apiKeyKey = 'openrouter_api_key';
  static const _providerKey = 'ai_provider';
  static const _modelKey = 'ai_model';

  static Future<String?> getApiKey() async {
    return await _storage.read(key: _apiKeyKey);
  }

  static Future<void> saveApiKey(String apiKey) async {
    await _storage.write(key: _apiKeyKey, value: apiKey);
  }

  static Future<String> getProvider() async {
    return await _storage.read(key: _providerKey) ?? 'openrouter';
  }

  static Future<void> saveProvider(String provider) async {
    await _storage.write(key: _providerKey, value: provider);
  }

  static Future<String> getModel() async {
    return await _storage.read(key: _modelKey) ?? 'openrouter/auto';
  }

  static Future<void> saveModel(String model) async {
    await _storage.write(key: _modelKey, value: model);
  }

  static Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }
}

class AIModel {
  final String id;
  final String name;
  final bool hasVision;

  AIModel({required this.id, required this.name, this.hasVision = false});

  String get displayName {
    final parts = id.split('/');
    final shortId = parts.length > 1 ? parts.sublist(1).join('/') : parts[0];
    final display = shortId[0].toUpperCase() + shortId.substring(1);
    return '$display${hasVision ? ' 👁' : ''}';
  }
}

class AIService {
  static final Map<String, List<AIModel>> _modelCache = {};

  static Future<List<AIModel>> fetchModels(String apiKey) async {
    if (_modelCache.containsKey(apiKey)) {
      return _modelCache[apiKey]!;
    }

    final response = await http.get(
      Uri.parse('https://openrouter.ai/api/v1/models'),
      headers: {
        'Content-Type': 'application/json',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      },
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = jsonDecode(response.body);
      final models = <AIModel>[];

      for (final m in data['data'] ?? []) {
        final inputModalities =
            m['architecture']?['input_modalities'] as List? ?? [];
        final modality = m['architecture']?['modality'] as String? ?? '';
        final hasVision =
            inputModalities.contains('image') || modality.contains('image');

        models.add(
          AIModel(
            id: m['id'] as String,
            name: m['name'] as String? ?? m['id'] as String,
            hasVision: hasVision,
          ),
        );
      }

      models.sort((a, b) => a.id.compareTo(b.id));
      _modelCache[apiKey] = models;
      return models;
    } else {
      throw Exception('Failed to fetch models (HTTP ${response.statusCode})');
    }
  }

  static void clearModelCache() {
    _modelCache.clear();
  }
}

class SummarizeResult {
  final String? streamId;
  final String? error;

  SummarizeResult.success(this.streamId) : error = null;
  SummarizeResult.error(this.error) : streamId = null;
}

class AISummarizeService {
  static final Map<String, StreamController<String>> _chunkControllers = {};
  static final Map<String, StreamController<String>> _errorControllers = {};
  static final Map<String, StreamController<void>> _doneControllers = {};
  static final Map<String, HttpClient> _clients = {};

  static const _summarizableExtensions = {
    '.txt',
    '.md',
    '.json',
    '.csv',
    '.log',
    '.xml',
    '.yaml',
    '.yml',
    '.ini',
    '.conf',
    '.cfg',
    '.toml',
    '.env',
    '.sh',
    '.bat',
    '.py',
    '.js',
    '.ts',
    '.html',
    '.css',
    '.sql',
    '.rb',
    '.go',
    '.rs',
    '.java',
    '.c',
    '.cpp',
    '.h',
    '.hpp',
    '.tsx',
    '.jsx',
    '.vue',
    '.svelte',
    '.dart',
    '.php',
    '.r',
    '.swift',
    '.kt',
    '.pdf',
    '.docx',
    '.doc',
  };

  static const _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
    '.svg',
  };

  static Stream<String> getChunkStream(String streamId) {
    if (!_chunkControllers.containsKey(streamId)) {
      _chunkControllers[streamId] = StreamController<String>.broadcast();
    }
    return _chunkControllers[streamId]!.stream;
  }

  static Stream<String> getErrorStream(String streamId) {
    if (!_errorControllers.containsKey(streamId)) {
      _errorControllers[streamId] = StreamController<String>.broadcast();
    }
    return _errorControllers[streamId]!.stream;
  }

  static Stream<void> getDoneStream(String streamId) {
    if (!_doneControllers.containsKey(streamId)) {
      _doneControllers[streamId] = StreamController<void>.broadcast();
    }
    return _doneControllers[streamId]!.stream;
  }

  static Future<SummarizeResult> summarize({
    required String type,
    required String content,
    String? filename,
    String? filePath,
  }) async {
    final apiKey = await AISettingsService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return SummarizeResult.error('no-api-key');
    }

    final model = await AISettingsService.getModel();

    String? textContent;
    Map<String, dynamic>? imageContent;

    if (type == 'text') {
      textContent = content;
    } else if (filename != null) {
      final ext = _getExtension(filename).toLowerCase();
      final isImage = _imageExtensions.contains(ext);

      if (ext == '.docx' || ext == '.doc') {
        return SummarizeResult.error(
          'DOCX summarization is not yet supported on mobile',
        );
      }
      if (!_summarizableExtensions.contains(ext) && !isImage) {
        return SummarizeResult.error('unsupported-type');
      }

      if (filePath != null && await File(filePath).exists()) {
        if (ext == '.pdf') {
          try {
            final extracted = await _extractPdfText(filePath);
            textContent = extracted;
          } catch (e) {
            return SummarizeResult.error('Could not extract text from PDF');
          }
        } else if (isImage) {
          final hasVision = await _checkModelVisionSupport(model, apiKey);
          if (!hasVision) {
            return SummarizeResult.error('model-unsupported');
          }
          final file = File(filePath);
          final bytes = await file.readAsBytes();
          final base64Data = base64Encode(bytes);
          final mimeType = _getMimeType(filename);
          imageContent = {
            'type': 'image_url',
            'image_url': {'url': 'data:$mimeType;base64,$base64Data'},
          };
        } else {
          final stat = await File(filePath).stat();
          var fileContent = await File(filePath).readAsString();
          const maxBytes = 100 * 1024;
          if (stat.size > maxBytes) {
            fileContent =
                '${fileContent.substring(0, maxBytes)}\n\n[Content truncated, showing first 100KB]';
          }
          textContent = fileContent;
        }
      } else {
        textContent = content;
      }
    }

    final streamId = DateTime.now().millisecondsSinceEpoch.toString();
    _startStream(streamId, model, apiKey, textContent, imageContent);
    return SummarizeResult.success(streamId);
  }

  static Future<bool> _checkModelVisionSupport(
    String model,
    String apiKey,
  ) async {
    try {
      final models = await AIService.fetchModels(apiKey);
      final modelObj = models.firstWhere(
        (m) => m.id == model,
        orElse: () => AIModel(id: model, name: model),
      );
      return modelObj.hasVision ||
          model.contains('vision') ||
          model == 'openrouter/auto';
    } catch (e) {
      return model.contains('vision') || model == 'openrouter/auto';
    }
  }

  static Future<String> _extractPdfText(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final pdfDoc = spdf.PdfDocument(inputBytes: bytes);
    final extractor = spdf.PdfTextExtractor(pdfDoc);
    final text = extractor.extractText();
    pdfDoc.dispose();
    if (text.trim().isEmpty) throw Exception('Could not extract text from PDF');
    const maxBytes = 100 * 1024;
    if (utf8.encode(text).length > maxBytes) {
      return '${text.substring(0, maxBytes)}\n\n[Content truncated, showing first 100KB]';
    }
    return text;
  }

  static String _getExtension(String filename) {
    final lastDot = filename.lastIndexOf('.');
    return lastDot != -1 ? filename.substring(lastDot) : '';
  }

  static String _getMimeType(String filename) {
    final ext = _getExtension(filename).toLowerCase();
    const mimeMap = {
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.png': 'image/png',
      '.gif': 'image/gif',
      '.bmp': 'image/bmp',
      '.webp': 'image/webp',
      '.svg': 'image/svg+xml',
    };
    return mimeMap[ext] ?? 'application/octet-stream';
  }

  static Future<void> _startStream(
    String streamId,
    String model,
    String apiKey,
    String? textContent,
    Map<String, dynamic>? imageContent,
  ) async {
    final client = HttpClient();
    _clients[streamId] = client;

    try {
      final List<dynamic> messages;
      if (imageContent != null) {
        messages = [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': 'Summarize the following image concisely:',
              },
              imageContent,
            ],
          },
        ];
      } else {
        messages = [
          {
            'role': 'user',
            'content':
                'Summarize the following content concisely:\n\n$textContent',
          },
        ];
      }

      final body = jsonEncode({
        'model': model,
        'messages': messages,
        'stream': true,
      });

      final request = await client.postUrl(
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      );
      request.headers.set('Content-Type', 'application/json; charset=utf-8');
      request.headers.set('Authorization', 'Bearer $apiKey');
      request.add(utf8.encode(body));

      final response = await request.close();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        String buffer = '';
        await for (final chunk in response.transform(utf8.decoder)) {
          buffer += chunk;
          final lines = buffer.split('\n');
          buffer = lines.removeLast();

          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty || !trimmed.startsWith('data: ')) continue;

            final jsonStr = trimmed.substring(6);
            if (jsonStr == '[DONE]') {
              if (!(_doneControllers[streamId]?.isClosed ?? true)) {
                _doneControllers[streamId]?.add(null);
              }
              _cleanup(streamId);
              return;
            }

            try {
              final parsed = jsonDecode(jsonStr);
              final text =
                  parsed['choices']?[0]?['delta']?['content'] as String?;
              if (text != null && text.isNotEmpty) {
                if (!(_chunkControllers[streamId]?.isClosed ?? true)) {
                  _chunkControllers[streamId]?.add(text);
                }
              }
            } catch (e) {
              // Skip malformed JSON
            }
          }
        }

        if (!(_doneControllers[streamId]?.isClosed ?? true)) {
          _doneControllers[streamId]?.add(null);
        }
        _cleanup(streamId);
      } else {
        final errBody = await response.transform(utf8.decoder).join();
        if (!(_errorControllers[streamId]?.isClosed ?? true)) {
          _errorControllers[streamId]?.add(
            'API error (${response.statusCode}): $errBody',
          );
        }
        _cleanup(streamId);
      }
    } catch (e) {
      if (e.toString().contains('AbortException') ||
          e.toString().contains('cancelled')) {
        _cleanup(streamId);
        return;
      }
      if (!(_errorControllers[streamId]?.isClosed ?? true)) {
        _errorControllers[streamId]?.add('Network error: $e');
      }
      _cleanup(streamId);
    }
  }

  static void cancelStream(String streamId) {
    _clients[streamId]?.close(force: true);
    _cleanup(streamId);
  }

  static void _cleanup(String streamId) {
    _clients.remove(streamId);
    _chunkControllers[streamId]?.close();
    _errorControllers[streamId]?.close();
    _doneControllers[streamId]?.close();
    _chunkControllers.remove(streamId);
    _errorControllers.remove(streamId);
    _doneControllers.remove(streamId);
  }
}
