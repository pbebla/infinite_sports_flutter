import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotifications {
  static final _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future init() async {
    await _firebaseMessaging.requestPermission(
      provisional: true
    );
    final apns = await _firebaseMessaging.getAPNSToken();
    final token = await _firebaseMessaging.getToken();
    print("device token: $token");
  }

  static Future initLocalNotifications() async {
    const AndroidInitializationSettings androidInitializationSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    final DarwinInitializationSettings iOSinitializationSettings = DarwinInitializationSettings();
    final InitializationSettings initializationSettings = InitializationSettings(
      android: androidInitializationSettings,
      iOS: iOSinitializationSettings
    );

    if (Platform.isAndroid) {
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()!
          .requestNotificationsPermission();
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
    const iosNotificationDetails = DarwinNotificationDetails();
    const NotificationDetails notificationDetails =
      NotificationDetails(
        android: androidNotificationDetails,
        iOS: iosNotificationDetails
      );
    await _flutterLocalNotificationsPlugin
      .show(0, title, body, notificationDetails, payload: payload);
  }
}
