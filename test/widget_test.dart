import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:remind/services/database_service.dart';
import 'package:remind/screens/notes_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseService.instance.init();
  });

  testWidgets('notes screen launches', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: NotesScreen()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('Tap + to add a note or folder'), findsOneWidget);
  });
}
