import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[DEBUG] Background message: ${message.notification?.title}');
}

// Helper function to show local notification
Future<void> showLocalNotification(
  String title,
  String body, {
  String? payload,
}) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
        'fast_share_channel',
        'Fast Share Notifications',
        channelDescription: 'Notifications for Fast Share messages and files',
        importance: Importance.max,
        priority: Priority.high,
      );
  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
  );

  await flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecond,
    title,
    body,
    platformChannelSpecifics,
    payload: payload ?? 'OPEN_APP:',
  );
}
