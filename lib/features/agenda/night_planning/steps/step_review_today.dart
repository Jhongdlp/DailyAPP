import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';
import '../../../../core/providers/tasks_provider.dart';
import '../../../../core/theme/bento_theme.dart';
import '../night_planning_screen.dart';

/// Paso 1 — cerrar el día que termina.
///
/// Va primero porque no se puede planear con la cabeza llena de lo de hoy.
/// Marcar lo hecho y ponerle una palabra al día lo deja atrás; sin ese cierre,
/// planear mañana se convierte en rumiar sobre hoy.
///
/// Nada de esto es obligatorio: se puede pasar de largo. Un ritual que exige
/// rellenar formularios se abandona a la tercera noche.
class StepReviewToday extends ConsumerStatefulWidget {
  final DateTime day;
  final void Function(int? mood, String? reflection) onNext;

  const StepReviewToday({super.key, required this.day, required this.onNext});

  @override
  ConsumerState<StepReviewToday> createState() => _StepReviewTodayState();
}

class _StepReviewTodayState extends ConsumerState<StepReviewToday> {
  final _reflectionController = TextEditingController();
  int? _mood;

  static const _moods = [
    (value: 1, emoji: '😞', label: 'duro'),
    (value: 2, emoji: '😕', label: 'flojo'),
    (value: 3, emoji: '😐', label: 'normal'),
    (value: 4, emoji: '🙂', label: 'bien'),
    (value: 5, emoji: '😄', label: 'genial'),
  ];

  @override
  void dispose() {
    _reflectionController.dispose();
    super.dispose();
  }

  void _next() {
    final text = _reflectionController.text.trim();
    widget.onNext(_mood, text.isEmpty ? null : text);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(tasksProvider);
    final tasks = ref.read(tasksProvider.notifier).tasksForDay(widget.day);
    final done = tasks.where((t) => t.completed).length;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const NightStepHeading(
                  title: 'Cierra el día',
                  subtitle: 'Marca lo que sí hiciste. Lo que no, no es una deuda: mañana es página nueva.',
                ),
                const SizedBox(height: 22),
                if (tasks.isEmpty)
                  Text(
                    'Hoy no planeaste nada. Empecemos por mañana.',
                    style: GoogleFonts.montserrat(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: BentoTheme.creamAlpha(0.45),
                    ),
                  )
                else ...[
                  Text(
                    '$done de ${tasks.length} completados',
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: BentoTheme.creamAlpha(0.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final task in tasks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () => ref.read(tasksProvider.notifier).toggleComplete(task.id),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            Icon(
                              task.completed ? Icons.check_circle : Icons.radio_button_unchecked,
                              size: 21,
                              color: task.completed
                                  ? BentoTheme.accentLime
                                  : BentoTheme.creamAlpha(0.3),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                task.title,
                                style: GoogleFonts.montserrat(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  decoration:
                                      task.completed ? TextDecoration.lineThrough : null,
                                  color: task.completed
                                      ? BentoTheme.creamAlpha(0.4)
                                      : BentoTheme.cream,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 26),
                Text(
                  '¿CÓMO TE FUE?',
                  style: GoogleFonts.montserrat(
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                    color: BentoTheme.creamAlpha(0.5),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final mood in _moods)
                      GestureDetector(
                        onTap: () => setState(
                          () => _mood = _mood == mood.value ? null : mood.value,
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _mood == mood.value
                                ? BentoTheme.accentLime.withValues(alpha: 0.16)
                                : BentoTheme.creamAlpha(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _mood == mood.value
                                  ? BentoTheme.accentLime
                                  : Colors.transparent,
                            ),
                          ),
                          child: Column(
                            children: [
                              Twemoji(emoji: mood.emoji, height: 22, width: 22),
                              const SizedBox(height: 3),
                              Text(
                                mood.label,
                                style: GoogleFonts.montserrat(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: BentoTheme.creamAlpha(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _reflectionController,
                  maxLines: 3,
                  style: GoogleFonts.montserrat(
                    color: BentoTheme.cream,
                    fontWeight: FontWeight.w500,
                    fontSize: 13.5,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Algo que quieras dejar escrito y soltar (opcional)',
                    hintStyle: GoogleFonts.montserrat(
                      color: BentoTheme.creamAlpha(0.32),
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                    filled: true,
                    fillColor: BentoTheme.creamAlpha(0.06),
                    contentPadding: const EdgeInsets.all(14),
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
                      borderSide: BorderSide(color: BentoTheme.accentLime, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: NightStepButton(label: 'Siguiente', onTap: _next),
        ),
      ],
    );
  }
}
