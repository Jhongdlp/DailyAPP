import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistem_daily/features/habits/habit_form_dialog.dart';
import 'package:sistem_daily/core/models/habit_template.dart';

void main() {
  testWidgets('showHabitFormDialog renders without errors for custom creation', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => showHabitFormDialog(context, ref),
                child: const Text('Open Custom'),
              ),
            ),
          ),
        ),
      ),
    );

    // Tap button to open dialog
    await tester.tap(find.text('Open Custom'));
    await tester.pumpAndSettle();

    // Check if dialog is visible and has no errors
    expect(find.text('Nuevo hábito'), findsOneWidget);
  });

  testWidgets('showHabitFormDialog renders without errors for "Tomar agua" template', (WidgetTester tester) async {
    final template = kHabitTemplates.firstWhere((t) => t.name == 'Tomar agua');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => showHabitFormDialog(context, ref, template: template),
                child: const Text('Open Template'),
              ),
            ),
          ),
        ),
      ),
    );

    // Tap button to open dialog
    await tester.tap(find.text('Open Template'));
    await tester.pumpAndSettle();

    // Check if dialog is visible and has no errors
    expect(find.text('Nuevo hábito'), findsOneWidget);
  });
}
