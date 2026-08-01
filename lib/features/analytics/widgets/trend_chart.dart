import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/metric_model.dart';
import '../../../core/theme/bento_theme.dart';

/// Un punto del periodo. `value` es `null` en los días sin registro.
typedef TrendPoint = ({DateTime day, double? value});

/// Serie temporal de **una** métrica, con eje y rejilla.
///
/// Una sola serie por gráfica a propósito: dos métricas de escalas distintas
/// necesitarían dos ejes verticales, y una gráfica de doble eje se puede
/// inclinar para contar lo que uno quiera. Aquí se cambia de métrica tocando
/// su tarjeta.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.metric,
    required this.points,
    this.height = 168,
  });

  final DailyMetric metric;
  final List<TrendPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    final withData = points.where((p) => p.value != null).toList();

    if (withData.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Aún no hay suficientes días registrados de ${metric.inlineName}.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: BentoTheme.textSecondary,
            ),
          ),
        ),
      );
    }

    var min = withData.first.value!;
    var max = withData.first.value!;
    for (final p in withData) {
      if (p.value! < min) min = p.value!;
      if (p.value! > max) max = p.value!;
    }

    // El eje arranca en cero cuando el mínimo ya está cerca: si no, una
    // variación pequeña se vería como un acantilado.
    if (min > 0 && min < max * 0.4) min = 0;
    if (min == max) {
      min = min - 1;
      max = max + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              metric.format(max),
              style: _axisStyle,
            ),
            Text(
              '${withData.length} ${withData.length == 1 ? 'día' : 'días'} con dato',
              style: _axisStyle,
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _TrendPainter(
              points: points,
              min: min,
              max: max,
              color: metric.accent,
              gridColor: BentoTheme.creamAlpha(0.10),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(metric.format(min), style: _axisStyle),
            Text(_dayLabel(points.first.day), style: _axisStyle),
            Text(_dayLabel(points.last.day), style: _axisStyle),
          ],
        ),
      ],
    );
  }

  static TextStyle get _axisStyle => GoogleFonts.outfit(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: BentoTheme.creamAlpha(0.45),
      );

  static String _dayLabel(DateTime d) => '${d.day}/${d.month}';
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.min,
    required this.max,
    required this.color,
    required this.gridColor,
  });

  final List<TrendPoint> points;
  final double min;
  final double max;
  final Color color;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Rejilla recesiva: sirve para leer alturas, no para mirarla.
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * (i / 3);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    double xFor(int i) =>
        points.length == 1 ? 0 : size.width * (i / (points.length - 1));
    double yFor(double v) => size.height * (1 - (v - min) / (max - min));

    // Los días sin dato cortan la línea en vez de interpolarse: unir por encima
    // del hueco dibujaría un registro que no existió.
    final segments = <List<Offset>>[];
    var current = <Offset>[];

    for (var i = 0; i < points.length; i++) {
      final value = points[i].value;
      if (value == null) {
        if (current.length > 1) segments.add(current);
        current = <Offset>[];
        continue;
      }
      current.add(Offset(xFor(i), yFor(value)));
    }
    if (current.length > 1) segments.add(current);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final segment in segments) {
      final path = Path()..moveTo(segment.first.dx, segment.first.dy);
      for (final point in segment.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }

      final area = Path.from(path)
        ..lineTo(segment.last.dx, size.height)
        ..lineTo(segment.first.dx, size.height)
        ..close();

      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.20), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );

      canvas.drawPath(path, linePaint);
    }

    // Un día suelto entre dos huecos no forma segmento, pero sí es un dato:
    // se marca con un punto para que no desaparezca de la gráfica.
    for (var i = 0; i < points.length; i++) {
      final value = points[i].value;
      if (value == null) continue;

      final prevEmpty = i == 0 || points[i - 1].value == null;
      final nextEmpty = i == points.length - 1 || points[i + 1].value == null;
      if (prevEmpty && nextEmpty) {
        canvas.drawCircle(
          Offset(xFor(i), yFor(value)),
          3,
          Paint()..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.min != min ||
      old.max != max ||
      old.color != color ||
      old.points.length != points.length;
}
