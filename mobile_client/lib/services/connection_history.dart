import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fast_share_mobile/models/connection_entry.dart';

/// Service to manage connection history
class ConnectionHistoryService {
  static const String _historyKey = 'connection_history';
  static const String _lastNetworkKey = 'last_network_name';
  static const int _maxHistorySize = 10;

  static Future<SharedPreferences> get _prefs async {
    return await SharedPreferences.getInstance();
  }

  /// Save a connection to history
  static Future<void> saveConnection(ConnectionEntry entry) async {
    final prefs = await _prefs;
    final history = await getConnectionHistory();

    // Remove existing entry with same IP
    history.removeWhere((e) => e.ip == entry.ip);

    // Add new entry at the beginning
    history.insert(0, entry);

    // Keep only the last _maxHistorySize entries
    if (history.length > _maxHistorySize) {
      history.removeRange(_maxHistorySize, history.length);
    }

    // Save to preferences
    final jsonList = history.map((e) => e.toJson()).toList();
    await prefs.setString(_historyKey, jsonEncode(jsonList));

    // Save network name
    if (entry.networkName != null) {
      await prefs.setString(_lastNetworkKey, entry.networkName!);
    }
  }

  /// Get connection history
  static Future<List<ConnectionEntry>> getConnectionHistory() async {
    final prefs = await _prefs;
    final jsonString = prefs.getString(_historyKey);

    if (jsonString == null) return [];

    try {
      final jsonList = jsonDecode(jsonString) as List;
      return jsonList
          .map((json) => ConnectionEntry.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error loading connection history: $e');
      return [];
    }
  }

  /// Get the last connected entry
  static Future<ConnectionEntry?> getLastConnection() async {
    final history = await getConnectionHistory();
    return history.isNotEmpty ? history.first : null;
  }

  /// Get the last network name
  static Future<String?> getLastNetworkName() async {
    final prefs = await _prefs;
    return prefs.getString(_lastNetworkKey);
  }

  /// Remove a connection from history
  static Future<void> removeConnection(String ip) async {
    final prefs = await _prefs;
    final history = await getConnectionHistory();

    history.removeWhere((e) => e.ip == ip);

    final jsonList = history.map((e) => e.toJson()).toList();
    await prefs.setString(_historyKey, jsonEncode(jsonList));
  }

  /// Clear all history
  static Future<void> clearHistory() async {
    final prefs = await _prefs;
    await prefs.remove(_historyKey);
    await prefs.remove(_lastNetworkKey);
  }
}
