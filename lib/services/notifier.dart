import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications — fires when a new return OTP shows up.
class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int _id = 0;

  static Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  static Future<void> show({required String title, required String body}) async {
    if (!_ready) await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'otpflow_otps',
        'New OTPs',
        channelDescription: 'Alerts when a new return OTP arrives',
        importance: Importance.high,
        priority: Priority.high,
        color: Color.fromARGB(255, 30, 136, 255),
      ),
    );
    await _plugin.show(_id++, title, body, details);
  }
}
