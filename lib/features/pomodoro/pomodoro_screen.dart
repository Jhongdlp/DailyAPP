import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/providers/focus_stats_provider.dart';
import '../../core/theme/bento_theme.dart';
import 'pomodoro_palette.dart';
import 'providers/pomodoro_provider.dart';
import 'widgets/break_panels.dart';
import 'widgets/distraction_inbox.dart';
import 'widgets/focus_dial.dart';
import 'widgets/focus_task_card.dart';

/// Medidas derivadas del hueco real, no de constantes por dispositivo.
///
/// Todo lo que ocupa sitio (dial, botones, huecos) sale de aquí, así que la
/// pantalla se adapta igual a un móvil en horizontal, a una tablet o a una
/// ventana de escritorio sin ramas por caso.
class _Sizing {
  final bool landscape;
  final bool compact;
  final double dial;
  final double controlBig;
  final double controlSmall;
  final double gap;

  const _Sizing({
    required this.landscape,
    required this.compact,
    required this.dial,
    required this.controlBig,
    required this.controlSmall,
    required this.gap,
  });

  factory _Sizing.from(BoxConstraints c) {
    final w = c.maxWidth;
    final h = c.maxHeight;
    final landscape = w > h;
    // En horizontal la altura es el recurso escaso; en vertical, el ancho.
    final compact = landscape ? h < 430 : h < 660;

    final dial = landscape
        ? math.min(w * 0.36, h * 0.62).clamp(120.0, 250.0)
        : math.min(w - 88, h * 0.33).clamp(150.0, 300.0);

    return _Sizing(
      landscape: landscape,
      compact: compact,
      dial: dial.toDouble(),
      controlBig: compact ? 54 : 62,
      controlSmall: compact ? 42 : 47,
      gap: compact ? 12 : 18,
    );
  }
}

class PomodoroScreen extends ConsumerStatefulWidget {
  const PomodoroScreen({super.key});

  @override
  ConsumerState<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends ConsumerState<PomodoroScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Que la pantalla no se apague es un extra: si la plataforma no lo soporta
    // (escritorio, test) la sesión sigue igual de válida.
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Los `Timer` no corren en segundo plano: al volver hay que reconciliar el
    // reloj con la hora objetivo, no con los tics perdidos.
    if (state == AppLifecycleState.resumed) {
      ref.read(pomodoroProvider.notifier).syncWithBackground();
    }
  }

  Future<bool> _confirmExit() async {
    final running = ref.read(pomodoroProvider).isActive;
    if (!running) return true;

    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BentoTheme.neuSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          '¿Terminar la sesión?',
          style: GoogleFonts.montserrat(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: BentoTheme.cream,
          ),
        ),
        content: Text(
          'El bloque en curso se cortará aquí. Los minutos que llevas enfocado sí se guardan.',
          style: GoogleFonts.outfit(
            fontSize: 14,
            height: 1.45,
            color: BentoTheme.creamAlpha(0.65),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Seguir enfocado',
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w700,
                color: PomodoroPalette.focus,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Terminar',
              style: GoogleFonts.montserrat(
                fontWeight: FontWeight.w600,
                color: BentoTheme.creamAlpha(0.6),
              ),
            ),
          ),
        ],
      ),
    );

    return leave ?? false;
  }

  /// Salir es siempre lo mismo venga del botón o del gesto atrás: confirmar,
  /// cerrar el bloque (que registra los minutos ya enfocados) y volver.
  Future<void> _exitSession() async {
    if (!await _confirmExit()) return;
    if (!mounted) return;
    ref.read(pomodoroProvider.notifier).stop();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // El resto de la pantalla NO escucha `timeLeft`: el tic de cada segundo
    // solo repinta el dial, que es el único que cambia. Sin esto, cada segundo
    // reconstruiría una decena de piezas neumórficas con sus sombras.
    final view = ref.watch(pomodoroProvider.select((s) => (
          phase: s.phase,
          isActive: s.isActive,
          cycleInSet: s.cycleInSet,
          setSize: s.prefs.sessionsBeforeLongBreak,
          panelMode: s.prefs.breakPanelMode,
          carouselIndex: s.carouselIndex,
          completed: s.completedFocusSessions,
        )));

    final accent = PomodoroPalette.of(view.phase);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _exitSession();
      },
      child: Scaffold(
        backgroundColor: BentoTheme.neuSurface,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final sizing = _Sizing.from(constraints);
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: sizing.landscape ? 16 : 20,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(
                      phase: view.phase,
                      accent: accent,
                      completed: view.completed,
                      onBack: _exitSession,
                    ),
                    SizedBox(height: sizing.gap * 0.6),
                    Expanded(
                      child: sizing.landscape
                          ? _LandscapeBody(
                              sizing: sizing,
                              phase: view.phase,
                              accent: accent,
                              cycleInSet: view.cycleInSet,
                              setSize: view.setSize,
                              panelMode: view.panelMode,
                              carouselIndex: view.carouselIndex,
                            )
                          : _PortraitBody(
                              sizing: sizing,
                              phase: view.phase,
                              accent: accent,
                              cycleInSet: view.cycleInSet,
                              setSize: view.setSize,
                              panelMode: view.panelMode,
                              carouselIndex: view.carouselIndex,
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Cuerpos por orientación ──────────────────────────────────────────────

class _PortraitBody extends StatelessWidget {
  final _Sizing sizing;
  final PomodoroPhase phase;
  final Color accent;
  final int cycleInSet;
  final int setSize;
  final int panelMode;
  final int carouselIndex;

  const _PortraitBody({
    required this.sizing,
    required this.phase,
    required this.accent,
    required this.cycleInSet,
    required this.setSize,
    required this.panelMode,
    required this.carouselIndex,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // El panel de descanso ocupa una fracción del hueco real, nunca una
        // altura fija: en una pantalla baja encoge en vez de empujar.
        final panelHeight =
            (constraints.maxHeight * 0.34).clamp(150.0, 280.0).toDouble();

        // Scroll de seguridad: si la suma no cabe (pantalla muy baja, fuente
        // del sistema al 200 %), la pantalla se desliza en lugar de cortarse.
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: FocusDial(size: sizing.dial)),
                SizedBox(height: sizing.gap),
                _CycleDots(
                  cycleInSet: cycleInSet,
                  setSize: setSize,
                  accent: accent,
                ),
                SizedBox(height: sizing.gap),
                _Controls(sizing: sizing, accent: accent, phase: phase),
                SizedBox(height: sizing.gap),
                if (phase.isFocus) ...[
                  const FocusTaskCard(),
                  SizedBox(height: sizing.gap * 0.6),
                  const _ParkDistractionButton(),
                ] else ...[
                  BreakPanelTabs(mode: panelMode, accent: accent),
                  SizedBox(height: sizing.gap * 0.7),
                  SizedBox(
                    height: panelHeight,
                    child: BreakPanelContent(
                      mode: panelMode,
                      carouselIndex: carouselIndex,
                      accent: accent,
                    ),
                  ),
                  SizedBox(height: sizing.gap * 0.7),
                  const DistractionInbox(),
                ],
                SizedBox(height: sizing.gap),
                const _TodayStrip(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LandscapeBody extends StatelessWidget {
  final _Sizing sizing;
  final PomodoroPhase phase;
  final Color accent;
  final int cycleInSet;
  final int setSize;
  final int panelMode;
  final int carouselIndex;

  const _LandscapeBody({
    required this.sizing,
    required this.phase,
    required this.accent,
    required this.cycleInSet,
    required this.setSize,
    required this.panelMode,
    required this.carouselIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Columna del reloj. Va en su propio scroll para que un móvil muy bajo
        // en horizontal deslice el reloj sin arrastrar el panel de al lado.
        Expanded(
          flex: 5,
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FocusDial(size: sizing.dial),
                    SizedBox(height: sizing.gap * 0.8),
                    _CycleDots(
                      cycleInSet: cycleInSet,
                      setSize: setSize,
                      accent: accent,
                    ),
                    SizedBox(height: sizing.gap * 0.8),
                    _Controls(sizing: sizing, accent: accent, phase: phase),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: sizing.gap),
        // Columna de contexto: qué estás haciendo (enfoque) o qué miras
        // mientras descansas. Mismo patrón que en vertical —altura mínima del
        // hueco más scroll— para que con la fuente del sistema al 200 % la
        // columna deslice en vez de recortarse.
        Expanded(
          flex: 6,
          child: LayoutBuilder(
            builder: (context, c) {
              final panelHeight =
                  (c.maxHeight * 0.62).clamp(140.0, 420.0).toDouble();

              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (phase.isFocus) ...[
                        const FocusTaskCard(compact: true),
                        SizedBox(height: sizing.gap * 0.6),
                        const _ParkDistractionButton(),
                        SizedBox(height: sizing.gap * 0.6),
                        const DistractionInbox(),
                      ] else ...[
                        BreakPanelTabs(mode: panelMode, accent: accent),
                        SizedBox(height: sizing.gap * 0.6),
                        SizedBox(
                          height: panelHeight,
                          child: BreakPanelContent(
                            mode: panelMode,
                            carouselIndex: carouselIndex,
                            accent: accent,
                          ),
                        ),
                      ],
                      SizedBox(height: sizing.gap * 0.6),
                      const _TodayStrip(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Piezas ───────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final PomodoroPhase phase;
  final Color accent;
  final int completed;
  final VoidCallback onBack;

  const _TopBar({
    required this.phase,
    required this.accent,
    required this.completed,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        NeuCard(
          borderRadius: 16,
          distance: 3,
          blur: 6,
          padding: EdgeInsets.zero,
          onTap: onBack,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(Icons.arrow_back_ios_new_rounded,
                size: 15, color: BentoTheme.creamAlpha(0.6)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.5),
                      blurRadius: 7,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  phase.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.montserrat(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3.0,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 38,
          height: 38,
          child: completed == 0
              ? null
              : Center(
                  child: Text(
                    '×$completed',
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: BentoTheme.creamAlpha(0.4),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Puntos de la tanda: cuántos enfoques van hasta el descanso largo. Es la
/// única "gamificación" en pantalla durante el enfoque, y es información pura.
class _CycleDots extends StatelessWidget {
  final int cycleInSet;
  final int setSize;
  final Color accent;

  const _CycleDots({
    required this.cycleInSet,
    required this.setSize,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(setSize, (i) {
        final done = i < cycleInSet;
        final current = i == cycleInSet;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: done || current ? 22 : 14,
            height: 5,
            decoration: BoxDecoration(
              color: done
                  ? accent
                  : (current
                      ? accent.withValues(alpha: 0.4)
                      : BentoTheme.creamAlpha(0.12)),
              borderRadius: BorderRadius.circular(100),
            ),
          ),
        );
      }),
    );
  }
}

class _Controls extends ConsumerWidget {
  final _Sizing sizing;
  final Color accent;
  final PomodoroPhase phase;

  const _Controls({
    required this.sizing,
    required this.accent,
    required this.phase,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = ref.watch(pomodoroProvider.select((s) => s.isActive));
    final notifier = ref.read(pomodoroProvider.notifier);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CircleButton(
          icon: Icons.add_rounded,
          label: '5 min',
          size: sizing.controlSmall,
          color: BentoTheme.creamAlpha(0.55),
          onTap: () => notifier.extendPhase(5),
        ),
        SizedBox(width: sizing.gap),
        _CircleButton(
          icon: isActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: sizing.controlBig,
          color: accent,
          tint: true,
          onTap: () {
            HapticFeedback.mediumImpact();
            notifier.toggle();
          },
        ),
        SizedBox(width: sizing.gap),
        _CircleButton(
          icon: Icons.skip_next_rounded,
          label: phase.isFocus ? 'descanso' : 'enfoque',
          size: sizing.controlSmall,
          color: BentoTheme.creamAlpha(0.55),
          onTap: notifier.skip,
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final double size;
  final Color color;
  final bool tint;
  final VoidCallback onTap;

  const _CircleButton({
    required this.icon,
    this.label,
    required this.size,
    required this.color,
    this.tint = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        NeuCard(
          borderRadius: size / 2,
          distance: tint ? 5 : 4,
          blur: tint ? 10 : 8,
          padding: EdgeInsets.zero,
          color: tint ? color.withValues(alpha: 0.14) : null,
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * 0.44, color: color),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 5),
          Text(
            label!,
            style: GoogleFonts.montserrat(
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: BentoTheme.creamAlpha(0.3),
            ),
          ),
        ],
      ],
    );
  }
}

class _ParkDistractionButton extends ConsumerWidget {
  const _ParkDistractionButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count =
        ref.watch(pomodoroProvider.select((s) => s.distractions.length));

    return NeuCard(
      borderRadius: 16,
      distance: 3,
      blur: 6,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onTap: () => showDistractionCapture(context),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bolt_rounded, size: 16, color: BentoTheme.accentOrange),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Se me ha cruzado algo',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.montserrat(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: BentoTheme.creamAlpha(0.6),
              ),
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: BentoTheme.accentOrange.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: BentoTheme.accentOrange,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lo enfocado hoy, la racha y los bloques del día. Cierra el bucle: la sesión
/// deja de ser un temporizador suelto y pasa a alimentar un número que sube.
class _TodayStrip extends ConsumerWidget {
  const _TodayStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(focusStatsProvider);

    return NeuPressed(
      borderRadius: 16,
      lite: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat(
            value: formatFocusDuration(stats.todayMinutes),
            label: 'hoy',
          ),
          _Divider(),
          _Stat(value: '${stats.todayPomodoros}', label: 'bloques'),
          _Divider(),
          _Stat(
            value: '${stats.streak}',
            label: stats.streak == 1 ? 'día seguido' : 'días seguidos',
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      color: BentoTheme.creamAlpha(0.08),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;

  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: BentoTheme.creamAlpha(0.85),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.montserrat(
              fontSize: 8.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: BentoTheme.creamAlpha(0.32),
            ),
          ),
        ],
      ),
    );
  }
}
