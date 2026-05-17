import 'dart:io' show Platform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'kelivo_bg_chat_v2',
    'Chat Background',
    description: 'Notifications for chat generation status',
    importance: Importance.high,
    playSound: true,
  );
  static const AndroidNotificationChannel _proactiveChannel =
      AndroidNotificationChannel(
        'kelivo_proactive_v1',
        '澄的消息',
        description: '澄主动发送的消息',
        importance: Importance.high,
        playSound: true,
      );

  static Future<void> ensureInitialized() async {
    if (!Platform.isAndroid) return;
    await ensureInitializedForPlatform();
  }

  static Future<void> ensureInitializedForPlatform() async {
    if (_inited) return;

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings init = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _plugin.initialize(init);

    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        await android.createNotificationChannel(_channel);
        await android.createNotificationChannel(_proactiveChannel);
      }
    }
    if (Platform.isIOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
    }
    _inited = true;
  }

  /// Ensure Android 13+ notifications permission is granted.
  static Future<bool> ensureAndroidNotificationsPermission() async {
    if (!Platform.isAndroid) return true;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return true;
    try {
      final enabled = await android.areNotificationsEnabled();
      if (enabled == true) return true;
    } catch (_) {}
    try {
      final ok = await android.requestNotificationsPermission();
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> showChatCompleted({String? title, String? body}) async {
    if (!Platform.isAndroid) return;
    await ensureInitialized();
    await _plugin.show(
      2001,
      title ?? 'Generation complete',
      body ?? 'Assistant reply has been generated',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          category: AndroidNotificationCategory.message,
          visibility: NotificationVisibility.public,
          ticker: 'Kelivo',
          styleInformation: const DefaultStyleInformation(true, true),
        ),
      ),
    );
  }

  static Future<void> showProactive({required String content}) async {
    await ensureInitializedForPlatform();
    final androidDetails = AndroidNotificationDetails(
      _proactiveChannel.id,
      _proactiveChannel.name,
      channelDescription: _proactiveChannel.description,
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(content),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    await _plugin.show(
      3001,
      '✦ 澄找你',
      content,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }
}
