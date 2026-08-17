/// 本地通知：agent 提问 / DSH 状态告警。
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  int _seq = 0;
  bool _ready = false;

  Future<void> init() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
    _ready = true;
  }

  Future<void> show(String title, String body) async {
    if (!_ready) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'dsh_gateway',
        'DSH 网关提醒',
        channelDescription: 'agent 提问与 DSH 状态告警',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(++_seq, title, body, details);
  }
}
