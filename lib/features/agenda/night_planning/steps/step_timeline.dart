import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/models/task_model.dart';
import '../../../../core/network/local_ai_client.dart';
import '../../../../core/providers/habits_provider.dart';
import '../../../../core/providers/settings_provider.dart';
import '../../../../core/services/agenda_ai_service.dart';
import '../../../../core/providers/tasks_provider.dart';
import '../../../../core/theme/bento_theme.dart';
import '../../quick_parse.dart';
import '../../task_form_dialog.dart';
import '../../timeline_scale.dart';
import '../../widgets/day_timeline.dart';
import '../../widgets/quick_add_bar.dart';
import '../night_planning_screen.dart';

const _wakingStartHour = 7;
const _wakingEndHour = 23;
const _overbookedRatio = 0.7;

/// Paso 4 — rellenar el resto del día.
///
/// Reutiliza el mismo timeline de la Agenda, con sus gestos: mantener y
/// arrastrar crea un bloque, y la barra de arriba acepta una línea escrita a
/// mano. Es el paso donde se pasa más rato, así que no puede tener menos
/// herramientas que la pantalla normal.
class StepTimeline extends ConsumerStatefulWidget {
  final DateTime planDay;
  final VoidCallback onNext;

  const StepTimeline({super.key, required this.planDay, required this.onNext});

  @override
  ConsumerState<StepTimeline> createState() => _StepTimelineState();
}

class _StepTimelineState extends ConsumerState<StepTimeline> {
  /// Propuestas aún sin aceptar. Viven solo en memoria: nada llega a la agenda
  /// hasta que se acepta explícitamente.
  List<SuggestedBlock> _suggestions = const [];
  bool _askingAi = false;
  String? _aiMessage;

  List<Task> get _dayTasks => ref.read(tasksProvider.notifier).tasksForDay(widget.planDay);

  Future<void> _askAi() async {
    if (_askingAi) return;
    setState(() {
      _askingAi = true;
      _aiMessage = null;
    });

    final settings = ref.read(settingsProvider);
    final service = AgendaAIService(
      LocalAIClient(baseUrl: settings.localAiUrl, textModelName: settings.textModel),
    );
    final tasks = _dayTasks;

    final result = await service.suggestPlan(
      day: widget.planDay,
      habits: ref.read(habitsProvider),
      alreadyPlanned: tasks,
      mits: tasks.where((t) => t.isMit).map((t) => t.title).toList(),
    );

    if (!mounted) return;
    setState(() {
      _askingAi = false;
      _suggestions = result;
      // El fallo nunca bloquea: se avisa y se sigue planeando a mano.
      _aiMessage = result.isEmpty ? 'No pude sugerir nada ahora. Sigue a mano.' : null;
    });
  }

  Future<void> _accept(SuggestedBlock block) async {
    setState(() => _suggestions = _suggestions.where((b) => b != block).toList());
    final start = widget.planDay.add(Duration(minutes: block.startMinutes));
    await ref.read(tasksProvider.notifier).addTask(
          title: block.title,
          dueDate: widget.planDay,
          startAt: start,
          endAt: widget.planDay.add(Duration(minutes: block.endMinutes)),
          remindAt: start,
          blockType: block.blockType,
          plannedAt: DateTime.now(),
        );
  }

  Future<void> _acceptAll() async {
    final all = _suggestions;
    setState(() => _suggestions = const []);
    for (final block in all) {
      final start = widget.planDay.add(Duration(minutes: block.startMinutes));
      await ref.read(tasksProvider.notifier).addTask(
            title: block.title,
            dueDate: widget.planDay,
            startAt: start,
            endAt: widget.planDay.add(Duration(minutes: block.endMinutes)),
            remindAt: start,
            blockType: block.blockType,
            plannedAt: DateTime.now(),
          );
    }
  }

  int _suggestedStartMinutes(List<Task> tasks) {
    if (tasks.isNotEmpty) {
      final lastEnd = tasks.map(endMinutesOf).reduce((a, b) => a > b ? a : b);
      if (lastEnd < TimelineScale.minutesPerDay - 15) return TimelineScale.snap(lastEnd);
    }
    return _wakingStartHour * 60 + 60;
  }

  Future<void> _create(String title, DateTime start, DateTime end) {
    return ref.read(tasksProvider.notifier).addTask(
          title: title,
          dueDate: widget.planDay,
          startAt: start,
          endAt: end,
          remindAt: start,
          plannedAt: DateTime.now(),
        );
  }

  Future<void> _createFromQuickAdd(ParsedBlock parsed) {
    final startMinutes = parsed.startMinutes ?? _suggestedStartMinutes(_dayTasks);
    final start = widget.planDay.add(Duration(minutes: startMinutes));
    return ref.read(tasksProvider.notifier).addTask(
          title: parsed.title,
          // El desplazamiento de día que traiga la línea se ignora aquí a
          // propósito: este paso es para el día que se está planeando.
          dueDate: widget.planDay,
          startAt: start,
          endAt: start.add(Duration(minutes: parsed.durationMinutes ?? 30)),
          remindAt: start,
          priority: parsed.priority,
          blockType: parsed.blockType ?? BlockType.task,
          location: parsed.location,
          plannedAt: DateTime.now(),
        );
  }

  Future<void> _reschedule(Task task, DateTime start, DateTime end) {
    return ref.read(tasksProvider.notifier).updateTask(task.copyWith(
          startAt: start,
          endAt: end,
          remindAt: task.hasReminder ? start : null,
          clearReminder: !task.hasReminder,
        ));
  }

  bool _isCompleted(Task task) {
    final habitId = task.habitId;
    if (habitId == null) return task.completed;
    final habits = ref.read(habitsProvider);
    final index = habits.indexWhere((h) => h.id == habitId);
    if (index == -1) return task.completed;
    return habits[index].isCompletedOn(task.dueDate);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(tasksProvider);
    ref.watch(habitsProvider);
    final tasks = _dayTasks;

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: NightStepHeading(
            title: 'Rellena tu día',
            subtitle: 'Mantén y arrastra sobre una hora para crear un bloque, o escríbelo abajo.',
          ),
        ),
        const SizedBox(height: 14),
        _buildAiRow(),
        _buildLoadBar(tasks),
        QuickAddBar(
          fallbackStartMinutes: _suggestedStartMinutes(tasks),
          onSubmit: _createFromQuickAdd,
        ),
        Expanded(
          child: DayTimeline(
            day: widget.planDay,
            tasks: tasks,
            isCompleted: _isCompleted,
            onCreate: _create,
            onReschedule: _reschedule,
            onTapBlock: (task) =>
                showTaskFormDialog(context, ref, day: widget.planDay, existing: task),
            onToggleBlock: (task) {
              final habitId = task.habitId;
              if (habitId == null) {
                ref.read(tasksProvider.notifier).toggleComplete(task.id);
              } else {
                ref.read(habitsProvider.notifier).toggleHabit(habitId, task.dueDate);
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: NightStepButton(label: 'Siguiente', onTap: widget.onNext),
        ),
      ],
    );
  }

  /// Botón de sugerencia y, si hay propuestas, la lista de bloques fantasma.
  ///
  /// Se aceptan uno a uno o de golpe, y se descartan sin más. La IA propone;
  /// el día sigue siendo decisión de quien lo vive.
  Widget _buildAiRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _askAi,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    color: BentoTheme.accentPurple.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: BentoTheme.accentPurple.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_askingAi)
                        SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: BentoTheme.accentPurple),
                        )
                      else
                        Icon(Icons.auto_awesome, size: 14, color: BentoTheme.accentPurple),
                      const SizedBox(width: 6),
                      Text(
                        _askingAi ? 'Pensando…' : 'Sugerir plan',
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: BentoTheme.accentPurple,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _acceptAll,
                  child: Text(
                    'aceptar todo',
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: BentoTheme.accentLime,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => setState(() => _suggestions = const []),
                  child: Text(
                    'descartar',
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: BentoTheme.creamAlpha(0.45),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_aiMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _aiMessage!,
                style: GoogleFonts.montserrat(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: BentoTheme.creamAlpha(0.45),
                ),
              ),
            ),
          if (_suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final block in _suggestions)
                    GestureDetector(
                      onTap: () => _accept(block),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                        decoration: BoxDecoration(
                          color: BentoTheme.creamAlpha(0.05),
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: BentoTheme.accentPurple.withValues(alpha: 0.35),
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _fmtMinutes(block.startMinutes),
                              style: GoogleFonts.montserrat(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: BentoTheme.accentPurple,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              block.title,
                              style: GoogleFonts.montserrat(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: BentoTheme.creamAlpha(0.8),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Icon(Icons.add, size: 14, color: BentoTheme.accentLime),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _fmtMinutes(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// El mismo contador que la Agenda: está para frenar, no para animar a
  /// llenar el día. Sobreplanificar es lo que hace abandonar el sistema.
  Widget _buildLoadBar(List<Task> tasks) {
    final planned = tasks.fold<int>(0, (sum, t) => sum + (t.durationMinutes ?? 40));
    final available = (_wakingEndHour - _wakingStartHour) * 60;
    final ratio = (planned / available).clamp(0.0, 1.0);
    final overbooked = ratio > _overbookedRatio;

    String fmtHours(int minutes) {
      final h = minutes / 60;
      return h % 1 == 0 ? '${h.toInt()}h' : '${h.toStringAsFixed(1)}h';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '${fmtHours(planned)} planeadas  ·  ${fmtHours((available - planned).clamp(0, available))} libres',
                style: GoogleFonts.montserrat(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: BentoTheme.creamAlpha(0.55),
                ),
              ),
              const Spacer(),
              if (overbooked)
                Text(
                  'deja aire',
                  style: GoogleFonts.montserrat(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: BentoTheme.accentOrange,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              backgroundColor: BentoTheme.creamAlpha(0.08),
              valueColor: AlwaysStoppedAnimation(
                overbooked ? BentoTheme.accentOrange : BentoTheme.accentLime,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
