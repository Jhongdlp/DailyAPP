import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/habit_model.dart';
import '../../core/network/local_ai_client.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/utils/error_snackbar.dart';
import '../../core/widgets/streak_flame.dart';
import 'habit_form_dialog.dart';
import 'widgets/habit_heatmap.dart';

class HabitDetailScreen extends ConsumerStatefulWidget {
  final String habitId;
  const HabitDetailScreen({super.key, required this.habitId});

  @override
  ConsumerState<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends ConsumerState<HabitDetailScreen> {
  bool _analyzing = false;
  String? _aiFeedback;

  Future<void> _confirmDelete(Habit habit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BentoTheme.darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: BentoTheme.errorRed.withValues(alpha: 0.6), width: 1.5),
        ),
        title: Text('¿Eliminar hábito?', style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w700)),
        content: Text(
          'Se eliminará "${habit.name}" y todo su historial. Esta acción no se puede deshacer.',
          style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.6), fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: BentoTheme.errorRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(habitsProvider.notifier).deleteHabit(habit.id);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _analyzeWithAI(Habit habit) async {
    setState(() {
      _analyzing = true;
      _aiFeedback = null;
    });

    final settings = ref.read(settingsProvider);
    final buffer = StringBuffer();
    buffer.writeln('Hábito: "${habit.name}" (categoría: ${habit.category.label}).');
    buffer.writeln('Racha actual: ${habit.currentStreak()} días.');
    buffer.writeln('Mejor racha histórica: ${habit.bestStreak()} días.');
    buffer.writeln('Cumplimiento últimos 30 días: ${(habit.completionRate(days: 30) * 100).round()}%.');
    buffer.writeln('Cumplimiento últimos 7 días: ${(habit.completionRate(days: 7) * 100).round()}%.');
    buffer.writeln('Total de días completados registrados: ${habit.completedDates.length}.');
    buffer.writeln('\nAnaliza mi tendencia (mejorando, estancada o empeorando) y dame un consejo específico y motivador como coach de vida para sostener o mejorar este hábito.');

    try {
      final client = LocalAIClient(baseUrl: settings.localAiUrl, textModelName: settings.textModel);
      final response = await client.askText(
        buffer.toString(),
        systemPrompt: 'Eres un coach de productividad amigable y analítico. Responde en español de forma directa, breve, estructurada y en un tono motivador.',
      );
      if (mounted) setState(() => _aiFeedback = response);
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, message: 'Error al conectar con la IA Local: $e');
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BentoTheme.creamAlpha(0.08),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: BentoTheme.creamAlpha(0.14)),
        ),
        child: Icon(Icons.arrow_back, size: 18, color: BentoTheme.cream),
      ),
    );
  }

  Widget _buildMenuButton(Habit habit) {
    return PopupMenuButton<String>(
      color: BentoTheme.darkCardAlt,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: BentoTheme.creamAlpha(0.1))),
      icon: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BentoTheme.creamAlpha(0.08),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: BentoTheme.creamAlpha(0.14)),
        ),
        child: Icon(Icons.more_vert, size: 18, color: BentoTheme.cream),
      ),
      onSelected: (value) async {
        if (value == 'edit') {
          await showHabitFormDialog(context, ref, existing: habit);
        } else if (value == 'archive') {
          await ref.read(habitsProvider.notifier).archiveHabit(habit.id);
          if (context.mounted) Navigator.pop(context);
        } else if (value == 'delete') {
          await _confirmDelete(habit);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'edit', child: Text('Editar', style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600))),
        PopupMenuItem(value: 'archive', child: Text('Archivar', style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600))),
        PopupMenuItem(value: 'delete', child: Text('Eliminar', style: GoogleFonts.montserrat(color: BentoTheme.errorRed, fontWeight: FontWeight.w600))),
      ],
    );
  }

  Widget _buildProgressCard(BuildContext context, Habit habit, Color color) {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final progress = habit.dailyProgress[today] ?? 0.0;
    final goal = habit.goalValue!;
    final ratio = (progress / goal).clamp(0.0, 1.0);

    final fmtProgress = progress % 1 == 0 ? progress.toInt().toString() : progress.toStringAsFixed(2);
    final fmtGoal = goal % 1 == 0 ? goal.toInt().toString() : goal.toString();
    final unit = habit.goalUnit ?? '';

    double increment = 1.0;
    final unitLower = unit.toLowerCase();
    if (unitLower == 'l') {
      increment = 0.25;
    } else if (unitLower == 'ml') {
      increment = 250.0;
    } else if (unitLower == 'pasos' || unitLower == 'steps') {
      increment = 1000.0;
    } else if (unitLower == 'min' || unitLower == 'minutos') {
      increment = 5.0;
    }

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      borderRadius: 20,
      backgroundColor: BentoTheme.darkCard.withValues(alpha: 0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Progreso de hoy',
            style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 14, color: BentoTheme.cream),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        fmtProgress,
                        style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 32, height: 0.8, color: BentoTheme.cream),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '/ $fmtGoal $unit',
                        style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 16, color: BentoTheme.creamAlpha(0.4)),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => ref.read(habitsProvider.notifier).updateHabitProgress(habit.id, today, -increment),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: BentoTheme.creamAlpha(0.18))),
                      child: Icon(Icons.remove, size: 14, color: BentoTheme.cream),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => ref.read(habitsProvider.notifier).updateHabitProgress(habit.id, today, increment),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: BentoTheme.accentHabits),
                      child: const Icon(Icons.add, size: 14, color: Color(0xFF0C0C0D)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: ratio,
              backgroundColor: BentoTheme.creamAlpha(0.09),
              color: color,
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final habits = ref.watch(habitsProvider);
    final matches = habits.where((h) => h.id == widget.habitId);
    final habit = matches.isEmpty ? null : matches.first;

    if (habit == null) {
      return Scaffold(
        backgroundColor: BentoTheme.darkBg,
        body: SafeArea(
          child: Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Volver', style: GoogleFonts.montserrat(color: BentoTheme.cream)),
            ),
          ),
        ),
      );
    }

    final color = habit.colorValue;

    return Scaffold(
      backgroundColor: BentoTheme.darkBg,
      body: Container(
        constraints: const BoxConstraints.expand(),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [BentoTheme.darkBgTop, BentoTheme.darkBg],
            stops: const [0.0, 0.6],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _buildBackButton(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${habit.icon}  ${habit.name}',
                        style: GoogleFonts.montserrat(fontSize: 19, fontWeight: FontWeight.w800, color: BentoTheme.cream),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildMenuButton(habit),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _StatCard(
                      label: 'Racha actual',
                      value: '',
                      color: StreakFlame.getColorForStreak(habit.currentStreak()),
                      valueWidget: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${habit.currentStreak()}',
                            style: GoogleFonts.montserrat(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: StreakFlame.getColorForStreak(habit.currentStreak()),
                            ),
                          ),
                          const SizedBox(width: 5),
                          StreakFlame(streak: habit.currentStreak(), size: 18),
                        ],
                      ),
                    ),
                    _StatCard(label: 'Mejor racha', value: '${habit.bestStreak()} 🏆', color: BentoTheme.accentPurple),
                    _StatCard(label: 'Cumplimiento 30d', value: '${(habit.completionRate(days: 30) * 100).round()}%', color: BentoTheme.successGreen),
                    _StatCard(label: 'Total completados', value: '${habit.completedDates.length}', color: color),
                  ],
                ),
                if (habit.goalValue != null) ...[
                  const SizedBox(height: 16),
                  _buildProgressCard(context, habit, color),
                ],
                const SizedBox(height: 16),
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  borderRadius: 20,
                  backgroundColor: BentoTheme.darkCard.withValues(alpha: 0.55),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Historial anual', style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, color: BentoTheme.cream)),
                      const SizedBox(height: 4),
                      Text(
                        'Se llena automáticamente con tus hábitos completados',
                        style: GoogleFonts.montserrat(fontSize: 11, color: BentoTheme.creamAlpha(0.45)),
                      ),
                      const SizedBox(height: 8),
                      HabitHeatmap(habit: habit),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _analyzing ? null : () => _analyzeWithAI(habit),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: BentoTheme.accentHabits.withValues(alpha: 0.5)),
                    ),
                    child: _analyzing
                        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: BentoTheme.accentHabits))
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.psychology_outlined, size: 18, color: BentoTheme.accentHabits),
                              const SizedBox(width: 8),
                              Text(
                                'Analizar con IA',
                                style: GoogleFonts.montserrat(color: BentoTheme.accentHabits, fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                            ],
                          ),
                  ),
                ),
                if (_aiFeedback != null) ...[
                  const SizedBox(height: 16),
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    borderRadius: 18,
                    backgroundColor: BentoTheme.darkCard.withValues(alpha: 0.55),
                    borderColor: BentoTheme.accentHabits.withValues(alpha: 0.35),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.psychology, color: BentoTheme.accentHabits, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Coach de IA',
                                  style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 14, color: BentoTheme.accentHabits),
                                ),
                              ],
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _aiFeedback = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: BentoTheme.creamAlpha(0.06),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.close, color: BentoTheme.creamAlpha(0.6), size: 14),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _aiFeedback!,
                          style: GoogleFonts.montserrat(fontSize: 13, color: BentoTheme.creamAlpha(0.85), fontWeight: FontWeight.w500, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Widget? valueWidget;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    this.valueWidget,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      backgroundColor: BentoTheme.darkCardAlt.withValues(alpha: 0.60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          valueWidget ?? Text(value, style: GoogleFonts.montserrat(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: GoogleFonts.montserrat(fontSize: 11, color: BentoTheme.creamAlpha(0.45), fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
