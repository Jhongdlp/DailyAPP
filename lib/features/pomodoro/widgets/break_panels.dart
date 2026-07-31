import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/task_model.dart';
import '../../../core/providers/tasks_provider.dart';
import '../../../core/theme/bento_theme.dart';
import '../pomodoro_palette.dart';
import '../providers/pomodoro_provider.dart';

/// Modos del panel de descanso. Existen solo aquí: durante el enfoque la
/// pantalla no ofrece nada que mirar, que es justo lo que la hace útil.
class BreakPanelMode {
  static const quote = 0;
  static const image = 1;
  static const breathing = 2;
  static const tasks = 3;

  static const icons = <int, IconData>{
    quote: Icons.format_quote_rounded,
    image: Icons.image_outlined,
    breathing: Icons.spa_outlined,
    tasks: Icons.checklist_rounded,
  };

  static const labels = <int, String>{
    quote: 'Frase',
    image: 'Paisaje',
    breathing: 'Respirar',
    tasks: 'Agenda',
  };
}

class BreakPanelTabs extends ConsumerWidget {
  final int mode;
  final Color accent;

  const BreakPanelTabs({super.key, required this.mode, required this.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NeuCard(
      borderRadius: 18,
      distance: 3,
      blur: 6,
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          for (final entry in BreakPanelMode.icons.entries)
            Expanded(
              child: _Tab(
                icon: entry.value,
                label: BreakPanelMode.labels[entry.key]!,
                selected: entry.key == mode,
                accent: accent,
                onTap: () =>
                    ref.read(pomodoroProvider.notifier).setBreakPanelMode(entry.key),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _Tab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: selected ? accent : BentoTheme.creamAlpha(0.4),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.montserrat(
              fontSize: 8.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0.4,
              color: selected ? BentoTheme.cream : BentoTheme.creamAlpha(0.4),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // `lite` porque son cuatro huecos en fila y se repintan al cambiar de
      // pestaña: el hueco caro aquí no aporta nada y cuesta dos blurs.
      child: selected
          ? NeuPressed(
              borderRadius: 14,
              lite: true,
              padding: EdgeInsets.zero,
              child: content,
            )
          : content,
    );
  }
}

/// Contenido del panel de descanso. Se le pasa la altura disponible ya
/// resuelta por el layout, de modo que nunca decide su propio tamaño ni puede
/// desbordar al padre.
class BreakPanelContent extends ConsumerStatefulWidget {
  final int mode;
  final int carouselIndex;
  final Color accent;

  const BreakPanelContent({
    super.key,
    required this.mode,
    required this.carouselIndex,
    required this.accent,
  });

  @override
  ConsumerState<BreakPanelContent> createState() => _BreakPanelContentState();
}

class _BreakPanelContentState extends ConsumerState<BreakPanelContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathing;

  /// Semilla por sesión de pantalla: las frases y las fotos cambian cada vez
  /// que se entra, no cada vez que se reconstruye.
  final int _seed = DateTime.now().millisecondsSinceEpoch % 9973;

  @override
  void initState() {
    super.initState();
    // Respiración cuadrada: 4 s por lado.
    _breathing = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    );
    if (widget.mode == BreakPanelMode.breathing) _breathing.repeat();
  }

  @override
  void didUpdateWidget(covariant BreakPanelContent old) {
    super.didUpdateWidget(old);
    // La animación solo corre cuando se está viendo: un controlador latiendo
    // detrás de otra pestaña es un frame de más por cada vsync.
    if (widget.mode == BreakPanelMode.breathing) {
      if (!_breathing.isAnimating) _breathing.repeat();
    } else if (_breathing.isAnimating) {
      _breathing.stop();
    }
  }

  @override
  void dispose() {
    _breathing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: switch (widget.mode) {
        BreakPanelMode.image => _ImagePanel(
            key: ValueKey('img_${widget.carouselIndex}'),
            index: widget.carouselIndex,
            seed: _seed,
            accent: widget.accent,
          ),
        BreakPanelMode.breathing => _BreathingPanel(
            key: const ValueKey('breathing'),
            controller: _breathing,
            accent: widget.accent,
          ),
        BreakPanelMode.tasks => _TasksPanel(
            key: const ValueKey('tasks'),
            accent: widget.accent,
          ),
        _ => _QuotePanel(
            key: ValueKey('quote_${widget.carouselIndex}'),
            index: widget.carouselIndex + _seed,
            accent: widget.accent,
          ),
      },
    );
  }
}

// ── Frases ───────────────────────────────────────────────────────────────

const _quotes = <({String text, String author})>[
  (text: 'La concentración es el secreto de la fuerza.', author: 'Ralph Waldo Emerson'),
  (text: 'No vigiles el reloj; haz lo que él hace: sigue adelante.', author: 'Sam Levenson'),
  (text: 'El secreto para salir adelante es comenzar.', author: 'Mark Twain'),
  (text: 'La disciplina es el puente entre las metas y los logros.', author: 'Jim Rohn'),
  (text: 'Un viaje de mil millas comienza con un solo paso.', author: 'Lao Tzu'),
  (text: 'Tu mente está para tener ideas, no para almacenarlas.', author: 'David Allen'),
  (text: 'La simplicidad es la máxima sofisticación.', author: 'Leonardo da Vinci'),
  (text: 'Primero, resuelve el problema. Después, escribe el código.', author: 'John Johnson'),
  (text: 'Controlar la complejidad es la esencia de la programación.', author: 'Brian Kernighan'),
  (text: 'La elegancia es un requisito del software, no un lujo.', author: 'Edsger Dijkstra'),
  (text: 'La mejor forma de predecir el futuro es inventarlo.', author: 'Alan Kay'),
  (text: 'Haz de cada día tu obra maestra.', author: 'John Wooden'),
  (text: 'La persistencia vence a la resistencia.', author: 'Constancia'),
  (text: 'En medio del caos, reside la oportunidad.', author: 'Albert Einstein'),
  (text: 'El enfoque es un músculo, y lo estás fortaleciendo ahora.', author: 'Crecimiento'),
  (text: 'Si automatizas un caos, solo consigues un caos automatizado.', author: 'Ingeniería'),
  (text: 'Descansar también es parte del trabajo.', author: 'Ritmo'),
  (text: 'Calma en la mente, fuerza en el alma.', author: 'Balance'),
];

class _QuotePanel extends StatelessWidget {
  final int index;
  final Color accent;

  const _QuotePanel({super.key, required this.index, required this.accent});

  @override
  Widget build(BuildContext context) {
    final quote = _quotes[index % _quotes.length];

    return NeuCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.format_quote_rounded,
                size: 30, color: accent.withValues(alpha: 0.22)),
            const SizedBox(height: 8),
            Text(
              quote.text,
              style: GoogleFonts.outfit(
                fontSize: 16,
                height: 1.5,
                fontWeight: FontWeight.w500,
                color: BentoTheme.creamAlpha(0.88),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 18,
                  height: 2,
                  color: accent.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    quote.author.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.montserrat(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Paisaje ──────────────────────────────────────────────────────────────

const _imageQueries = <String>[
  'https://loremflickr.com/800/800/landscape,nature,forest',
  'https://loremflickr.com/800/800/mountains,valley,scenery',
  'https://loremflickr.com/800/800/ocean,beach,coast',
  'https://loremflickr.com/800/800/lake,reflection,calm',
  'https://loremflickr.com/800/800/desert,dunes,sky',
];

class _ImagePanel extends StatelessWidget {
  final int index;
  final int seed;
  final Color accent;

  const _ImagePanel({
    super.key,
    required this.index,
    required this.seed,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    // `lock` fija qué foto devuelve loremflickr para esa semilla, de modo que
    // la imagen no baila entre reconstrucciones.
    final url = '${_imageQueries[index % _imageQueries.length]}?lock=${seed + index}';

    return NeuCard(
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2, color: accent),
              ),
            );
          },
          errorBuilder: (context, error, stack) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded,
                    size: 26, color: BentoTheme.creamAlpha(0.25)),
                const SizedBox(height: 8),
                Text(
                  'Sin conexión para cargar la imagen',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: BentoTheme.creamAlpha(0.35),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Respiración ──────────────────────────────────────────────────────────

class _BreathingPanel extends StatelessWidget {
  final AnimationController controller;
  final Color accent;

  const _BreathingPanel({
    super.key,
    required this.controller,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // El círculo se mide contra el hueco real, así que la guía encoge en
          // horizontal en vez de recortarse.
          final diameter =
              (math.min(constraints.maxWidth, constraints.maxHeight) - 64)
                  .clamp(70.0, 150.0);

          return AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final v = controller.value;
              final double scale;
              final String action;
              final int secondInStep = ((v % 0.25) / 0.25 * 4).floor() + 1;

              if (v < 0.25) {
                scale = 0.62 + 0.38 * Curves.easeInOut.transform(v / 0.25);
                action = 'Inhala';
              } else if (v < 0.50) {
                scale = 1.0;
                action = 'Mantén';
              } else if (v < 0.75) {
                scale = 1.0 - 0.38 * Curves.easeInOut.transform((v - 0.50) / 0.25);
                action = 'Exhala';
              } else {
                scale = 0.62;
                action = 'Vacío';
              }

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: diameter,
                    height: diameter,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: NeuPressed(
                            borderRadius: diameter / 2,
                            lite: true,
                            child: const SizedBox.shrink(),
                          ),
                        ),
                        Transform.scale(
                          scale: scale,
                          child: SizedBox(
                            width: diameter * 0.74,
                            height: diameter * 0.74,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: accent.withValues(alpha: 0.18),
                                border: Border.all(
                                  color: accent.withValues(alpha: 0.55),
                                  width: 1.5,
                                ),
                              ),
                              // Igual que el reloj: el número vive dentro de
                              // una figura medida, así que no escala con la
                              // fuente del sistema.
                              child: MediaQuery.withNoTextScaling(
                                child: Center(
                                  child: Text(
                                    '$secondInStep',
                                    style: GoogleFonts.shareTechMono(
                                      fontSize: diameter * 0.2,
                                      fontWeight: FontWeight.bold,
                                      color: accent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    action,
                    style: GoogleFonts.montserrat(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.0,
                      color: BentoTheme.cream,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Respiración cuadrada · 4-4-4-4',
                    style: GoogleFonts.montserrat(
                      fontSize: 9.5,
                      color: BentoTheme.creamAlpha(0.35),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ── Agenda del día ───────────────────────────────────────────────────────

class _TasksPanel extends ConsumerWidget {
  final Color accent;

  const _TasksPanel({super.key, required this.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayTasks = tasks.where((t) => t.dueDate == today).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    final pending = todayTasks.where((t) => !t.completed).length;
    final focusedId =
        ref.watch(pomodoroProvider.select((s) => s.focusedTaskId));

    return NeuCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'AGENDA DE HOY',
                  style: GoogleFonts.montserrat(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: BentoTheme.creamAlpha(0.4),
                  ),
                ),
              ),
              Text(
                '$pending pendientes',
                style: GoogleFonts.montserrat(
                  fontSize: 9.5,
                  color: BentoTheme.creamAlpha(0.32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: todayTasks.isEmpty
                ? Center(
                    child: Text(
                      'Nada en la agenda de hoy.\nDisfruta el descanso.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        height: 1.5,
                        color: BentoTheme.creamAlpha(0.4),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 4),
                    itemCount: todayTasks.length,
                    separatorBuilder: (_, _) => Divider(
                      color: BentoTheme.creamAlpha(0.07),
                      height: 1,
                    ),
                    itemBuilder: (context, i) => _TaskRow(
                      task: todayTasks[i],
                      accent: accent,
                      isFocused: todayTasks[i].id == focusedId,
                      onToggle: () => ref
                          .read(tasksProvider.notifier)
                          .toggleComplete(todayTasks[i].id),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final Task task;
  final Color accent;
  final bool isFocused;
  final VoidCallback onToggle;

  const _TaskRow({
    required this.task,
    required this.accent,
    required this.isFocused,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                border: Border.all(color: BentoTheme.creamAlpha(0.22), width: 1.5),
                borderRadius: BorderRadius.circular(6),
                color: task.completed ? accent : Colors.transparent,
              ),
              child: task.completed
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontSize: 13.5,
                  fontWeight: isFocused ? FontWeight.w600 : FontWeight.w400,
                  color: task.completed
                      ? BentoTheme.creamAlpha(0.32)
                      : BentoTheme.creamAlpha(0.85),
                  decoration: task.completed ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (isFocused) ...[
              const SizedBox(width: 6),
              Icon(Icons.center_focus_strong_rounded,
                  size: 14, color: PomodoroPalette.focus),
            ],
            if (task.isMit) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: BentoTheme.accentOrange, width: 0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'MIT',
                  style: GoogleFonts.montserrat(
                    fontSize: 7,
                    fontWeight: FontWeight.bold,
                    color: BentoTheme.accentOrange,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
