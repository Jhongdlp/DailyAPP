import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistem_daily/features/pomodoro/pomodoro_screen.dart';
import 'package:sistem_daily/features/pomodoro/providers/pomodoro_provider.dart';
import 'package:sistem_daily/features/pomodoro/widgets/break_panels.dart';
import 'package:sistem_daily/features/pomodoro/widgets/focus_dial.dart';

/// El pomodoro no toca Supabase para pintarse (las estadísticas y las tareas
/// caen a vacío sin credenciales), así que la pantalla sí se puede montar de
/// verdad. Esto cubre lo que el analizador no ve: que quepa.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── Que no se corte en ninguna pantalla ────────────────────────────────

  group('layout', () {
    /// Cada tamaño se prueba en las dos fases porque el cuerpo cambia por
    /// completo: en enfoque manda la tarea, en descanso el panel.
    const sizes = <String, Size>{
      'móvil vertical': Size(390, 844),
      'móvil horizontal': Size(844, 390),
      'móvil bajo horizontal': Size(640, 360),
      'móvil pequeño vertical': Size(320, 568),
      'tablet vertical': Size(834, 1112),
      'tablet horizontal': Size(1112, 834),
    };

    Future<void> pumpAt(
      WidgetTester tester,
      Size size, {
      required bool onBreak,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(pomodoroProvider.notifier);
      // Sin encadenado automático no queda ningún `Timer` vivo al acabar el
      // test, que es lo que el framework marcaría como fuga.
      notifier.configure(
        workDuration: 25,
        breakDuration: 5,
        longBreakDuration: 15,
        autoStartBreaks: false,
        autoStartFocus: false,
        breakPanelMode: 0,
      );
      if (onBreak) notifier.skip();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PomodoroScreen()),
        ),
      );
      await tester.pump();
    }

    for (final entry in sizes.entries) {
      for (final onBreak in [false, true]) {
        final phase = onBreak ? 'descanso' : 'enfoque';
        testWidgets('${entry.key} en $phase cabe sin desbordar', (tester) async {
          await pumpAt(tester, entry.value, onBreak: onBreak);
          // Un RenderFlex desbordado lanza durante el layout: si algo se
          // saliera de la pantalla, esto dejaría de ser null.
          expect(tester.takeException(), isNull);
          expect(find.byType(PomodoroScreen), findsOneWidget);

          // Y la promesa fuerte: la estructura entra entera, sin deslizar. Un
          // panel puede tener scroll propio (la agenda es una lista), pero el
          // esqueleto —reloj, controles, tira del día— no puede estar dentro
          // de uno: era exactamente el síntoma reportado en horizontal.
          for (final anchor in [
            find.byType(FocusDial),
            find.byType(BreakPanelTabs),
          ]) {
            if (anchor.evaluate().isEmpty) continue;
            expect(
              find.ancestor(
                of: anchor,
                matching: find.byType(SingleChildScrollView),
              ),
              findsNothing,
              reason: 'la pantalla no debe necesitar scroll para caber',
            );
          }
        });
      }
    }

    testWidgets('en horizontal el reloj sigue siendo grande, no un residuo',
        (tester) async {
      await pumpAt(tester, const Size(844, 390), onBreak: false);
      // Ceder el sitio sobrante no puede degenerar en un dial diminuto: si
      // esto baja, es que el resto de la columna ha engordado de más.
      expect(tester.getSize(find.byType(FocusDial)).width,
          greaterThanOrEqualTo(200));
    });

    for (final onBreak in [false, true]) {
      testWidgets(
          'con la fuente del sistema al doble sigue sin cortarse '
          '(${onBreak ? "descanso" : "enfoque"})', (tester) async {
        tester.view.physicalSize = const Size(844, 390);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(pomodoroProvider.notifier);
        notifier.configure(
          workDuration: 25,
          breakDuration: 5,
          longBreakDuration: 15,
          autoStartBreaks: false,
          autoStartFocus: false,
          breakPanelMode: 0,
        );
        if (onBreak) notifier.skip();

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            // El escalado se inyecta sobre el MediaQuery real (no uno nuevo,
            // que traería tamaño y márgenes a cero y no probaría nada).
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2.0)),
                child: child!,
              ),
              home: const PomodoroScreen(),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── Lógica del ciclo ───────────────────────────────────────────────────

  group('ciclo', () {
    ProviderContainer makeContainer({
      int work = 25,
      bool autoBreaks = false,
    }) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(pomodoroProvider.notifier).configure(
            workDuration: work,
            breakDuration: 5,
            longBreakDuration: 15,
            autoStartBreaks: autoBreaks,
            autoStartFocus: false,
            breakPanelMode: 0,
          );
      return container;
    }

    test('el descanso largo llega tras cerrar la tanda, no antes', () {
      final container = makeContainer();
      final notifier = container.read(pomodoroProvider.notifier);

      // Tres enfoques terminados enteros, cada uno con su descanso corto.
      for (var i = 0; i < 3; i++) {
        notifier.completePhase(); // enfoque → descanso corto
        expect(container.read(pomodoroProvider).phase, PomodoroPhase.shortBreak);
        notifier.completePhase(); // descanso → enfoque
        expect(container.read(pomodoroProvider).phase, PomodoroPhase.focus);
      }

      // El cuarto cierra la tanda de 4.
      notifier.completePhase();
      expect(container.read(pomodoroProvider).phase, PomodoroPhase.longBreak);
      expect(container.read(pomodoroProvider).completedFocusSessions, 4);

      // Y el descanso largo devuelve los puntos de ciclo a cero.
      notifier.completePhase();
      final state = container.read(pomodoroProvider);
      expect(state.phase, PomodoroPhase.focus);
      expect(state.cycleInSet, 0);
    });

    test('saltar avanza de fase pero no cuenta el bloque', () {
      final container = makeContainer();
      container.read(pomodoroProvider.notifier).skip();

      final state = container.read(pomodoroProvider);
      expect(state.phase, PomodoroPhase.shortBreak);
      expect(state.cycleInSet, 0);
      expect(state.completedFocusSessions, 0);
    });

    test('saltar siempre el enfoque nunca desbloquea el descanso largo', () {
      final container = makeContainer();
      final notifier = container.read(pomodoroProvider.notifier);

      for (var i = 0; i < 6; i++) {
        notifier.skip();
        expect(container.read(pomodoroProvider).phase, PomodoroPhase.shortBreak);
        notifier.skip();
      }
    });

    test('alargar el bloque no hace retroceder el progreso', () {
      final container = makeContainer(work: 25);
      final notifier = container.read(pomodoroProvider.notifier);

      // A mitad del bloque.
      notifier.extendPhase(0); // no-op, deja el estado listo
      final before = container.read(pomodoroProvider);
      expect(before.progress, 0.0);

      notifier.extendPhase(5);
      final after = container.read(pomodoroProvider);
      expect(after.timeLeft, before.timeLeft + 300);
      // La duración crece con el tiempo añadido, así que lo transcurrido —y el
      // anillo— se quedan donde estaban en vez de saltar hacia atrás.
      expect(after.phaseDurationSeconds, before.phaseDurationSeconds + 300);
      expect(after.progress, 0.0);
    });

    test('cambiar de fase reinicia el tiempo añadido a mano', () {
      final container = makeContainer();
      final notifier = container.read(pomodoroProvider.notifier);

      notifier.extendPhase(10);
      notifier.skip();

      final state = container.read(pomodoroProvider);
      expect(state.extraSeconds, 0);
      expect(state.timeLeft, 5 * 60);
    });
  });

  // ── Bandeja de distracciones ───────────────────────────────────────────

  group('distracciones', () {
    test('se apilan en orden y se pueden quitar de una en una', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pomodoroProvider.notifier);

      notifier.captureDistraction('  llamar al banco  ');
      notifier.captureDistraction('mirar el correo');
      notifier.captureDistraction('   '); // en blanco: se ignora

      var state = container.read(pomodoroProvider);
      expect(state.distractions.length, 2);
      expect(state.distractions.first.text, 'llamar al banco');

      notifier.removeDistraction(0);
      state = container.read(pomodoroProvider);
      expect(state.distractions.single.text, 'mirar el correo');
    });

    test('sobreviven al cambio de fase: se revisan en el descanso', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(pomodoroProvider.notifier);

      notifier.configure(
        workDuration: 25,
        breakDuration: 5,
        longBreakDuration: 15,
        autoStartBreaks: false,
        autoStartFocus: false,
        breakPanelMode: 0,
      );
      notifier.captureDistraction('responder a Ana');
      notifier.skip();

      expect(container.read(pomodoroProvider).distractions.length, 1);
    });
  });
}
