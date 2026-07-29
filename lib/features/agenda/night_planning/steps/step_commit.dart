import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/models/task_model.dart';
import '../../../../core/providers/day_plan_provider.dart';
import '../../../../core/providers/rpg_provider.dart';
import '../../../../core/providers/tasks_provider.dart';
import '../../../../core/theme/bento_theme.dart';
import '../night_planning_screen.dart';

/// Paso 5 — el compromiso.
///
/// El plan se devuelve redactado como frases de "a las HH:MM voy a X".
/// Formularlo así, y no como una lista, es lo que convierte una lista de
/// tareas en una intención de implementación: la forma "cuándo y dónde haré
/// qué" es la que de verdad mueve la aguja del cumplimiento.
///
/// Y cierra: al pulsar el botón el ritual termina y ya no hay nada que pensar
/// hasta mañana. Ese cierre es la mitad del valor de planear de noche.
class StepCommit extends ConsumerStatefulWidget {
  final DateTime planDay;
  final ValueChanged<String?> onIntentionChanged;
  final Future<void> Function() onFinish;

  const StepCommit({
    super.key,
    required this.planDay,
    required this.onIntentionChanged,
    required this.onFinish,
  });

  @override
  ConsumerState<StepCommit> createState() => _StepCommitState();
}

class _StepCommitState extends ConsumerState<StepCommit> {
  final _intentionController = TextEditingController();
  bool _finishing = false;

  /// XP por completar el ritual. Lo que premiamos es el acto de planear, no
  /// cuánto se planeó: si premiáramos el volumen, el incentivo sería llenar
  /// el día, que es justo lo que no queremos.
  static const _ritualXp = 40;
  static const _ritualGold = 15;

  @override
  void dispose() {
    _intentionController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);

    final text = _intentionController.text.trim();
    widget.onIntentionChanged(text.isEmpty ? null : text);

    ref.read(rpgProvider.notifier).gainXpAndGold(_ritualXp, _ritualGold);
    await widget.onFinish();

    if (mounted) setState(() => _finishing = false);
  }

  String _fmt(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Cada bloque como una frase en primera persona.
  String _sentenceFor(Task task) {
    final buffer = StringBuffer('A las ${_fmt(task.startAt)} voy a ${task.title.toLowerCase()}');
    if (task.location != null && task.location!.isNotEmpty) {
      buffer.write(' en ${task.location}');
    }
    return '$buffer.';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(tasksProvider);
    ref.watch(dayPlansProvider);

    final tasks = ref.read(tasksProvider.notifier).tasksForDay(widget.planDay);
    final habits = tasks.where((t) => t.isHabitBlock).length;
    final mits = tasks.where((t) => t.isMit).toList();
    final plannedMinutes = tasks.fold<int>(0, (sum, t) => sum + (t.durationMinutes ?? 40));
    final first = tasks.isEmpty ? null : tasks.first;
    final streak = ref.read(dayPlansProvider.notifier).planningStreak;

    String fmtHours(int minutes) {
      final h = minutes / 60;
      return h % 1 == 0 ? '${h.toInt()}h' : '${h.toStringAsFixed(1)}h';
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const NightStepHeading(
                  title: 'Mañana ya está decidido',
                  subtitle: 'Esto es lo que acabas de dejar listo. Ya no tienes que darle vueltas.',
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: BentoTheme.accentLime.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: BentoTheme.accentLime.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _stat('${tasks.length}', 'bloques'),
                          _stat(fmtHours(plannedMinutes), 'planeadas'),
                          _stat('$habits', habits == 1 ? 'hábito' : 'hábitos'),
                        ],
                      ),
                      if (first != null) ...[
                        const SizedBox(height: 14),
                        Container(height: 1, color: BentoTheme.accentLime.withValues(alpha: 0.2)),
                        const SizedBox(height: 12),
                        Text(
                          'Empiezas a las ${_fmt(first.startAt)} con ${first.title}',
                          style: GoogleFonts.montserrat(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: BentoTheme.cream,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (mits.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'TUS 3 GRANDES',
                    style: GoogleFonts.montserrat(
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                      color: BentoTheme.creamAlpha(0.5),
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final task in mits)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(Icons.star_rounded,
                                size: 15, color: BentoTheme.accentOrange),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _sentenceFor(task),
                              style: GoogleFonts.montserrat(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                                color: BentoTheme.creamAlpha(0.85),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                Text(
                  '¿CÓMO QUIERES SENTIRTE MAÑANA?',
                  style: GoogleFonts.montserrat(
                    fontSize: 11,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                    color: BentoTheme.creamAlpha(0.5),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _intentionController,
                  maxLines: 2,
                  style: GoogleFonts.montserrat(
                    color: BentoTheme.cream,
                    fontWeight: FontWeight.w500,
                    fontSize: 13.5,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Tranquilo y con el informe fuera (opcional)',
                    hintStyle: GoogleFonts.montserrat(
                      color: BentoTheme.creamAlpha(0.3),
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
                if (streak > 0) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Icon(Icons.nights_stay_outlined, size: 16, color: BentoTheme.accentPurple),
                      const SizedBox(width: 7),
                      Text(
                        streak == 1
                            ? 'Primera noche planeando.'
                            : '$streak noches seguidas planeando.',
                        style: GoogleFonts.montserrat(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: BentoTheme.accentPurple,
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
            label: _finishing ? 'Guardando…' : 'Listo, a dormir',
            onTap: _finish,
          ),
        ),
      ],
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.montserrat(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.0,
              color: BentoTheme.cream,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: BentoTheme.creamAlpha(0.5),
            ),
          ),
        ],
      ),
    );
  }
}
