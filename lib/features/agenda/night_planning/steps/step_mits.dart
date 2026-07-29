import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/models/task_model.dart';
import '../../../../core/providers/tasks_provider.dart';
import '../../../../core/theme/bento_theme.dart';
import '../night_planning_screen.dart';

/// Paso 2 — los tres grandes de mañana.
///
/// Exactamente tres, no una lista abierta. Un día tiene sitio para tres cosas
/// que importen de verdad; permitir diez garantiza que ninguna se termine y
/// que el sistema se abandone por sensación de fracaso. La restricción no es
/// una limitación de la app, es el mecanismo.
class StepMits extends ConsumerStatefulWidget {
  final DateTime today;
  final DateTime planDay;
  final VoidCallback onNext;

  const StepMits({
    super.key,
    required this.today,
    required this.planDay,
    required this.onNext,
  });

  @override
  ConsumerState<StepMits> createState() => _StepMitsState();
}

class _StepMitsState extends ConsumerState<StepMits> {
  final _controllers = List.generate(3, (_) => TextEditingController());
  bool _saving = false;

  /// Hora por defecto de cada uno de los tres. Se colocan temprano y
  /// escalonados: la voluntad no se recarga durante el día, así que lo que
  /// importa va cuando todavía queda.
  static const _slots = [9 * 60, 11 * 60, 15 * 60];

  @override
  void initState() {
    super.initState();
    // Precarga los MIT que ya estén marcados para mañana, para que volver
    // atrás en el ritual no borre lo escrito.
    final existing = ref
        .read(tasksProvider.notifier)
        .tasksForDay(widget.planDay)
        .where((t) => t.isMit)
        .toList();
    for (var i = 0; i < existing.length && i < 3; i++) {
      _controllers[i].text = existing[i].title;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// Lo de hoy que quedó sin hacer. Arrastrarlo a mañana con un toque evita
  /// el trabajo de volver a escribirlo, que es justo donde se pierde.
  List<Task> get _unfinishedToday => ref
      .read(tasksProvider.notifier)
      .tasksForDay(widget.today)
      .where((t) => !t.completed && !t.isHabitBlock)
      .toList();

  void _adopt(Task task) {
    final free = _controllers.indexWhere((c) => c.text.trim().isEmpty);
    if (free == -1) return;
    setState(() => _controllers[free].text = task.title);
  }

  Future<void> _next() async {
    if (_saving) return;
    setState(() => _saving = true);

    final notifier = ref.read(tasksProvider.notifier);
    final existingMits = notifier.tasksForDay(widget.planDay).where((t) => t.isMit).toList();
    final titles = _controllers.map((c) => c.text.trim()).toList();

    for (var i = 0; i < titles.length; i++) {
      final title = titles[i];
      final existing = i < existingMits.length ? existingMits[i] : null;

      if (title.isEmpty) {
        // Vaciar el campo quita la marca de "grande", pero no borra el bloque:
        // borrar algo que el usuario no pidió borrar sería una sorpresa fea.
        if (existing != null) {
          await notifier.updateTask(existing.copyWith(isMit: false));
        }
        continue;
      }

      if (existing != null) {
        if (existing.title != title) {
          await notifier.updateTask(existing.copyWith(title: title));
        }
      } else {
        final start = widget.planDay.add(Duration(minutes: _slots[i]));
        await notifier.addTask(
          title: title,
          dueDate: widget.planDay,
          startAt: start,
          endAt: start.add(const Duration(minutes: 60)),
          remindAt: start,
          priority: TaskPriority.high,
          isMit: true,
          plannedAt: DateTime.now(),
        );
      }
    }

    if (mounted) {
      setState(() => _saving = false);
      widget.onNext();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(tasksProvider);
    final pending = _unfinishedToday;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const NightStepHeading(
                  title: 'Tus 3 grandes',
                  subtitle: 'Si mañana solo salieran tres cosas, ¿cuáles querrías que fueran?',
                ),
                const SizedBox(height: 22),
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: BentoTheme.accentOrange.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${i + 1}',
                            style: GoogleFonts.montserrat(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: BentoTheme.accentOrange,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _controllers[i],
                            textInputAction:
                                i == 2 ? TextInputAction.done : TextInputAction.next,
                            style: GoogleFonts.montserrat(
                              color: BentoTheme.cream,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              hintText: i == 0 ? 'Lo más importante' : 'Opcional',
                              hintStyle: GoogleFonts.montserrat(
                                color: BentoTheme.creamAlpha(0.3),
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                              filled: true,
                              fillColor: BentoTheme.creamAlpha(0.06),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: BentoTheme.creamAlpha(0.12)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: BentoTheme.creamAlpha(0.12)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide:
                                    BorderSide(color: BentoTheme.accentOrange, width: 1.5),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Solo tres. Lo demás cabe en el día, pero no manda.',
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: BentoTheme.creamAlpha(0.4),
                  ),
                ),
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: 26),
                  Text(
                    'QUEDÓ DE HOY',
                    style: GoogleFonts.montserrat(
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                      color: BentoTheme.creamAlpha(0.5),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final task in pending)
                        GestureDetector(
                          onTap: () => _adopt(task),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: BentoTheme.creamAlpha(0.06),
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(color: BentoTheme.creamAlpha(0.14)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  task.title,
                                  style: GoogleFonts.montserrat(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: BentoTheme.creamAlpha(0.75),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Icon(Icons.arrow_upward,
                                    size: 13, color: BentoTheme.accentOrange),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: NightStepButton(
            label: _saving ? 'Guardando…' : 'Siguiente',
            onTap: _next,
          ),
        ),
      ],
    );
  }
}
