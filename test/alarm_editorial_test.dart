import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistem_daily/core/models/alarm_model.dart';
import 'package:sistem_daily/core/theme/editorial_theme.dart';
import 'package:sistem_daily/core/theme/oklch.dart';
import 'package:sistem_daily/features/alarm/alarm_card_editorial.dart';
import 'package:sistem_daily/features/alarm/widgets/editorial_time_picker.dart';

/// La tarjeta de alarma y la rueda de hora se pueden montar de verdad en un
/// test: la tarjeta sólo lee `alarmsProvider` al alternar el interruptor o al
/// deslizar para borrar, y la rueda no toca ningún provider.
///
/// Lo que se cubre es la decisión de diseño que sostiene la lista: **el estado
/// encendido/apagado es una sola señal, el peso de la tinta**. Un test de
/// colores parece frágil, pero justo aquí es lo contrario — es la regla que se
/// rompe sola en cuanto alguien añade un acento "para que se vea mejor".
void main() {
  AlarmModel alarm({
    bool enabled = true,
    int hour = 7,
    int? bedtimeHour,
  }) =>
      AlarmModel(
        id: 'a1',
        userId: 'u1',
        enabled: enabled,
        hour: hour,
        minute: 30,
        targetObject: 'Taza de café',
        label: 'Despertar',
        daysOfWeek: const [1, 2, 3, 4, 5],
        createdAt: DateTime(2026, 1, 1),
        bedtimeHour: bedtimeHour,
        bedtimeMinute: bedtimeHour == null ? null : 0,
      );

  Future<void> pumpCard(WidgetTester tester, AlarmModel model) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AlarmCardEditorial(alarm: model, onTap: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('la alarma encendida muestra hora, etiqueta y objeto',
      (tester) async {
    await pumpCard(tester, alarm());

    expect(find.text('7:30'), findsOneWidget);
    expect(find.text('AM'), findsOneWidget);
    expect(find.text('Despertar'), findsOneWidget);
    expect(find.text('Taza de café'), findsOneWidget);
    expect(find.text('Lun, Mar, Mié, Jue, Vie'), findsOneWidget);
  });

  testWidgets('apagada, la cuenta atrás desaparece y el interruptor está en off',
      (tester) async {
    await pumpCard(tester, alarm(enabled: false));

    // La cuenta atrás sólo tiene sentido si va a ocurrir: en una alarma
    // apagada sería un dato falso.
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').startsWith('Suena en'),
      ),
      findsNothing,
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('encendida y apagada no se pintan igual', (tester) async {
    Color titleColor() => tester
        .widget<Text>(find.text('7:30'))
        .style!
        .color!;

    await pumpCard(tester, alarm());
    final on = titleColor();

    await pumpCard(tester, alarm(enabled: false));
    final off = titleColor();

    expect(on, isNot(off),
        reason: 'el estado se dice con el peso de la tinta, no con un icono');
  });

  testWidgets('la alarma de sueño enseña el rango entero', (tester) async {
    await pumpCard(tester, alarm(bedtimeHour: 23));

    // Para el usuario es una sola cosa: "de 11 a 7:30".
    expect(find.text('11:00 PM'), findsOneWidget);
    expect(find.text('7:30 AM'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').contains('en la cama'),
      ),
      findsOneWidget,
    );
  });

  /// Esta pieza ya se rompió una vez: los números iban en papel sobre un panel
  /// de papel y sólo se veía el que caía dentro de la banda de tinta. Los
  /// vecinos son la mitad de la información de una rueda —de dónde vienes y
  /// adónde vas—, así que su contraste es un requisito, no un gusto.
  test('las cifras de la rueda se leen sobre el papel', () {
    for (final (name, color) in [
      ('elegida', EditorialTimePicker.selectedColor),
      ('vecina', EditorialTimePicker.neighborColor),
    ]) {
      final onPaper = contrastRatio(color, EditorialTheme.paper);
      final onBand = contrastRatio(color, EditorialTheme.gray);

      expect(onPaper, greaterThanOrEqualTo(4.5),
          reason: 'la cifra $name no se lee sobre el panel (${onPaper.toStringAsFixed(2)}:1)');
      expect(onBand, greaterThanOrEqualTo(4.5),
          reason: 'la cifra $name no se lee dentro de la banda '
              '(${onBand.toStringAsFixed(2)}:1)');
    }
  });

  test('la cifra elegida se distingue de sus vecinas', () {
    // No basta con que las dos se lean: tienen que distinguirse ENTRE SÍ, o la
    // rueda no dice cuál está elegida. El tamaño y el peso también lo marcan,
    // pero el color no puede ir en contra.
    expect(
      contrastRatio(
        EditorialTimePicker.selectedColor,
        EditorialTimePicker.neighborColor,
      ),
      greaterThanOrEqualTo(2.0),
    );
  });

  testWidgets('la rueda de hora devuelve la hora elegida en 24h',
      (tester) async {
    TimeOfDay? picked;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorialTimePicker(
            initialTime: const TimeOfDay(hour: 7, minute: 30),
            onChanged: (t) => picked = t,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AM'), findsOneWidget);
    expect(find.text('PM'), findsOneWidget);

    // Pasar a PM sobre las 7:30 tiene que dar 19:30, no 7:30 con una etiqueta
    // distinta: la conversión de 12h a 24h es donde estos selectores fallan.
    await tester.tap(find.text('PM'));
    await tester.pumpAndSettle();

    expect(picked, const TimeOfDay(hour: 19, minute: 30));
  });

  testWidgets('los atajos de minutos mueven la rueda', (tester) async {
    TimeOfDay? picked;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorialTimePicker(
            initialTime: const TimeOfDay(hour: 7, minute: 30),
            onChanged: (t) => picked = t,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Llegar a :45 girando de uno en uno son quince pasos; el chip lo hace de
    // un toque, y la rueda tiene que quedar donde dice el chip.
    await tester.tap(find.text(':45'));
    await tester.pumpAndSettle();

    expect(picked, const TimeOfDay(hour: 7, minute: 45));
  });
}
