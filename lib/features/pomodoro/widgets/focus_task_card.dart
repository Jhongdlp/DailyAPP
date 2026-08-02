import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';

import '../../../core/models/task_model.dart';
import '../../../core/providers/focus_stats_provider.dart';
import '../../../core/providers/tasks_provider.dart';
import '../../../core/theme/bento_theme.dart';
import '../pomodoro_palette.dart';
import '../providers/pomodoro_provider.dart';

List<Task> todayTasksSorted(List<Task> tasks) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return tasks.where((t) => t.dueDate == today).toList()
    ..sort((a, b) {
      // Lo que queda por hacer va antes, y dentro de eso lo importante primero:
      // elegir tarea debe costar un vistazo, no una búsqueda.
      if (a.completed != b.completed) return a.completed ? 1 : -1;
      if (a.isMit != b.isMit) return a.isMit ? -1 : 1;
      return a.startAt.compareTo(b.startAt);
    });
}

/// La única cosa a la que se está atendiendo en este bloque. Ocupa el centro
/// de la pantalla durante el enfoque porque responder "¿qué estoy haciendo?"
/// sin pensar es lo que evita la deriva.
class FocusTaskCard extends ConsumerWidget {
  final bool compact;

  const FocusTaskCard({super.key, this.compact = false});

  Future<void> _choose(
      BuildContext context, WidgetRef ref, String? currentId) async {
    final choice = await pickFocusTask(context, selectedId: currentId);
    if (choice == null) return; // hoja cerrada sin elegir: no se toca nada
    ref.read(pomodoroProvider.notifier).setFocusedTask(choice.id, choice.title);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focus = ref.watch(pomodoroProvider.select((s) => (
          id: s.focusedTaskId,
          title: s.focusedTaskTitle,
        )));

    if (focus.id == null && focus.title == null) {
      return NeuCard(
        padding: EdgeInsets.symmetric(
          horizontal: 18,
          vertical: compact ? 14 : 18,
        ),
        onTap: () => _choose(context, ref, focus.id),
        child: Row(
          children: [
            Icon(Icons.adjust_rounded,
                size: 20, color: BentoTheme.creamAlpha(0.35)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Elegir en qué te enfocas',
                style: GoogleFonts.outfit(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: BentoTheme.creamAlpha(0.5),
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: BentoTheme.creamAlpha(0.3)),
          ],
        ),
      );
    }

    final tasks = ref.watch(tasksProvider);
    final task = focus.id == null
        ? null
        : tasks.where((t) => t.id == focus.id).firstOrNull;
    final title = task?.title ?? focus.title ?? '';
    final done = task?.completed ?? false;
    final pomodoros =
        ref.watch(focusStatsProvider.select((s) => s.pomodorosOnTask(focus.id)));

    return NeuCard(
      padding: EdgeInsets.fromLTRB(18, compact ? 13 : 16, 12, compact ? 13 : 16),
      onTap: () => _choose(context, ref, focus.id),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: compact ? 32 : 38,
            decoration: BoxDecoration(
              color: PomodoroPalette.focus,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TRABAJANDO EN',
                  style: GoogleFonts.montserrat(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: BentoTheme.creamAlpha(0.38),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: compact ? 15 : 16.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: done
                        ? BentoTheme.creamAlpha(0.4)
                        : BentoTheme.creamAlpha(0.92),
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (pomodoros > 0) ...[
                  const SizedBox(height: 5),
                  TwemojiText(
                    text: '🍅 $pomodoros ${pomodoros == 1 ? "bloque" : "bloques"} en esta tarea',
                    style: GoogleFonts.montserrat(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: BentoTheme.creamAlpha(0.4),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (task != null)
            _RoundAction(
              icon: done ? Icons.replay_rounded : Icons.check_rounded,
              color: done ? BentoTheme.creamAlpha(0.5) : BentoTheme.successGreen,
              tooltip: done ? 'Marcar como pendiente' : 'Marcar como hecha',
              onTap: () {
                HapticFeedback.mediumImpact();
                ref.read(tasksProvider.notifier).toggleComplete(task.id);
              },
            ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: NeuCard(
        borderRadius: 18,
        distance: 3,
        blur: 6,
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

/// Tarea elegida para el bloque. Ambos campos a `null` significa "sin tarea
/// concreta", que no es lo mismo que cerrar la hoja sin elegir (eso devuelve
/// `null` entero y no cambia nada).
typedef FocusTaskChoice = ({String? id, String? title});

/// Selector de la tarea del bloque. Solo ofrece las de hoy: enfocarse en algo
/// que no está en la agenda del día suele ser la propia deriva.
///
/// Devuelve la elección en vez de escribirla, para que sirva igual dentro de
/// la sesión (aplica ya) que en la configuración previa (aplica al arrancar).
Future<FocusTaskChoice?> pickFocusTask(
  BuildContext context, {
  String? selectedId,
}) {
  return showModalBottomSheet<FocusTaskChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FocusTaskPickerSheet(selectedId: selectedId),
  );
}

class _FocusTaskPickerSheet extends ConsumerWidget {
  final String? selectedId;

  const _FocusTaskPickerSheet({this.selectedId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = todayTasksSorted(ref.watch(tasksProvider));
    final stats = ref.watch(focusStatsProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      decoration: BoxDecoration(
        color: BentoTheme.neuSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: BentoTheme.neuFloating(elevation: 24),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: BentoTheme.creamAlpha(0.18),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '¿En qué te enfocas?',
            style: GoogleFonts.montserrat(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: BentoTheme.cream,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: tasks.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No hay tareas en la agenda de hoy.\nPuedes enfocarte igualmente sin tarea.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 13.5,
                        height: 1.5,
                        color: BentoTheme.creamAlpha(0.45),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: tasks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final task = tasks[i];
                      final selected = task.id == selectedId;
                      final count = stats.pomodorosOnTask(task.id);

                      return NeuCard(
                        borderRadius: 16,
                        distance: selected ? 2 : 3,
                        blur: selected ? 4 : 6,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        borderColor: selected ? PomodoroPalette.focus : null,
                        color: selected
                            ? PomodoroPalette.focus.withValues(alpha: 0.1)
                            : null,
                        onTap: () => Navigator.pop<FocusTaskChoice>(
                          context,
                          (id: task.id, title: task.title),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontSize: 14.5,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: task.completed
                                      ? BentoTheme.creamAlpha(0.4)
                                      : BentoTheme.creamAlpha(0.9),
                                  decoration: task.completed
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            if (count > 0) ...[
                              const SizedBox(width: 8),
                              TwemojiText(
                                text: '🍅$count',
                                style: GoogleFonts.montserrat(
                                  fontSize: 11,
                                  color: BentoTheme.creamAlpha(0.45),
                                ),
                              ),
                            ],
                            if (task.isMit) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: BentoTheme.accentOrange,
                                      width: 0.8),
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
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => Navigator.pop<FocusTaskChoice>(
              context,
              (id: null, title: null),
            ),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Enfocarme sin tarea concreta',
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BentoTheme.creamAlpha(0.45),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
