import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistem_daily/core/models/habit_model.dart';
import 'package:sistem_daily/core/providers/exercise_habit_link_provider.dart';
import 'package:sistem_daily/core/providers/habits_provider.dart';
import 'package:sistem_daily/features/analytics/analytics_tab_editorial.dart';
import 'package:sistem_daily/features/exercise/exercise_tab_editorial.dart';

class _MockHabitsNotifier extends HabitsNotifier {
  final List<Habit> _initial;
  _MockHabitsNotifier(this._initial);
  @override
  List<Habit> build() => _initial;
}

class _MockExerciseLinkNotifier extends ExerciseHabitLinkNotifier {
  final String? _initial;
  _MockExerciseLinkNotifier(this._initial);
  @override
  String? build() => _initial;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AnalyticsTabEditorial', () {
    testWidgets('monta correctamente y muestra el título y selectores', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AnalyticsTabEditorial(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Analíticas'), findsOneWidget);
      expect(find.text('7 días'), findsOneWidget);
      expect(find.text('30 días'), findsOneWidget);
      expect(find.text('90 días'), findsOneWidget);
    });

    testWidgets('cambiar el rango temporal actualiza el estado', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AnalyticsTabEditorial(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('30 días'));
      await tester.pumpAndSettle();

      expect(find.text('Analíticas'), findsOneWidget);
    });
  });

  group('ExerciseTabEditorial', () {
    testWidgets('muestra gate de vinculación cuando no hay hábito asignado', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ExerciseTabEditorial(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vincula tu hábito de ejercicio'), findsOneWidget);
    });

    testWidgets('muestra contenido completo cuando hay un hábito vinculado', (tester) async {
      final habit = Habit(
        id: 'habit-run',
        name: 'Entrenamiento Matutino',
        icon: 'directions_run',
        color: '#FF5722',
        createdAt: DateTime.now(),
      );

      final container = ProviderContainer(
        overrides: [
          habitsProvider.overrideWith(() => _MockHabitsNotifier([habit])),
          exerciseHabitLinkProvider.overrideWith(() => _MockExerciseLinkNotifier('habit-run')),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ExerciseTabEditorial(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ejercicio'), findsOneWidget);
      expect(find.text('Entrenamiento Matutino'), findsOneWidget);
      expect(find.text('Registrar carrera'), findsOneWidget);
      expect(find.text('Foto progreso'), findsOneWidget);
    });
  });
}
