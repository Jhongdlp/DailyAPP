import 'package:flutter/material.dart';

/// Línea de tendencia diminuta para una tarjeta de métrica.
///
/// No lleva ejes, ni rejilla, ni etiquetas a propósito: acompaña a un número
/// que ya dice el valor, y su único trabajo es enseñar la forma del periodo.
/// Todo lo demás sería ruido a este tamaño.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 28,
  });

  /// Valores en orden cronológico. Los huecos ya vienen resueltos por quien
  /// llama: aquí un `null` sería un corte en la línea y no hay sitio para
  /// explicarlo.
  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Con un solo punto no hay forma que enseñar, solo un pixel suelto que se
    // leería como un dato raro.
    if (values.length < 2) return SizedBox(height: height);

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(values: values, color: color),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    var min = values.first;
    var max = values.first;
    for (final v in values) {
      if (v < min) min = v;
      if (v > max) max = v;
    }

    // Una serie plana se dibuja centrada en vez de dividir por cero. Es
    // información legítima: "esto no se movió".
    final span = max - min;
    final path = Path();

    for (var i = 0; i < values.length; i++) {
      final x = size.width * (i / (values.length - 1));
      final normalized = span == 0 ? 0.5 : (values[i] - min) / span;
      // Se deja un margen arriba y abajo para que el trazo no se coma el borde.
      final y = size.height * (1 - normalized) * 0.82 + size.height * 0.09;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Relleno tenue bajo la línea: da peso visual sin competir con el número.
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Punto final: marca dónde estás ahora, que es el único punto concreto que
    // importa en una serie de este tamaño.
    final lastX = size.width;
    final lastNormalized =
        span == 0 ? 0.5 : (values.last - min) / span;
    final lastY = size.height * (1 - lastNormalized) * 0.82 + size.height * 0.09;

    canvas.drawCircle(Offset(lastX - 2, lastY), 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color || !_sameValues(old.values, values);

  static bool _sameValues(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
