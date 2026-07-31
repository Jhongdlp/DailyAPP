import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/bento_theme.dart';
import '../pomodoro_palette.dart';
import '../providers/pomodoro_provider.dart';

/// El reloj de la sesión: plato neumórfico hundido, corona de marcas de minuto
/// que se van encendiendo y arco de progreso con halo.
///
/// Es el único widget que se reconstruye cada segundo — por eso escucha solo
/// los campos del tic y no el estado entero, y por eso el resto de la pantalla
/// puede permitirse sombras caras sin repintarlas 60 veces por minuto.
class FocusDial extends ConsumerWidget {
  final double size;

  const FocusDial({super.key, required this.size});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tick = ref.watch(pomodoroProvider.select((s) => (
          timeLeft: s.timeLeft,
          progress: s.progress,
          phase: s.phase,
          isActive: s.isActive,
          endsAt: s.endsAt,
        )));

    final color = PomodoroPalette.of(tick.phase);
    final minutes = (tick.timeLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (tick.timeLeft % 60).toString().padLeft(2, '0');

    // Todo el interior escala con el diámetro: así el mismo dial sirve para un
    // móvil en horizontal y para una tablet sin ajustes por caso.
    final timeFont = size * 0.235;
    final hintFont = (size * 0.055).clamp(9.0, 13.0);

    return Semantics(
      label: '${tick.phase.label}, quedan $minutes minutos $seconds segundos',
      button: true,
      child: GestureDetector(
        onTap: () => ref.read(pomodoroProvider.notifier).toggle(),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Plato hundido: el tiempo ocurre DENTRO de la superficie.
              Positioned.fill(
                child: NeuPressed(
                  borderRadius: size / 2,
                  distance: size * 0.02,
                  blur: size * 0.05,
                  child: const SizedBox.shrink(),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _DialPainter(
                      progress: tick.progress,
                      color: color,
                      running: tick.isActive,
                      trackColor: BentoTheme.neuShadowDark.withValues(alpha: 0.35),
                      tickColor: BentoTheme.creamAlpha(0.14),
                    ),
                  ),
                ),
              ),
              // El reloj es un elemento gráfico: su tamaño ya sale del diámetro
              // del plato, así que el escalado de fuente del sistema aquí solo
              // conseguiría reventar el círculo. Los dígitos son, de lejos, el
              // texto más grande de la pantalla.
              MediaQuery.withNoTextScaling(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$minutes:$seconds',
                      style: GoogleFonts.shareTechMono(
                        fontSize: timeFont,
                        height: 1.0,
                        color: BentoTheme.cream,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -1.0,
                      ),
                    ),
                    SizedBox(height: size * 0.045),
                    // Saber a qué hora acaba quita la necesidad de volver a
                    // mirar: el bloque deja de ser una cuenta atrás y pasa a
                    // ser una cita.
                    Text(
                      tick.isActive && tick.endsAt != null
                          ? 'termina ${formatClock(tick.endsAt!)}'
                          : 'en pausa',
                      style: GoogleFonts.montserrat(
                        fontSize: hintFont,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                        color: tick.isActive
                            ? BentoTheme.creamAlpha(0.38)
                            : color.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool running;
  final Color trackColor;
  final Color tickColor;

  _DialPainter({
    required this.progress,
    required this.color,
    required this.running,
    required this.trackColor,
    required this.tickColor,
  });

  static const int _tickCount = 60;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, size.height / 2);

    final strokeWidth = (size.width * 0.028).clamp(3.0, 7.0);
    final arcRadius = radius - strokeWidth * 1.6;
    final rect = Rect.fromCircle(center: center, radius: arcRadius);

    // Corona de marcas: da lectura analógica del avance sin tener que
    // interpretar el arco, y le pone cara de instrumento al plato.
    final tickOuter = arcRadius - strokeWidth * 1.6;
    final tickInner = tickOuter - size.width * 0.035;
    final passed = (progress * _tickCount).floor();

    for (var i = 0; i < _tickCount; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / _tickCount);
      final isMajor = i % 5 == 0;
      final lit = i < passed;

      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = isMajor ? 2.2 : 1.2
        ..color = lit
            ? color.withValues(alpha: isMajor ? 0.75 : 0.45)
            : (isMajor ? tickColor.withValues(alpha: 0.9) : tickColor);

      final from = tickInner + (isMajor ? 0 : size.width * 0.012);
      canvas.drawLine(
        center + Offset(math.cos(angle) * from, math.sin(angle) * from),
        center + Offset(math.cos(angle) * tickOuter, math.sin(angle) * tickOuter),
        paint,
      );
    }

    // Carril del arco
    canvas.drawCircle(
      center,
      arcRadius,
      Paint()
        ..color = trackColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke,
    );

    if (progress <= 0) return;

    final sweep = 2 * math.pi * progress;

    // Halo. En pausa se apaga: la pantalla deja de "respirar" y se nota que el
    // reloj está parado incluso de reojo.
    if (running) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..color = color.withValues(alpha: 0.28)
          ..strokeWidth = strokeWidth * 2.4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeWidth),
      );
    }

    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..color = running ? color : color.withValues(alpha: 0.5)
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Cabeza del arco: el punto que avanza es lo que hace el progreso legible
    // en un vistazo de medio segundo.
    final headAngle = -math.pi / 2 + sweep;
    final head = center +
        Offset(math.cos(headAngle) * arcRadius, math.sin(headAngle) * arcRadius);
    canvas.drawCircle(
      head,
      strokeWidth * 0.95,
      Paint()..color = running ? color : color.withValues(alpha: 0.5),
    );
    canvas.drawCircle(
      head,
      strokeWidth * 0.42,
      Paint()..color = Colors.white.withValues(alpha: running ? 0.9 : 0.4),
    );
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.running != running ||
      old.trackColor != trackColor ||
      old.tickColor != tickColor;
}
