import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FileStorage {
  static const _migratedKey = 'file_storage_migrated_v2';
  static const _mediaChannel = MethodChannel('fast_share/media');

  /// Returns the external FastShare directory.
  /// Creates it if it doesn't exist.
  static Future<Directory> getFastShareDir() async {
    final externalDir = await getExternalStorageDirectory();
    if (externalDir == null) {
      // Fallback to internal if external unavailable
      final appDir = await getApplicationDocumentsDirectory();
      final fallback = Directory('${appDir.path}/FastShare');
      if (!await fallback.exists()) {
        await fallback.create(recursive: true);
      }
      return fallback;
    }
    final fastShareDir = Directory('${externalDir.path}/FastShare');
    if (!await fastShareDir.exists()) {
      await fastShareDir.create(recursive: true);
    }
    return fastShareDir;
  }

  /// Migrate files from old internal storage to new external storage.
  /// Runs once; sets a flag in SharedPreferences to avoid re-running.
  static Future<void> migrateIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migratedKey) == true) return;

    try {
      final oldDir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/FastShare',
      );
      final newDir = await getFastShareDir();

      if (await oldDir.exists()) {
        await for (final entity in oldDir.list()) {
          if (entity is File) {
            final filename = entity.uri.pathSegments.last;
            final newPath = '${newDir.path}/$filename';
            // Don't overwrite if file already exists in new location
            if (!await File(newPath).exists()) {
              await entity.rename(newPath);
            } else {
              await entity.delete();
            }
          }
        }
        // Remove old directory if empty
        if (await oldDir.list().isEmpty) {
          await oldDir.delete();
        }
      }
    } catch (e) {
      // Don't block app launch if migration fails
      print('[FileStorage] Migration failed: $e');
    }

    await prefs.setBool(_migratedKey, true);
  }

  /// Notify Android MediaStore about a new file so Gallery apps see it.
  static Future<void> scanFile(String filePath) async {
    try {
      await _mediaChannel.invokeMethod('scanFile', {'path': filePath});
    } catch (e) {
      print('[FileStorage] Media scan failed: $e');
    }
  }
}
