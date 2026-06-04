import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firebase_options.dart';
import 'package:fast_share_mobile/services/notifications.dart';
import 'package:fast_share_mobile/services/theme_notifier.dart';
import 'package:fast_share_mobile/theme/app_theme.dart';
import 'package:fast_share_mobile/screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) async {
      final String? payload = response.payload;
      if (payload != null) {
        if (payload.startsWith('COPY:')) {
          final String textToCopy = payload.substring(5);
          await Clipboard.setData(ClipboardData(text: textToCopy));
        } else if (payload.startsWith('OPEN_APP:')) {
          // Open the app when notification is tapped
          // The app will automatically reconnect via lifecycle observer
          debugPrint('[DEBUG] Notification tapped, opening app');
        } else {
          final Uri url = Uri.parse(payload);
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      }
    },
  );

  // Request permission for notifications (iOS)
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  // Get FCM token
  final fcmToken = await FirebaseMessaging.instance.getToken();
  debugPrint('[DEBUG] FCM Token: $fcmToken');

  // Save FCM token for later use
  final prefs = await SharedPreferences.getInstance();
  if (fcmToken != null) {
    await prefs.setString('fcm_token', fcmToken);
  }

  // Listen for token refresh
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
    debugPrint('[DEBUG] FCM Token refreshed: $newToken');
    prefs.setString('fcm_token', newToken);
  });

  // Handle background messages
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Handle foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint(
      '[DEBUG] Received foreground message: ${message.notification?.title}',
    );
    if (message.notification != null) {
      showLocalNotification(
        message.notification!.title ?? 'Fast Share',
        message.notification!.body ?? '',
        payload: message.data['payload'],
      );
    }
  });

  // Handle message when app is opened from background via notification
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    debugPrint('[DEBUG] Message opened app: ${message.notification?.title}');
    // The app will automatically reconnect via lifecycle observer
  });

  // Create and initialize theme notifier
  final ThemeNotifier themeNotifier = ThemeNotifier();
  await themeNotifier.init();

  runApp(FastShareApp(themeNotifier: themeNotifier));
}

class FastShareApp extends StatelessWidget {
  final ThemeNotifier themeNotifier;

  const FastShareApp({super.key, required this.themeNotifier});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeNotifier,
      builder: (context, child) {
        return MaterialApp(
          title: 'Fast Share Mobile',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeNotifier.mode,
          home: child,
        );
      },
      child: HomeScreen(themeNotifier: themeNotifier),
    );
  }
}
