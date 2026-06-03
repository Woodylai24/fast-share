import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fast_share_mobile/models/message.dart';

/// Message storage service for persistence
class MessageStorageService {
  static const String _messagesKey = 'saved_messages';
  static const int _maxMessages = 100;

  static Future<void> saveMessages(List<Message> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = messages.map((m) => m.toJson()).toList();
    await prefs.setString(_messagesKey, jsonEncode(jsonList));
  }

  static Future<List<Message>> loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_messagesKey);

    if (jsonString == null) return [];

    try {
      final jsonList = jsonDecode(jsonString) as List;
      return jsonList
          .map((json) => Message.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error loading messages: $e');
      return [];
    }
  }

  static Future<void> clearMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_messagesKey);
  }
}
