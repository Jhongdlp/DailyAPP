import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistem_daily/core/providers/appearance_provider.dart';
import 'package:sistem_daily/core/theme/design_language.dart';
import 'package:sistem_daily/features/agenda/widgets/agenda_bars_editorial.dart';
import 'package:sistem_daily/features/agenda/widgets/month_calendar.dart';

/// La tira de días es la única de las tres barras que se puede montar sin
/// providers, y es también donde vive la decisión que más fácil se rompe: cómo
/// se distinguen "hoy" y "el día que estoy mirando".
///
/// La versión neumórfica usaba dos señales parecidas —relleno del acento para
/// el elegido, filete del mismo acento para hoy— y con el día de hoy
/// seleccionado se pisaban. Aquí son señales de naturaleza distinta:
/// inversión de material para el elegido, punto bajo la cifra para hoy.
void main() {
  DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> pumpStrip(
    WidgetTester tester, {
    required DateTime selected,
    int Function(DateTime)? countFor,
    ValueChanged<DateTime>? onSelect,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayStripEditorial(
            selectedDay: selected,
            countFor: countFor,
            onSelect: onSelect ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('la tira monta y enseña el día de hoy', (tester) async {
    final today = dateOnly(DateTime.now());
    await pumpStrip(tester, selected: today);

    expect(find.text('${today.day}'), findsWidgets);
  });

  testWidgets('tocar un día lo comunica hacia arriba', (tester) async {
    final today = dateOnly(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    DateTime? picked;

    await pumpStrip(
      tester,
      selected: today,
      onSelect: (day) => picked = day,
    );

    // La tira arranca centrada en hoy, así que mañana está en pantalla.
    await tester.tap(find.text('${tomorrow.day}').first);
    await tester.pump();

    expect(picked, tomorrow);
  });

  /// El calendario y el timeline no duplican su archivo: parametrizan los
  /// tokens por piel. El riesgo de ese patrón es que una piel se quede sin
  /// token al añadir un elemento, así que se comprueba que las dos se montan y
  /// que de verdad pintan distinto.
  testWidgets('el calendario se monta en las dos pieles y no se ven igual',
      (tester) async {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);

    Future<Color?> cellColorFor(DesignLanguage design) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(appearanceProvider.notifier).setDesign(design);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: MonthCalendar(
                selectedDay: day,
                accentColor: const Color(0xFF9BC53D),
                statsFor: (_) => const DayStats(),
                onSelect: (_) {},
                onAddReminder: () {},
                onAddBlock: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // La celda del día elegido: es la única con relleno propio.
      final selected = find.ancestor(
        of: find.text('${day.day}').first,
        matching: find.byType(AnimatedContainer),
      );
      final box = tester.widget<AnimatedContainer>(selected.first);
      return (box.decoration as BoxDecoration?)?.color;
    }

    final neu = await cellColorFor(DesignLanguage.neu);
    final editorial = await cellColorFor(DesignLanguage.editorial);

    expect(neu, isNotNull);
    expect(editorial, isNotNull);
    expect(neu, isNot(editorial),
        reason: 'si coinciden, una de las dos pieles se quedó sin token');
  });

  testWidgets('los días con bloques marcan densidad, no cuenta exacta',
      (tester) async {
    final today = dateOnly(DateTime.now());
    // Un día cargadísimo y uno vacío: la tira nunca debe pintar más de tres
    // puntos, porque el número exacto ya se ve entrando en el día.
    await pumpStrip(
      tester,
      selected: today,
      countFor: (day) => day == today.add(const Duration(days: 2)) ? 40 : 0,
    );

    // No hay texto con la cuenta en ninguna parte: si apareciera, la tira
    // habría dejado de ser un mapa de densidad.
    expect(find.text('40'), findsNothing);
  });
}
