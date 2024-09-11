import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotifications {
  static final _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future init() async {
    await _firebaseMessaging.requestPermission(
      provisional: true
    );

    final token = await _firebaseMessaging.getToken();
    print("device token: $token");
  }

  static Future initLocalNotifications() async {
    const AndroidInitializationSettings androidInitializationSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    final DarwinInitializationSettings iOSinitializationSettings = DarwinInitializationSettings(
      onDidReceiveLocalNotification: (id, title, body, payload) => null,
    );
    final InitializationSettings initializationSettings = InitializationSettings(
      android: androidInitializationSettings,
      iOS: iOSinitializationSettings
    );

    _flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()!
      .requestNotificationsPermission();

    _flutterLocalNotificationsPlugin.initialize(initializationSettings,
      onDidReceiveNotificationResponse: onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: onNotificationTap);
  }

  static void onNotificationTap(notificationresponse) {
  }

  //local notifications
  static Future showSimpleNotification({
    required String title,
    required String body,
    required String payload,
  }) async {
    const AndroidNotificationDetails androidNotificationDetails = 
      AndroidNotificationDetails('infinite_sports_notifications', 'Infinite Sports App Notifications',
        channelDescription: 'Incoming Infinite Sports notifications',
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'ticker');
    const NotificationDetails notificationDetails =
      NotificationDetails(
        android: androidNotificationDetails
      );
    await _flutterLocalNotificationsPlugin
      .show(0, title, body, notificationDetails, payload: payload);
  }
}