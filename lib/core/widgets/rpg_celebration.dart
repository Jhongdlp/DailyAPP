import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/bento_theme.dart';

class RpgCelebration {
  static void show(
    BuildContext context, {
    required int xp,
    required int gold,
    bool levelUp = false,
    int? newLevel,
  }) {
    final overlayState = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _CelebrationOverlayWidget(
        xp: xp,
        gold: gold,
        levelUp: levelUp,
        newLevel: newLevel,
        onDismiss: () {
          overlayEntry.remove();
        },
      ),
    );

    overlayState.insert(overlayEntry);
  }
}

class _CelebrationOverlayWidget extends StatefulWidget {
  final int xp;
  final int gold;
  final bool levelUp;
  final int? newLevel;
  final VoidCallback onDismiss;

  const _CelebrationOverlayWidget({
    required this.xp,
    required this.gold,
    required this.levelUp,
    this.newLevel,
    required this.onDismiss,
  });

  @override
  State<_CelebrationOverlayWidget> createState() => _CelebrationOverlayWidgetState();
}

class _CelebrationOverlayWidgetState extends State<_CelebrationOverlayWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _controller.forward();

    // Auto dismiss after duration
    final duration = widget.levelUp ? const Duration(milliseconds: 4000) : const Duration(milliseconds: 2500);
    _dismissTimer = Timer(duration, _dismiss);
  }

  void _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: widget.levelUp ? 0 : MediaQuery.viewPaddingOf(context).top + 16,
      left: 0,
      right: 0,
      bottom: widget.levelUp ? 0 : null,
      child: Material(
        color: Colors.transparent,
        child: widget.levelUp 
            ? _buildLevelUpWidget()
            : _buildXpGoldWidget(),
      ),
    );
  }

  // 1. Notificación pequeña flotante para XP y Oro (Tactile HUD)
  Widget _buildXpGoldWidget() {
    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                // Fondo oscuro translúcido con efecto glass
                color: BentoTheme.darkBg.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: BentoTheme.accentHabits.withValues(alpha: 0.25),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: BentoTheme.accentHabits.withValues(alpha: 0.15),
                    blurRadius: 18,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, color: BentoTheme.accentPurple, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '+${widget.xp} XP',
                    style: GoogleFonts.montserrat(
                      color: BentoTheme.accentPurple,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 2. Celebración de Pantalla Completa de Subida de Nivel (Level Up Pop-up)
  Widget _buildLevelUpWidget() {
    return Stack(
      children: [
        // Fondo semi-transparente que oscurece la pantalla
        Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.70),
          ),
        ),
        
        // Confeti animado básico
        const Positioned.fill(
          child: IgnorePointer(
            child: _ConfettiShower(),
          ),
        ),

        // Tarjeta central de celebración
        Center(
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                decoration: BoxDecoration(
                  color: BentoTheme.darkCard.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: BentoTheme.accentLime.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: BentoTheme.accentLime.withValues(alpha: 0.25),
                      blurRadius: 36,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Corona o Trofeo Flotante con Brillo
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: BentoTheme.accentLime.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: BentoTheme.accentLime.withValues(alpha: 0.2),
                            blurRadius: 20,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          Icons.emoji_events_outlined,
                          size: 44,
                          color: BentoTheme.accentLime,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Texto SUBE DE NIVEL
                    Text(
                      '¡NIVEL COMPLETADO!',
                      style: GoogleFonts.montserrat(
                        color: BentoTheme.accentLime,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Nivel Nuevo
                    Text(
                      'Nivel ${widget.newLevel ?? 2}',
                      style: GoogleFonts.montserrat(
                        color: BentoTheme.cream,
                        fontWeight: FontWeight.w900,
                        fontSize: 44,
                        letterSpacing: -1,
                      ),
                    ),
                    
                    const SizedBox(height: 12),
                    Text(
                      '¡Tu disciplina y constancia están dando frutos! Sigue construyendo tu mejor versión.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: BentoTheme.creamAlpha(0.65),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 28),
                    
                    // Botón de continuar
                    GestureDetector(
                      onTap: _dismiss,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        decoration: BoxDecoration(
                          color: BentoTheme.accentLime,
                          borderRadius: BorderRadius.circular(100),
                          boxShadow: [
                            BoxShadow(
                              color: BentoTheme.accentLime.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          '¡Excelente!',
                          style: GoogleFonts.montserrat(
                            color: BentoTheme.darkBg,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Lluvia de confeti de partículas flotantes
class _ConfettiShower extends StatefulWidget {
  const _ConfettiShower();

  @override
  State<_ConfettiShower> createState() => _ConfettiShowerState();
}

class _ConfettiShowerState extends State<_ConfettiShower> with SingleTickerProviderStateMixin {
  late AnimationController _particleController;
  final List<_ConfettiParticle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addListener(() {
        setState(() {});
      });

    // Crear partículas
    for (int i = 0; i < 60; i++) {
      _particles.add(
        _ConfettiParticle(
          x: _random.nextDouble(),
          y: _random.nextDouble() * -0.5, // Empezar arriba de la pantalla
          speed: 0.15 + _random.nextDouble() * 0.25,
          angle: _random.nextDouble() * 2 * pi,
          rotationSpeed: _random.nextDouble() * 4 - 2,
          color: _randomColor(),
          size: 6 + _random.nextDouble() * 10,
        ),
      );
    }

    _particleController.forward();
  }

  Color _randomColor() {
    final colors = [
      BentoTheme.accentLime,
      BentoTheme.accentPurple,
      BentoTheme.accentHabits,
      BentoTheme.accentAlarm,
      BentoTheme.accentFinance,
      const Color(0xFFFFB236),
    ];
    return colors[_random.nextInt(colors.length)];
  }

  @override
  void dispose() {
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _particleController.value;
    return CustomPaint(
      painter: _ConfettiPainter(
        particles: _particles,
        progress: progress,
      ),
      size: Size.infinite,
    );
  }
}

class _ConfettiParticle {
  final double x; // Relativo al ancho (0.0 a 1.0)
  double y; // Relativo al alto
  final double speed;
  final double angle;
  final double rotationSpeed;
  final Color color;
  final double size;

  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.angle,
    required this.rotationSpeed,
    required this.color,
    required this.size,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      // Calcular la posición actual de la partícula en base al progreso
      final currentY = size.height * (p.y + (progress * p.speed));
      final currentX = size.width * (p.x + sin(progress * 4 + p.angle) * 0.05);

      if (currentY > size.height || currentY < 0) continue;

      paint.color = p.color;

      canvas.save();
      canvas.translate(currentX, currentY);
      canvas.rotate(progress * p.rotationSpeed);

      // Dibujar cuadraditos u óvalos de confeti
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
        paint,
      );

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}
