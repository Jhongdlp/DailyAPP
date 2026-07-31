import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../pomodoro_setup_sheet.dart';

class TomatoButton extends StatefulWidget {
  final double size;

  const TomatoButton({
    super.key,
    this.size = 38.0,
  });

  @override
  State<TomatoButton> createState() => _TomatoButtonState();
}

class _TomatoButtonState extends State<TomatoButton> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    // Squish effect: scale down to 0.82 and squeeze vertically when pressed
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.82).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _animController.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _animController.reverse();
    _openPomodoroSetup();
  }

  void _onTapCancel() {
    _animController.reverse();
  }

  void _openPomodoroSetup() {
    PomodoroSetupSheet.show(context);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          // Squish transformation: scale width and height slightly differently to simulate soft rubber
          final scale = _scaleAnimation.value;
          final widthScale = scale;
          final heightScale = scale * 0.95; // squish vertically slightly more

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(widthScale, heightScale, 1.0),
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: CustomPaint(
                painter: _TomatoPainter(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TomatoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double cx = w / 2;
    final double cy = h / 2 + (h * 0.05); // shift body slightly down

    final Rect bodyRect = Rect.fromLTRB(w * 0.08, h * 0.18, w * 0.92, h * 0.96);

    // 1. Tomato Red Body Gradient (Radial to give 3D gloss)
    final Paint bodyPaint = Paint()
      ..shader = RadialGradient(
        colors: const [
          Color(0xFFFF5252), // bright reflection center
          Color(0xFFE53935), // classic tomato red
          Color(0xFFC62828), // darker shade towards edges
        ],
        center: const Alignment(-0.2, -0.3), // highlight offset
        radius: 0.85,
      ).createShader(bodyRect);

    // Draw slightly squashed circular body (tomato shapes are wider than tall)
    canvas.drawOval(bodyRect, bodyPaint);

    // 2. Gloss highlight (light reflection crescent)
    final Paint highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    
    final Path highlightPath = Path()
      ..addOval(Rect.fromLTRB(w * 0.22, h * 0.28, w * 0.44, h * 0.44));
    
    canvas.drawPath(highlightPath, highlightPaint);

    // 3. Green stem and leaves
    final Paint stemPaint = Paint()
      ..color = const Color(0xFF4CAF50) // leaf green
      ..style = PaintingStyle.fill;

    // Center stem stick
    final Path stemPath = Path()
      ..moveTo(cx - (w * 0.05), cy - (h * 0.26))
      ..quadraticBezierTo(cx - (w * 0.04), cy - (h * 0.45), cx - (w * 0.12), cy - (h * 0.48))
      ..quadraticBezierTo(cx, cy - (h * 0.44), cx + (w * 0.03), cy - (h * 0.28))
      ..close();
    canvas.drawPath(stemPath, stemPaint);

    // Leaves crown (4 leaves radiating from center top)
    final double crownY = cy - (h * 0.26);

    // Left leaf
    final Path leaf1 = Path()
      ..moveTo(cx, crownY)
      ..quadraticBezierTo(cx - (w * 0.18), crownY - (h * 0.04), cx - (w * 0.28), crownY + (h * 0.08))
      ..quadraticBezierTo(cx - (w * 0.16), crownY + (h * 0.10), cx, crownY)
      ..close();
    canvas.drawPath(leaf1, stemPaint);

    // Right leaf
    final Path leaf2 = Path()
      ..moveTo(cx, crownY)
      ..quadraticBezierTo(cx + (w * 0.18), crownY - (h * 0.04), cx + (w * 0.28), crownY + (h * 0.08))
      ..quadraticBezierTo(cx + (w * 0.16), crownY + (h * 0.10), cx, crownY)
      ..close();
    canvas.drawPath(leaf2, stemPaint);

    // Bottom-center leaf
    final Path leaf3 = Path()
      ..moveTo(cx, crownY)
      ..quadraticBezierTo(cx - (w * 0.08), crownY + (h * 0.15), cx - (w * 0.02), crownY + (h * 0.22))
      ..quadraticBezierTo(cx + (w * 0.08), crownY + (h * 0.15), cx, crownY)
      ..close();
    canvas.drawPath(leaf3, stemPaint);

    // Back-left leaf
    final Path leaf4 = Path()
      ..moveTo(cx, crownY)
      ..quadraticBezierTo(cx - (w * 0.12), crownY - (h * 0.12), cx - (w * 0.15), crownY - (h * 0.14))
      ..quadraticBezierTo(cx - (w * 0.04), crownY - (h * 0.08), cx, crownY)
      ..close();
    canvas.drawPath(leaf4, stemPaint);

    // Back-right leaf
    final Path leaf5 = Path()
      ..moveTo(cx, crownY)
      ..quadraticBezierTo(cx + (w * 0.12), crownY - (h * 0.12), cx + (w * 0.15), crownY - (h * 0.14))
      ..quadraticBezierTo(cx + (w * 0.04), crownY - (h * 0.08), cx, crownY)
      ..close();
    canvas.drawPath(leaf5, stemPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
