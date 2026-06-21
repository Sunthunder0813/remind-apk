import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'services/database_service.dart';
import 'services/notification_service.dart';
import 'services/anime_like_service.dart';
import 'services/widget_service.dart';

// Fixed name the background isolate (widgetBackgroundCallback) looks this
// port up by via IsolateNameServer — this is how a checklist toggle made
// from the home screen widget can notify an already-open, already-
// frontmost NoteEditorScreen INSTANTLY, with no polling delay. Hive's own
// box.watch() can't do this (it's scoped to one isolate's Box object —
// see widget_service.dart/note_editor_screen.dart comments for the full
// story of why that didn't work), but raw isolate-to-isolate messaging
// via IsolateNameServer works regardless of which isolate sent it.
const String kChecklistUpdatePortName = 'remind_checklist_update_port';

// Broadcast stream any number of open screens can subscribe to — backed
// by the ReceivePort registered below. Using a StreamController instead
// of having each screen register its own named port avoids two screens
// fighting over the same registered name (IsolateNameServer only allows
// ONE port per name at a time).
final StreamController<dynamic> checklistUpdateStream = StreamController<dynamic>.broadcast();

// main() is now async because we need to wait for Hive to initialize
// before the app UI starts rendering
void main() async {
  // Required when doing async work before runApp()
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize our local database
  await DatabaseService.instance.init();
  await NotificationService.instance.init();

  // Populate the in-memory Liked/Watchlisted cache from Hive — must run
  // after DatabaseService.init() since it reads from the saved_anime box.
  AnimeLikeService.instance.loadFromHive();

  // Push today's todos to the Android home screen widget on every cold
  // start, so it's accurate even if the user hasn't opened the Calendar
  // tab yet this session.
  await WidgetService.refreshWidget(DatabaseService.instance.getAllNotes());

  // Lets the native side wake widgetBackgroundCallback (in widget_service.dart)
  // whenever a checklist checkbox is tapped on the home screen widget.
  await HomeWidget.registerBackgroundCallback(widgetBackgroundCallback);

  // Registers the single ReceivePort that the background isolate sends
  // toggle notifications into. Messages received here are immediately
  // re-broadcast on checklistUpdateStream for any open screen to react to.
  IsolateNameServer.removePortNameMapping(kChecklistUpdatePortName); // clear any stale mapping from a previous hot restart
  final receivePort = ReceivePort();
  IsolateNameServer.registerPortWithName(receivePort.sendPort, kChecklistUpdatePortName);
  receivePort.listen((message) {
    checklistUpdateStream.add(message);
  });

  runApp(const RemindApp());
}

class RemindApp extends StatelessWidget {
  const RemindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Remind',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const HomeScreen(),
    );
  }
}