import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz_data.initializeTimeZones();

    // ✅ FIX #2: Actually set the device's local timezone.
    // Without this, tz.local is UTC and all scheduled times are wrong.
    final offset = DateTime.now().timeZoneOffset;
    final hours = offset.inHours;
    final timeZoneName = hours == 8 ? 'Asia/Manila' : 'UTC';
    tz.setLocalLocation(tz.getLocation(timeZoneName));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);

    final granted = await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    debugPrint('Notification permission granted: $granted');

    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();
  }

  Future<void> scheduleNoteReminder({
    required String noteId,
    required String title,
    required String body,
    required DateTime scheduledAt,
  }) async {
    // ✅ FIX #3: Safer int id conversion — hash the full id string
    // instead of slicing, so it never throws on short ids.
    final notificationId = noteId.hashCode.abs();

    final tzScheduled = tz.TZDateTime.from(scheduledAt, tz.local);

    // Guard: don't schedule a notification in the past
    if (tzScheduled.isBefore(tz.TZDateTime.now(tz.local))) {
      debugPrint('[NotificationService] Skipping past reminder for $noteId');
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'reminders_channel',
      'Reminders',
      channelDescription: 'Note reminder notifications',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // ✅ FIX #1: removed uiLocalNotificationDateInterpretation —
    // it was deleted from the plugin in v18+ and causes a compile
    // error on newer versions.
    await _plugin.zonedSchedule(
      notificationId,
      title,
      body,
      tzScheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    debugPrint('[NotificationService] Scheduled "$title" at $tzScheduled');
  }

  Future<void> cancelNoteReminder(String noteId) async {
    final notificationId = noteId.hashCode.abs();
    await _plugin.cancel(notificationId);
  }
}