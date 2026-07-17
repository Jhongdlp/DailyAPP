import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Triggers a burst of micro-confetti particles at the specified global position.
void triggerConfettiCelebration(BuildContext context, Offset position) {
  final overlayState = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _ConfettiOverlayWidget(
      spawnPosition: position,
      onFinished: () {
        entry.remove();
      },
    ),
  );
  overlayState.insert(entry);
}

class _ConfettiOverlayWidget extends StatefulWidget {
  final Offset spawnPosition;
  final VoidCallback onFinished;

  const _ConfettiOverlayWidget({
    required this.spawnPosition,
    required this.onFinished,
  });

  @override
  State<_ConfettiOverlayWidget> createState() => _ConfettiOverlayWidgetState();
}

class _ConfettiOverlayWidgetState extends State<_ConfettiOverlayWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_ConfettiParticle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Initialize 24 confetti particles with random initial trajectories
    final random = math.Random();
    _particles = List.generate(24, (index) {
      // Angle between -135 and -45 degrees (pointing generally upwards)
      final angle = (-45 - random.nextDouble() * 90) * math.pi / 180;
      final speed = 4.0 + random.nextDouble() * 7.0;
      final color = HSVColor.fromAHSV(
        1.0,
        random.nextDouble() * 360, // random hue
        0.8, // high saturation
        0.95, // bright value
      ).toColor();

      return _ConfettiParticle(
        x: widget.spawnPosition.dx,
        y: widget.spawnPosition.dy,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed,
        color: color,
        size: 3.5 + random.nextDouble() * 4.5,
        rotationSpeed: (random.nextDouble() - 0.5) * 15,
        shape: random.nextBool() ? _ParticleShape.circle : _ParticleShape.square,
      );
    });

    _controller.forward().then((_) => widget.onFinished());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          // Update physics simulation
          for (final p in _particles) {
            p.update();
          }

          return CustomPaint(
            painter: _ConfettiPainter(
              particles: _particles,
              progress: _controller.value,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

enum _ParticleShape { circle, square }

class _ConfettiParticle {
  double x;
  double y;
  double vx;
  double vy;
  double angle = 0;
  final double rotationSpeed;
  final Color color;
  final double size;
  final _ParticleShape shape;

  // Constants for physical simulation
  static const double gravity = 0.28;
  static const double drag = 0.97;

  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.size,
    required this.rotationSpeed,
    required this.shape,
  });

  void update() {
    // Apply gravity
    vy += gravity;
    
    // Apply drag
    vx *= drag;
    vy *= drag;

    // Move
    x += vx;
    y += vy;

    // Spin
    angle += rotationSpeed * math.pi / 180;
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter({
    required this.particles,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fade out everything near the end of life
    final double opacity = (1.0 - progress).clamp(0.0, 1.0);

    for (final p in particles) {
      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.angle);

      if (p.shape == _ParticleShape.circle) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}
