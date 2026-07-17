import 'dart:math' as math;
import 'package:flutter/material.dart';

enum StreakTier {
  unlit,              // 0
  starter,            // 1 - 4
  blazing,            // 5 - 9
  voidFlare,          // 10 - 19
  cosmicNova,         // 20 - 39
  atomicSun,          // 40 - 99
  hyperNova,          // 100 - 299
  infinitySingularity // 300+
}

/// A highly polished, high-performance animated flame widget.
/// Renders programmatically using a CustomPainter, providing smooth micro-animations.
/// The appearance (size, color gradient, animation speed, particles) scales with the streak tier.
class StreakFlame extends StatefulWidget {
  final int streak;
  final double size;
  final bool animate;

  const StreakFlame({
    super.key,
    required this.streak,
    this.size = 24.0,
    this.animate = true,
  });

  /// Centralized colors for text labels matching the flame tiers
  static Color getColorForStreak(int streak) {
    if (streak == 0) return const Color(0xFF8E8E93);
    if (streak < 5) return const Color(0xFFFFB236);      // Orange-Yellow
    if (streak < 10) return const Color(0xFFFF5D36);     // Red-Orange
    if (streak < 20) return const Color(0xFFFF36C4);     // Purple-Magenta
    if (streak < 40) return const Color(0xFF00FFD1);     // Neon Cyan
    if (streak < 100) return const Color(0xFFCCFF00);    // Neon Lime Green
    if (streak < 300) return const Color(0xFFFFD54F);    // Supercharged White/Gold
    return const Color(0xFF00F0FF);                      // Prismatic Cyan-Magenta Core
  }

  @override
  State<StreakFlame> createState() => _StreakFlameState();
}

class _StreakFlameState extends State<StreakFlame> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final tier = _getTierFor(widget.streak);
    _controller = AnimationController(
      vsync: this,
      duration: _durationForTier(tier),
    );
    if (widget.streak > 0 && widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant StreakFlame oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.streak > 0 && widget.animate) {
      final oldTier = _getTierFor(oldWidget.streak);
      final newTier = _tier;
      
      if (oldTier != newTier || !_controller.isAnimating) {
        _controller.duration = _durationForTier(newTier);
        _controller.repeat();
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  StreakTier _getTierFor(int streak) {
    if (streak == 0) return StreakTier.unlit;
    if (streak < 5) return StreakTier.starter;
    if (streak < 10) return StreakTier.blazing;
    if (streak < 20) return StreakTier.voidFlare;
    if (streak < 40) return StreakTier.cosmicNova;
    if (streak < 100) return StreakTier.atomicSun;
    if (streak < 300) return StreakTier.hyperNova;
    return StreakTier.infinitySingularity;
  }

  StreakTier get _tier => _getTierFor(widget.streak);

  Duration _durationForTier(StreakTier tier) {
    switch (tier) {
      case StreakTier.blazing:
        return const Duration(milliseconds: 1600);
      case StreakTier.voidFlare:
        return const Duration(milliseconds: 1400);
      case StreakTier.cosmicNova:
        return const Duration(milliseconds: 1200);
      case StreakTier.atomicSun:
        return const Duration(milliseconds: 1000);
      case StreakTier.hyperNova:
        return const Duration(milliseconds: 850);
      case StreakTier.infinitySingularity:
        return const Duration(milliseconds: 700);
      default:
        return const Duration(milliseconds: 2000);
    }
  }

  double get _scaleFactor {
    switch (_tier) {
      case StreakTier.unlit:
        return 0.85;
      case StreakTier.starter:
        return 1.0;
      case StreakTier.blazing:
        return 1.12;
      case StreakTier.voidFlare:
        return 1.25;
      case StreakTier.cosmicNova:
        return 1.45;
      case StreakTier.atomicSun:
        return 1.65;
      case StreakTier.hyperNova:
        return 1.85;
      case StreakTier.infinitySingularity:
        return 2.1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tier = _tier;
    final scale = _scaleFactor;
    final currentSize = widget.size * scale;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 750),
      curve: Curves.elasticOut,
      width: currentSize,
      height: currentSize,
      alignment: Alignment.center,
      // RepaintBoundary: la llama repinta a 60fps; sin esta frontera cada tick
      // invalida el repintado de todo el subárbol ancestro (cards neumórficas
      // con sombras interiores blureadas incluidas). Con ella, el repintado
      // queda confinado a esta capa diminuta.
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              size: Size(currentSize, currentSize),
              willChange: true,
              painter: FlamePainter(
                animationValue: _controller.value,
                tier: tier,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Estilo visual de cada tier, resuelto una sola vez (antes se reconstruían
/// las listas de colores en cada frame de cada llama).
class _TierStyle {
  final List<Color> outer;
  final List<Color> inner;
  final List<Color> core;
  final Color particle;
  final int particleCount;
  const _TierStyle(this.outer, this.inner, this.core, this.particle, this.particleCount);
}

class FlamePainter extends CustomPainter {
  final double animationValue;
  final StreakTier tier;

  FlamePainter({
    required this.animationValue,
    required this.tier,
  });

  static const Map<StreakTier, _TierStyle> _styles = {
    StreakTier.starter: _TierStyle(
      [Color(0x70FF7E36), Color(0x00FF3636)],
      [Color(0xFFFFB236), Color(0xFFFF5236)],
      [Color(0xFFFFF7C2), Color(0xFFFFB236)],
      Color(0xFFFFB236),
      3,
    ),
    StreakTier.blazing: _TierStyle(
      [Color(0x80FF3636), Color(0x00D01B1B)],
      [Color(0xFFFF5D36), Color(0xFFE02B2B)],
      [Color(0xFFFFE0B2), Color(0xFFFF5D36)],
      Color(0xFFFF5D36),
      5,
    ),
    StreakTier.voidFlare: _TierStyle(
      [Color(0x809D36FF), Color(0x005D00FF)],
      [Color(0xFFFF36C4), Color(0xCCA000FF)],
      [Color(0xFFF3E5F5), Color(0xFFFF36C4)],
      Color(0xFFFF36C4),
      7,
    ),
    StreakTier.cosmicNova: _TierStyle(
      [Color(0x8000F0FF), Color(0x00003CFF)],
      [Color(0xFF00FF85), Color(0xFF0051FF)],
      [Color(0xFFE0F7FA), Color(0xFF00FFD1)],
      Color(0xFF00FFD1),
      11,
    ),
    StreakTier.atomicSun: _TierStyle(
      [Color(0x8039FF14), Color(0x000F6F00)],
      [Color(0xFFCCFF00), Color(0xFF26B000)],
      [Color(0xFFF9FBE7), Color(0xFFCCFF00)],
      Color(0xFFCCFF00),
      14,
    ),
    StreakTier.hyperNova: _TierStyle(
      [Color(0x80FFE57F), Color(0x00FF8F00)],
      [Color(0xFFFFF8E1), Color(0xFFFFC107)],
      [Color(0xFFFFFFFF), Color(0xFFFFF59D)],
      Color(0xFFFFD54F),
      18,
    ),
    StreakTier.infinitySingularity: _TierStyle(
      [Color(0x90FF007F), Color(0x001A0033)],
      [Color(0xFF00F0FF), Color(0xFF7B00FF)],
      [Color(0xFFFFFFFF), Color(0xFF00FFC4)],
      Color(0xFF00FFD1),
      24,
    ),
  };

  // Los shaders de gradiente solo dependen del tier y del tamaño (nunca del
  // frame de animación), así que se cachean entre frames y entre instancias
  // del painter. El tamaño de una llama es estable salvo durante la
  // transición elástica de tier; se acota la caché por si acaso.
  static final Map<(StreakTier, int, double, double), Shader> _shaderCache = {};

  static Shader _cachedShader(
    StreakTier tier,
    int slot,
    double w,
    double h,
    Shader Function() create,
  ) {
    if (_shaderCache.length > 96) _shaderCache.clear();
    return _shaderCache.putIfAbsent((tier, slot, w, h), create);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Draw dormant/unlit flame
    if (tier == StreakTier.unlit) {
      _paintUnlitFlame(canvas, size);
      return;
    }

    final style = _styles[tier];
    if (style == null) return;
    final outerColors = style.outer;
    final innerColors = style.inner;
    final coreColors = style.core;

    // 1. Draw Outer Glow (pulsing shadow)
    final glowPulse = 1.0 + 0.15 * math.sin(animationValue * 2 * math.pi);
    final glowPaint = Paint()
      ..shader = _cachedShader(
        tier,
        0,
        w,
        h,
        () => RadialGradient(
          colors: outerColors,
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
      )
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.22 * glowPulse);

    canvas.drawCircle(Offset(w / 2, h * 0.65), w * 0.35, glowPaint);

    // 2. Draw Flame Layers
    final t = animationValue * 2 * math.pi;

    // Outer Layer
    final outerPath = _getFlamePath(
      size: size,
      waveX: math.sin(t) * (w * 0.05),
      waveY: math.cos(t) * (h * 0.03),
      leftWave: math.sin(t + 1) * (w * 0.02),
      rightWave: math.cos(t + 2) * (w * 0.02),
      scale: 1.0,
      offsetY: 0.0,
    );
    final outerPaint = Paint()
      ..shader = _cachedShader(
        tier,
        1,
        w,
        h,
        () => LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: outerColors,
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
      );
    canvas.drawPath(outerPath, outerPaint);

    // Inner Layer
    final innerPath = _getFlamePath(
      size: size,
      waveX: math.sin(t + 2) * (w * 0.06),
      waveY: math.cos(t + 1) * (h * 0.04),
      leftWave: math.sin(t + 3) * (w * 0.03),
      rightWave: math.cos(t + 4) * (w * 0.03),
      scale: 0.74,
      offsetY: h * 0.08,
    );
    final innerPaint = Paint()
      ..shader = _cachedShader(
        tier,
        2,
        w,
        h,
        () => LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: innerColors,
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
      );
    canvas.drawPath(innerPath, innerPaint);

    // Core Layer
    final corePath = _getFlamePath(
      size: size,
      waveX: math.sin(t + 4) * (w * 0.07),
      waveY: math.cos(t + 3) * (h * 0.05),
      leftWave: math.sin(t + 5) * (w * 0.04),
      rightWave: math.cos(t + 6) * (w * 0.04),
      scale: 0.44,
      offsetY: h * 0.18,
    );
    final corePaint = Paint()
      ..shader = _cachedShader(
        tier,
        3,
        w,
        h,
        () => LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: coreColors,
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
      );
    canvas.drawPath(corePath, corePaint);

    // 3. Draw Spark Particles
    _paintParticles(canvas, size, style.particle, style.particleCount);
  }

  Path _getFlamePath({
    required Size size,
    required double waveX,
    required double waveY,
    required double leftWave,
    required double rightWave,
    required double scale,
    required double offsetY,
  }) {
    final w = size.width;
    final h = size.height;

    final cx = w / 2;
    final cy = h * 0.9 - offsetY;

    // Apply scale relative to center bottom
    final sw = w * scale;
    final sh = h * scale;

    final path = Path();
    path.moveTo(cx, cy);
    path.quadraticBezierTo(
      cx - sw * 0.45 + leftWave,
      cy - sh * 0.25,
      cx - sw * 0.35 + leftWave,
      cy - sh * 0.5,
    );
    path.cubicTo(
      cx - sw * 0.4 + leftWave,
      cy - sh * 0.75,
      cx - sw * 0.1 + waveX,
      cy - sh * 0.85 + waveY,
      cx + waveX,
      cy - sh * 1.0 + waveY,
    );
    path.cubicTo(
      cx + sw * 0.15 + waveX,
      cy - sh * 0.8 + waveY,
      cx + sw * 0.45 + rightWave,
      cy - sh * 0.65,
      cx + sw * 0.35 + rightWave,
      cy - sh * 0.45,
    );
    path.quadraticBezierTo(
      cx + sw * 0.4 + rightWave,
      cy - sh * 0.2,
      cx,
      cy,
    );
    path.close();
    return path;
  }

  void _paintUnlitFlame(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    
    final path = _getFlamePath(
      size: size,
      waveX: 0,
      waveY: 0,
      leftWave: 0,
      rightWave: 0,
      scale: 0.9,
      offsetY: 0,
    );

    final strokePaint = Paint()
      ..color = const Color(0xFF6E6E77).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final fillPaint = Paint()
      ..color = const Color(0xFF3F3F46).withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
    
    final emberPaint = Paint()
      ..color = const Color(0xFF71717A).withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(Offset(w / 2, h * 0.72), w * 0.12, emberPaint);
  }

  void _paintParticles(Canvas canvas, Size size, Color color, int count) {
    final w = size.width;
    final h = size.height;

    for (int i = 0; i < count; i++) {
      final offset = i * (1.0 / count);
      final p = (animationValue + offset) % 1.0;
      final py = h * (0.8 - p * 0.7);
      final px = w / 2 + math.sin(p * 3 * math.pi + i * 1.5) * (w * 0.2) * p;
      final radius = (1.0 - p) * (w * 0.05).clamp(1.0, 3.0);
      final opacity = math.sin(p * math.pi);

      final paint = Paint()
        ..color = color.withValues(alpha: opacity * 0.75)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8);

      canvas.drawCircle(Offset(px, py), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant FlamePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue || oldDelegate.tier != tier;
  }
}
