import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/sleep_model.dart';
import '../../../../core/theme/bento_theme.dart';
import '../night_edit_sheet.dart';
import 'sleep_chart_shell.dart';

/// Ventana de sueño: una barra por noche, del momento de apagar la luz al de
/// levantarse, sobre un eje de reloj de 18:00 a 12:00.
///
/// Es el gráfico principal del panel porque no hay que leer ningún número: si
/// las barras están alineadas, tu horario es estable; si se desplazan los fines
/// de semana, ahí está el jet lag social dibujado.
class SleepWindowChart extends StatefulWidget {
  final SleepAnalytics analytics;

  /// Noches a mostrar, de la más antigua a la más reciente.
  final List<SleepSession> nights;

  const SleepWindowChart({
    super.key,
    required this.analytics,
    required this.nights,
  });

  @override
  State<SleepWindowChart> createState() => _SleepWindowChartState();
}

class _SleepWindowChartState extends State<SleepWindowChart> {
  int? _selected;

  static const _rowHeight = 9.0;
  static const _gutter = 34.0;
  static const _axisBand = 20.0;

  List<SleepSession> get _rows {
    final list = widget.nights.where((n) => n.lightsOutAt != null).toList()
      ..sort((a, b) => a.nightKey.compareTo(b.nightKey));
    return list.length <= 30 ? list : list.sublist(list.length - 30);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final selected =
        _selected != null && _selected! < rows.length ? rows[_selected!] : null;

    return SleepChartShell(
      title: 'VENTANA DE SUEÑO',
      subtitle: 'Cada barra es una noche, de acostarte a levantarte. '
          'Alineadas = horario estable.',
      available: rows.length,
      minimum: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final height = rows.length * _rowHeight + _axisBand;
              return GestureDetector(
                onTapDown: (details) {
                  final index = (details.localPosition.dy / _rowHeight).floor();
                  setState(() => _selected =
                      index >= 0 && index < rows.length ? index : null);
                },
                child: CustomPaint(
                  size: Size(constraints.maxWidth, height),
                  painter: _WindowPainter(
                    nights: rows,
                    selected: _selected,
                    gutter: _gutter,
                    rowHeight: _rowHeight,
                    axisBand: _axisBand,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              SleepLegendDot(
                  color: BentoTheme.accentAlarm, label: 'Dormido'),
              SleepLegendDot(
                  color: BentoTheme.accentOrange,
                  label: 'Sonó la alarma y seguiste'),
              SleepLegendDot(
                  color: BentoTheme.accentAlarm.withValues(alpha: 0.45),
                  label: 'Volviste a dormirte'),
              SleepLegendDot(
                  color: BentoTheme.errorRed, label: 'Alarma ignorada'),
            ],
          ),
          const SizedBox(height: 10),
          // El detalle en texto es la vía accesible al valor exacto: el gráfico
          // no puede ser la única forma de leerlo.
          GestureDetector(
            onTap: selected == null
                ? null
                : () => NightEditSheet.show(context, selected),
            child: _SelectedNightReadout(session: selected),
          ),
        ],
      ),
    );
  }
}

class _SelectedNightReadout extends StatelessWidget {
  final SleepSession? session;

  const _SelectedNightReadout({this.session});

  String _time(DateTime? dt) => dt == null
      ? '—'
      : '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = session;
    final text = s == null
        ? 'Toca una noche para ver sus horas.'
        : '${shortDayLabel(s.date)} · '
            '${_time(s.lightsOutAt)} → ${_time(s.effectiveWakeAt)} · '
            '${formatSleepMinutes(s.sleepMinutes)}'
            '${s.wentBackToSleep ? ' · volviste a dormirte ${s.backToSleepMinutes} min' : ''}'
            '${s.alarmIgnored ? ' · alarma ignorada' : ''}'
            ' · toca para corregir';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: BentoTheme.creamAlpha(0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: GoogleFonts.montserrat(
          fontSize: 11,
          color: BentoTheme.creamAlpha(s == null ? 0.35 : 0.7),
        ),
      ),
    );
  }
}

class _WindowPainter extends CustomPainter {
  final List<SleepSession> nights;
  final int? selected;
  final double gutter;
  final double rowHeight;
  final double axisBand;

  /// El eje cubre de las 18:00 del día anterior a las 12:00 del día del
  /// despertar: 18 h, que es donde cae cualquier noche razonable.
  static const _spanMinutes = 18 * 60;

  _WindowPainter({
    required this.nights,
    required this.selected,
    required this.gutter,
    required this.rowHeight,
    required this.axisBand,
  });

  /// Minutos desde las 18:00 de la víspera de la noche [night].
  double? _offset(SleepSession night, DateTime? moment) {
    if (moment == null) return null;
    final origin = DateTime(night.date.year, night.date.month, night.date.day)
        .subtract(const Duration(hours: 6)); // 18:00 del día anterior
    final minutes = moment.difference(origin).inMinutes.toDouble();
    if (minutes < 0 || minutes > _spanMinutes) return null;
    return minutes;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = size.width - gutter;
    if (plotWidth <= 0) return;

    double x(double minutes) => gutter + plotWidth * (minutes / _spanMinutes);

    final plotHeight = nights.length * rowHeight;

    // Rejilla: líneas continuas de un tono por encima de la superficie. Nada
    // de discontinuas, que se leen como umbral cuando solo son referencia.
    final gridPaint = Paint()
      ..color = BentoTheme.creamAlpha(0.09)
      ..strokeWidth = 1;
    final labelStyle = GoogleFonts.montserrat(
      fontSize: 9,
      color: BentoTheme.creamAlpha(0.35),
    );

    for (var minutes = 0; minutes <= _spanMinutes; minutes += 180) {
      final dx = x(minutes.toDouble());
      canvas.drawLine(Offset(dx, 0), Offset(dx, plotHeight), gridPaint);

      final hour = (18 + minutes ~/ 60) % 24;
      final painter = TextPainter(
        text: TextSpan(
            text: '${hour.toString().padLeft(2, '0')}h', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(dx - painter.width / 2, plotHeight + 6),
      );
    }

    for (var i = 0; i < nights.length; i++) {
      final night = nights[i];
      final top = i * rowHeight;
      final barTop = top + 1.5;
      final barHeight = rowHeight - 3;

      // Banda tenue en fines de semana: hace visible el desplazamiento del
      // horario sin necesidad de etiquetar cada fila.
      if (night.date.weekday >= DateTime.saturday) {
        canvas.drawRect(
          Rect.fromLTWH(gutter, top, plotWidth, rowHeight),
          Paint()..color = BentoTheme.creamAlpha(0.035),
        );
      }

      if (selected == i) {
        canvas.drawRect(
          Rect.fromLTWH(0, top, size.width, rowHeight),
          Paint()..color = BentoTheme.creamAlpha(0.09),
        );
      }

      // Etiqueta de fecha cada 7 filas para no saturar el margen.
      if (i % 7 == 0) {
        final painter = TextPainter(
          text: TextSpan(text: shortDayLabel(night.date), style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(0, top + (rowHeight - painter.height) / 2));
      }

      final start = _offset(night, night.lightsOutAt);
      if (start == null) continue;

      final ring = _offset(night, night.firstRingAt);
      final woke = _offset(night, night.wokeAt);
      // Si la alarma se ignoró no hay hora de despertar: la barra llega hasta
      // el timbrazo y se marca en rojo, en vez de inventar un final.
      final end = woke ?? ring;
      if (end == null || end <= start) continue;

      // Tramo dormido: de apagar la luz al primer timbrazo (o al final).
      final sleptEnd = ring != null && ring > start && ring < end ? ring : end;
      final radius = Radius.circular(barHeight / 2);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x(start), barTop, x(sleptEnd), barTop + barHeight),
          radius,
        ),
        Paint()..color = BentoTheme.accentAlarm,
      );

      // Cola de snooze: lo que tardaste en levantarte desde que sonó.
      if (sleptEnd < end) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            // 2px de hueco de superficie en vez de un borde para separarlas.
            Rect.fromLTRB(x(sleptEnd) + 2, barTop, x(end), barTop + barHeight),
            radius,
          ),
          Paint()
            ..color = night.alarmIgnored
                ? BentoTheme.errorRed
                : BentoTheme.accentOrange,
        );
      }

      // Tramo de "me volví a dormir": va tras el despertar oficial, en el tono
      // del sueño pero rebajado, porque fue sueño de verdad aunque partido.
      final finalWake = _offset(night, night.finalWakeAt);
      if (finalWake != null && finalWake > end) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(x(end) + 2, barTop, x(finalWake), barTop + barHeight),
            radius,
          ),
          Paint()..color = BentoTheme.accentAlarm.withValues(alpha: 0.45),
        );
      }

      // Muesca de la hora a la que debía sonar.
      final scheduled = _offset(night, night.alarmScheduledAt);
      if (scheduled != null) {
        canvas.drawLine(
          Offset(x(scheduled), top + 0.5),
          Offset(x(scheduled), top + rowHeight - 0.5),
          Paint()
            ..color = BentoTheme.creamAlpha(0.5)
            ..strokeWidth = 1,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WindowPainter old) =>
      old.nights != nights || old.selected != selected;
}
