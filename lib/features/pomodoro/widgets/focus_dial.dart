import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/bento_theme.dart';
import '../pomodoro_palette.dart';
import '../providers/pomodoro_provider.dart';

/// El reloj de la sesión: un aro fino y la hora. Nada más.
///
/// Deliberadamente austero — sin plato, sin corona de marcas, sin halo. Lo que
/// se mira durante 25 minutos seguidos no debería tener nada que mirar: cuanto
/// menos dibujo, menos engancha la vista y más se queda en el trabajo.
///
/// Es el único widget que se reconstruye cada segundo, por eso escucha solo los
/// campos del tic y no el estado entero.
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

    // Todo el interior sale del diámetro, así que el mismo dial sirve para un
    // móvil en horizontal y para una tablet sin ajustes por caso.
    final timeFont = size * 0.26;
    final hintFont = (size * 0.052).clamp(8.5, 12.0).toDouble();

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
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _DialPainter(
                      progress: tick.progress,
                      color: color,
                      running: tick.isActive,
                      trackColor: BentoTheme.creamAlpha(0.09),
                    ),
                  ),
                ),
              ),
              // El reloj es un elemento gráfico: su tamaño ya sale del aro, así
              // que el escalado de fuente del sistema aquí solo conseguiría
              // reventar el círculo. Los dígitos son, de lejos, el texto más
              // grande de la pantalla.
              MediaQuery.withNoTextScaling(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: size * 0.14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Por si una fuente sustituta midiera más de lo previsto:
                      // encoge antes que desbordar.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '$minutes:$seconds',
                          style: GoogleFonts.shareTechMono(
                            fontSize: timeFont,
                            height: 1.0,
                            color: BentoTheme.creamAlpha(0.92),
                            letterSpacing: -1.0,
                          ),
                        ),
                      ),
                      SizedBox(height: size * 0.05),
                      // Saber a qué hora acaba quita la necesidad de volver a
                      // mirar: el bloque deja de ser una cuenta atrás y pasa a
                      // ser una cita.
                      Text(
                        tick.isActive && tick.endsAt != null
                            ? formatClock(tick.endsAt!)
                            : 'en pausa',
                        maxLines: 1,
                        style: GoogleFonts.montserrat(
                          fontSize: hintFont,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 2.0,
                          color: tick.isActive
                              ? BentoTheme.creamAlpha(0.3)
                              : color.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dos círculos: el carril y lo recorrido. El arco avanza en vez de vaciarse
/// porque ver crecer lo hecho sostiene mejor que ver menguar lo que queda.
class _DialPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool running;
  final Color trackColor;

  _DialPainter({
    required this.progress,
    required this.color,
    required this.running,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    final center = Offset(radius, size.height / 2);

    // Un aro fino a secas: engorda un poco en pantallas grandes para no
    // desaparecer, pero nunca llega a ser una barra.
    final stroke = (size.width * 0.014).clamp(2.0, 4.0).toDouble();
    final arcRadius = radius - stroke;

    canvas.drawCircle(
      center,
      arcRadius,
      Paint()
        ..color = trackColor
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke,
    );

    if (progress <= 0) return;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: arcRadius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        // En pausa el aro se apaga a medias: se nota que el reloj está parado
        // sin necesidad de leer nada.
        ..color = running ? color : color.withValues(alpha: 0.4)
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _DialPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.running != running ||
      old.trackColor != trackColor;
}
