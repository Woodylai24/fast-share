import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:fast_share_mobile/ai_service.dart';
import 'package:fast_share_mobile/models/message.dart';

class SummaryBottomSheet extends StatefulWidget {
  final Message message;

  const SummaryBottomSheet({super.key, required this.message});

  @override
  State<SummaryBottomSheet> createState() => _SummaryBottomSheetState();
}

class _SummaryBottomSheetState extends State<SummaryBottomSheet> {
  String _text = '';
  bool _isStreaming = false;
  String? _error;
  String _model = '';
  String? _streamId;
  StreamSubscription<String>? _chunkSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<void>? _doneSub;

  @override
  void initState() {
    super.initState();
    _loadModel();
    _startSummarize();
  }

  Future<void> _loadModel() async {
    final model = await AISettingsService.getModel();
    setState(() => _model = model);
  }

  Future<void> _startSummarize() async {
    final hasApiKey = await AISettingsService.hasApiKey();
    if (!hasApiKey) {
      setState(() {
        _error = 'Please set up your OpenRouter API key in AI Settings';
        _isStreaming = false;
      });
      return;
    }

    String? filePath;
    if (widget.message.url != null) {
      if (widget.message.url!.startsWith('file://')) {
        filePath = widget.message.url!.replaceFirst('file://', '');
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        final fastShareDir = Directory('${appDir.path}/FastShare');
        filePath = '${fastShareDir.path}/${widget.message.filename ?? 'file'}';
        if (!await File(filePath).exists()) {
          filePath = null;
        }
      }
    }

    setState(() => _isStreaming = true);

    final result = await AISummarizeService.summarize(
      type: widget.message.type.name,
      content: widget.message.content,
      filename: widget.message.filename,
      filePath: filePath,
    );

    if (result.error != null) {
      String errorMsg = result.error!;
      if (result.error == 'no-api-key') {
        errorMsg = 'Please set up your OpenRouter API key in AI Settings';
      } else if (result.error == 'unsupported-type') {
        errorMsg = 'This file type is not yet supported for summarization.';
      } else if (result.error == 'model-unsupported') {
        errorMsg =
            'Current model does not support image input. Please select a vision-capable model.';
      }
      setState(() {
        _error = errorMsg;
        _isStreaming = false;
      });
      return;
    }

    _streamId = result.streamId;
    _setupListeners();
  }

  void _setupListeners() {
    if (_streamId == null) return;

    _chunkSub = AISummarizeService.getChunkStream(_streamId!).listen((chunk) {
      setState(() => _text += chunk);
    });

    _errorSub = AISummarizeService.getErrorStream(_streamId!).listen((error) {
      setState(() {
        _error = error;
        _isStreaming = false;
      });
    });

    _doneSub = AISummarizeService.getDoneStream(_streamId!).listen((_) {
      setState(() => _isStreaming = false);
    });
  }

  void _cancelStream() {
    if (_streamId != null) {
      AISummarizeService.cancelStream(_streamId!);
    }
    setState(() => _isStreaming = false);
  }

  @override
  void dispose() {
    _chunkSub?.cancel();
    _errorSub?.cancel();
    _doneSub?.cancel();
    if (_streamId != null) {
      AISummarizeService.cancelStream(_streamId!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isImage =
        widget.message.filename != null &&
        RegExp(
          r'\.(jpg|jpeg|png|gif|webp|bmp|svg)$',
          caseSensitive: false,
        ).hasMatch(widget.message.filename!);
    final subtitle = widget.message.filename != null
        ? '${isImage ? '📷' : '📄'} ${widget.message.filename}'
        : (widget.message.type == MessageType.text
              ? 'Clipboard Text'
              : 'Content');

    return Container(
      padding: const EdgeInsets.all(16),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🤖 AI Summary',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (_model.isNotEmpty)
                    Text(
                      'Using: $_model',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  _cancelStream();
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          Expanded(child: SingleChildScrollView(child: _buildContent())),
          if (_isStreaming)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: TextButton(
                  onPressed: _cancelStream,
                  child: const Text('Cancel'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Text('⚠️ $_error', style: const TextStyle(color: Colors.orange));
    }
    if (_text.isEmpty && _isStreaming) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 8),
            Text('Analyzing...'),
          ],
        ),
      );
    }
    return SelectableText(_text, style: const TextStyle(fontSize: 14));
  }
}
