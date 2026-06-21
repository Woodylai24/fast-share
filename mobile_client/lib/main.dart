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
import 'package:fast_share_mobile/screens/onboarding_screen.dart';
import 'package:fast_share_mobile/screens/chat_screen.dart';
import 'package:fast_share_mobile/services/settings_service.dart';
import 'package:fast_share_mobile/services/file_storage.dart';

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

  // Migrate files from old internal storage to new external storage
  await FileStorage.migrateIfNeeded();

  runApp(FastShareApp(themeNotifier: themeNotifier));
}

class FastShareApp extends StatefulWidget {
  final ThemeNotifier themeNotifier;

  const FastShareApp({super.key, required this.themeNotifier});

  @override
  State<FastShareApp> createState() => _FastShareAppState();
}

class _FastShareAppState extends State<FastShareApp> {
  bool _onboardingComplete = false;
  ({String ip, int port, int httpPort})? _lastConnection;

  @override
  void initState() {
    super.initState();
    _loadLaunchState();
  }

  Future<void> _loadLaunchState() async {
    final complete = await SettingsService.getOnboardingComplete();
    // Only look up a saved pairing once onboarding is done — there can't be
    // one before the user has been through the intro flow.
    final lastConn = complete ? await SettingsService.getLastConnection() : null;
    if (mounted) {
      setState(() {
        _onboardingComplete = complete;
        _lastConnection = lastConn;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.themeNotifier,
      builder: (context, child) {
        return MaterialApp(
          title: 'Fast Share Mobile',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: widget.themeNotifier.mode,
          // WhatsApp-like routing:
          //  - Onboarding not done → OnboardingScreen
          //  - Returning user with a saved pairing → ChatScreen (auto-connects)
          //  - First launch / unpaired → HomeScreen (QR scanner + manual IP)
          home: _homeScreen(),
        );
      },
    );
  }

  Widget _homeScreen() {
    if (!_onboardingComplete) {
      return OnboardingScreen(
        onComplete: () {
          setState(() => _onboardingComplete = true);
        },
      );
    }

    final conn = _lastConnection;
    if (conn != null) {
      return ConnectedScreen(
        ip: conn.ip,
        port: conn.port,
        httpPort: conn.httpPort,
        themeNotifier: widget.themeNotifier,
      );
    }

    return HomeScreen(themeNotifier: widget.themeNotifier);
  }
}
