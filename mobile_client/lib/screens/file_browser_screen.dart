import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fast_share_mobile/services/file_storage.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  List<File> _files = [];
  bool _isLoading = true;
  bool _isSelectMode = false;
  final Set<int> _selectedIndices = {};

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _isLoading = true);
    try {
      final dir = await FileStorage.getFastShareDir();
      if (await dir.exists()) {
        final entities = await dir.list().toList();
        final files = entities.whereType<File>().toList();
        // Sort by date, newest first
        files.sort((a, b) =>
            FileStat.statSync(b.path).modified.compareTo(
                  FileStat.statSync(a.path).modified,
                ));
        if (mounted) {
          setState(() {
            _files = files;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _files = [];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _files = [];
          _isLoading = false;
        });
      }
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;

    String dayLabel;
    if (diff == 0) {
      dayLabel = 'Today';
    } else if (diff == 1) {
      dayLabel = 'Yesterday';
    } else {
      dayLabel =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    return '$dayLabel ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  bool _isImageFile(String filename) {
    return RegExp(r'\.(jpg|jpeg|png|gif|webp|bmp)$', caseSensitive: false)
        .hasMatch(filename);
  }

  IconData _fileIcon(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
        return Icons.image;
      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
        return Icons.videocam;
      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'flac':
        return Icons.audio_file;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  // ── Select mode ────────────────────────────────────────────────────

  void _toggleSelection(int index) {
    setState(() {
      _isSelectMode = true;
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
        if (_selectedIndices.isEmpty) _isSelectMode = false;
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  void _exitSelectMode() {
    setState(() {
      _isSelectMode = false;
      _selectedIndices.clear();
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIndices.clear();
      for (int i = 0; i < _files.length; i++) {
        _selectedIndices.add(i);
      }
    });
  }

  // ── Actions ────────────────────────────────────────────────────────

  Future<void> _openFile(File file) async {
    await OpenFilex.open(file.path);
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIndices.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Files'),
        content: Text('Delete $count file${count == 1 ? '' : 's'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final idx in _selectedIndices.toList()) {
      final file = _files[idx];
      if (await file.exists()) await file.delete();
    }
    _exitSelectMode();
    await _loadFiles();
  }

  Future<void> _shareSelected() async {
    final files = _selectedIndices.map((i) => _files[i]).toList();
    await Share.shareXFiles(
      files.map((f) => XFile(f.path)).toList(),
    );
    _exitSelectMode();
  }

  Future<void> _deleteSingle(File file) async {
    final filename = file.uri.pathSegments.last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Delete $filename?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (await file.exists()) await file.delete();
    await _loadFiles();
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !_isSelectMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isSelectMode) {
          _exitSelectMode();
        }
      },
      child: Scaffold(
        appBar: _isSelectMode ? _buildSelectionAppBar(isDark) : _buildNormalAppBar(isDark),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _files.isEmpty
                ? _buildEmptyState(isDark)
                : _buildFileList(isDark),
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar(bool isDark) {
    return AppBar(
      title: Text(
        'Files',
        style: TextStyle(color: isDark ? Colors.white : null),
      ),
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(bool isDark) {
    final count = _selectedIndices.length;
    final allSelected = _selectedIndices.length == _files.length;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelectMode,
      ),
      title: Text(
        '$count selected',
        style: TextStyle(color: isDark ? Colors.white : null),
      ),
      actions: [
        TextButton(
          onPressed: allSelected ? null : _selectAll,
          child: Text(
            'Select All',
            style: TextStyle(
              color: allSelected
                  ? (isDark ? Colors.grey[600] : Colors.grey)
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.share),
          tooltip: 'Share',
          onPressed: _shareSelected,
        ),
        IconButton(
          icon: const Icon(Icons.delete),
          tooltip: 'Delete',
          onPressed: _deleteSelected,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 64,
            color: isDark ? Colors.grey[600] : Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            'No files yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey[400] : Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Files you receive will appear here',
            style: TextStyle(
              color: isDark ? Colors.grey[500] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(bool isDark) {
    // Compute total size
    int totalBytes = 0;
    for (final f in _files) {
      try {
        totalBytes += FileStat.statSync(f.path).size;
      } catch (_) {}
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _files.length,
            itemBuilder: (context, index) {
              final file = _files[index];
              return _buildFileItem(file, index, isDark);
            },
          ),
        ),
        // Storage footer
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[100],
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
            ),
          ),
          child: Text(
            '${_formatFileSize(totalBytes)} in ${_files.length} file${_files.length == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildFileItem(File file, int index, bool isDark) {
    final stat = FileStat.statSync(file.path);
    final filename = file.uri.pathSegments.last;
    final isSelected = _selectedIndices.contains(index);
    final isImage = _isImageFile(filename);

    Widget leading;
    if (isImage && !_isSelectMode) {
      // Show thumbnail for images
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          file,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            _fileIcon(filename),
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      );
    } else if (_isSelectMode) {
      leading = Checkbox(
        value: isSelected,
        onChanged: (_) => _toggleSelection(index),
      );
    } else {
      leading = Icon(
        _fileIcon(filename),
        color: isDark ? Colors.grey[400] : Colors.grey[600],
      );
    }

    final tile = ListTile(
      leading: leading,
      title: Text(
        filename,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isDark ? Colors.white : null,
        ),
      ),
      subtitle: Text(
        '${_formatFileSize(stat.size)}  ·  ${_formatDate(stat.modified)}',
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
      onTap: _isSelectMode
          ? () => _toggleSelection(index)
          : () => _openFile(file),
      onLongPress: _isSelectMode
          ? null
          : () => _toggleSelection(index),
    );

    if (_isSelectMode) {
      // No swipe-to-delete in select mode
      return tile;
    }

    return Dismissible(
      key: ValueKey(file.path),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _deleteSingle(file).then((_) => false),
      // We handle deletion in confirmDismiss, so onDismissed is never called
      onDismissed: (_) {},
      child: tile,
    );
  }
}
