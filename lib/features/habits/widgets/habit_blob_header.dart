import 'package:flutter/material.dart';
import '../../../core/theme/bento_theme.dart';

/// Fondo decorativo del header de Hábitos: una mancha orgánica con una
/// textura de puntos encima, tal como en el diseño original (Habitos.dc.html).
class HabitBlobHeader extends StatelessWidget {
  final Color accentColor;

  const HabitBlobHeader({super.key, this.accentColor = BentoTheme.accentLime});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 196,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -46,
            right: -58,
            child: SizedBox(
              width: 320,
              height: 300,
              child: CustomPaint(painter: _BlobPainter()),
            ),
          ),
          Positioned(
            top: 40,
            right: 22,
            child: SizedBox(
              width: 130,
              height: 96,
              child: CustomPaint(
                painter: _DotGridPainter(
                  color: BentoTheme.creamAlpha(0.26),
                  dotRadius: 1.1,
                  spacing: 11,
                ),
              ),
            ),
          ),
          Positioned(
            top: 38,
            right: 22,
            child: SizedBox(
              width: 44,
              height: 44,
              child: CustomPaint(
                painter: _DotGridPainter(
                  color: accentColor,
                  dotRadius: 1.4,
                  spacing: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(241, 22)
      ..cubicTo(292, 37, 306, 100, 293, 154)
      ..cubicTo(281, 205, 244, 250, 190, 262)
      ..cubicTo(135, 275, 68, 259, 35, 216)
      ..cubicTo(4, 176, 1, 115, 30, 71)
      ..cubicTo(57, 34, 116, 7, 168, 4)
      ..cubicTo(195, 2, 217, 9, 241, 22)
      ..close();
    canvas.drawPath(path, Paint()..color = BentoTheme.darkBlob);
  }

  @override
  bool shouldRepaint(covariant _BlobPainter oldDelegate) => false;
}

class _DotGridPainter extends CustomPainter {
  final Color color;
  final double dotRadius;
  final double spacing;

  _DotGridPainter({required this.color, required this.dotRadius, required this.spacing});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = spacing / 2; y < size.height; y += spacing) {
      for (double x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dotRadius != dotRadius || oldDelegate.spacing != spacing;
}
