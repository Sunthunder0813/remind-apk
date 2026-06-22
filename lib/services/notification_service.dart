import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // Fires with a noteId every time the user taps a reminder notification
  // while the app is already running (warm tap — onDidReceiveNotificationResponse).
  // main.dart listens on this to push NoteEditorScreen for that note. The
  // COLD-start case (app fully closed, notification launches it) is handled
  // separately via getNotificationAppLaunchDetails() in init(), since the
  // plugin's tap callback doesn't fire for the launch that's already in
  // progress when the process starts fresh.
  final StreamController<String> noteTapStream = StreamController<String>.broadcast();

  Future<void> init() async {
    tz_data.initializeTimeZones();

    // Reads the device's REAL IANA timezone name (e.g. "Asia/Manila",
    // "America/New_York") instead of guessing from the raw UTC offset —
    // the old offset-based guess only worked by coincidence for devices
    // exactly at UTC+8, and silently fell back to UTC for every other
    // device/timezone, which is why notifications didn't fire correctly
    // on a different phone.
    String timeZoneName;
    try {
      timeZoneName = await FlutterTimezone.getLocalTimezone();
    } catch (e) {
      debugPrint('[NotificationService] Failed to read device timezone, falling back to UTC: $e');
      timeZoneName = 'UTC';
    }
    try {
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      debugPrint('[NotificationService] Unknown timezone "$timeZoneName", falling back to UTC: $e');
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

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

    await _plugin.initialize(
      settings,
      // Warm tap: app is already running (foreground or background) when
      // the user taps the notification. payload is whatever string we
      // passed into zonedSchedule below — here, just the raw noteId.
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final noteId = response.payload;
        if (noteId != null && noteId.isNotEmpty) {
          debugPrint('[NotificationService] Warm tap, noteId: $noteId');
          noteTapStream.add(noteId);
        }
      },
    );

    final granted = await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    debugPrint('Notification permission granted: $granted');

    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();
  }

  // Cold start: the app process wasn't running at all, and THIS launch
  // was caused by the user tapping a notification. The plugin can't fire
  // onDidReceiveNotificationResponse for that tap (nothing was listening
  // yet when it happened) — instead it remembers the launch details and
  // hands them back here once initialize() has run. Returns the noteId
  // payload if that's what happened, or null for an ordinary cold start.
  Future<String?> getLaunchNoteId() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    final payload = details.notificationResponse?.payload;
    debugPrint('[NotificationService] Cold-start launch noteId: $payload');
    return (payload != null && payload.isNotEmpty) ? payload : null;
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
      // payload carries the noteId through to the tap handler above —
      // this is the only way the handler knows WHICH note to open.
      payload: noteId,
    );

    debugPrint('[NotificationService] Scheduled "$title" at $tzScheduled');
  }

  Future<void> cancelNoteReminder(String noteId) async {
    final notificationId = noteId.hashCode.abs();
    await _plugin.cancel(notificationId);
  }
}