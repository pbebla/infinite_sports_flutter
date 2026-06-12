import 'dart:io';
import 'dart:ui' show Brightness, Color, PlatformDispatcher;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:infinite_sports_flutter/misc/notification_router.dart';

class PushNotifications {
  static final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future init() async {
    await FirebaseMessaging.instance.requestPermission(
      provisional: true
    );
  }

  /// Channel id shared with the Watcher's FCM sends (functions/src/lib/fcm.ts)
  /// and the manifest's default_notification_channel_id. Max importance makes
  /// alerts banner-pop instead of arriving silently in the tray.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'infinite_sports_notifications',
    'Infinite Sports App Notifications',
    description: 'Incoming Infinite Sports notifications',
    importance: Importance.max,
  );

  static Future initLocalNotifications() async {
    const AndroidInitializationSettings androidInitializationSettings = AndroidInitializationSettings('@drawable/ic_notification');
    final DarwinInitializationSettings iOSinitializationSettings = DarwinInitializationSettings();
    final InitializationSettings initializationSettings = InitializationSettings(
      android: androidInitializationSettings,
      iOS: iOSinitializationSettings
    );

    if (Platform.isAndroid) {
      final androidPlugin = _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()!;
      await androidPlugin.requestNotificationsPermission();
      await androidPlugin.createNotificationChannel(_channel);
    }

    if (Platform.isIOS) {
      await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true
        );
    }

    await _flutterLocalNotificationsPlugin.initialize(initializationSettings,
      onDidReceiveNotificationResponse: onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: onNotificationTap);
  }

  static void onNotificationTap(NotificationResponse notificationResponse) {
    openMatchFromPayloadString(notificationResponse.payload);
  }

  //local notifications
  static Future showSimpleNotification({
    required String title,
    required String body,
    required String payload,
  }) async {
    // Brand-red tint for the small stencil icon; full-color logo on a solid
    // square (Robinhood-style) as the large icon — white square in light
    // mode, black square in dark mode, matching the phone's theme.
    final isDark =
        PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    final androidNotificationDetails =
      AndroidNotificationDetails('infinite_sports_notifications', 'Infinite Sports App Notifications',
        channelDescription: 'Incoming Infinite Sports notifications',
        importance: Importance.max,
        priority: Priority.high,
        color: const Color(0xFFD00000),
        largeIcon: DrawableResourceAndroidBitmap(
            isDark ? 'ic_notification_large_dark' : 'ic_notification_large_light'),
        ticker: 'ticker');
    const iosNotificationDetails = DarwinNotificationDetails();
    final NotificationDetails notificationDetails =
      NotificationDetails(
        android: androidNotificationDetails,
        iOS: iosNotificationDetails
      );
    // Unique id per alert so a goal doesn't overwrite the kickoff in the tray.
    final id = DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
    await _flutterLocalNotificationsPlugin
      .show(id, title, body, notificationDetails, payload: payload);
  }
}
