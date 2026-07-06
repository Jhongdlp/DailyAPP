import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/habit_model.dart';
import '../../core/network/local_ai_client.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/utils/error_snackbar.dart';
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
        backgroundColor: BentoTheme.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: BentoTheme.errorRed, width: 2),
        ),
        title: const Text('¿Eliminar hábito?', style: TextStyle(color: BentoTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Se eliminará "${habit.name}" y todo su historial. Esta acción no se puede deshacer.',
            style: const TextStyle(color: BentoTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: BentoTheme.textSecondary, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: BentoTheme.errorRed),
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

  Widget _buildProgressCard(BuildContext context, Habit habit, Color color) {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final progress = habit.dailyProgress[today] ?? 0.0;
    final goal = habit.goalValue!;
    final ratio = (progress / goal).clamp(0.0, 1.0);
    final percentage = (ratio * 100).round();

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

    return BentoCard(
      borderColor: color,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${habit.icon} Progreso de Hoy',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: BentoTheme.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$fmtProgress / $fmtGoal $unit ($percentage%)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: ratio >= 1.0 ? BentoTheme.successGreen : BentoTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () {
                      ref.read(habitsProvider.notifier).updateHabitProgress(habit.id, today, -increment);
                    },
                    icon: const Icon(Icons.remove_circle_outline, color: BentoTheme.textSecondary),
                  ),
                  IconButton(
                    onPressed: () {
                      ref.read(habitsProvider.notifier).updateHabitProgress(habit.id, today, increment);
                    },
                    icon: Icon(Icons.add_circle_outline, color: color),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              backgroundColor: BentoTheme.borderMuted,
              color: color,
              minHeight: 12,
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
      return BentoBackground(
        child: Center(
          child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
        ),
      );
    }

    final color = habit.colorValue;

    return BentoBackground(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: BentoTheme.primaryDark),
                ),
                Expanded(
                  child: Text(
                    '${habit.icon} ${habit.name}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: BentoTheme.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: BentoTheme.primaryDark),
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
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(value: 'archive', child: Text('Archivar')),
                    PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatCard(label: 'Racha actual', value: '${habit.currentStreak()} 🔥', color: BentoTheme.accentOrange),
                _StatCard(label: 'Mejor racha', value: '${habit.bestStreak()} 🏆', color: BentoTheme.accentPurple),
                _StatCard(label: 'Cumplimiento 30d', value: '${(habit.completionRate(days: 30) * 100).round()}%', color: BentoTheme.successGreen),
                _StatCard(label: 'Total completados', value: '${habit.completedDates.length}', color: color),
              ],
            ),
            if (habit.goalValue != null) ...[
              const SizedBox(height: 20),
              _buildProgressCard(context, habit, color),
            ],
            const SizedBox(height: 20),
            BentoCard(
              borderColor: color,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📅 Historial anual', style: TextStyle(fontWeight: FontWeight.w900, color: BentoTheme.textPrimary)),
                  const SizedBox(height: 4),
                  const Text(
                    'Se llena automáticamente con tus hábitos completados',
                    style: TextStyle(fontSize: 11, color: BentoTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  HabitHeatmap(habit: habit),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _analyzing ? null : () => _analyzeWithAI(habit),
                    icon: _analyzing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.psychology_outlined),
                    label: const Text('Analizar con IA'),
                  ),
                ),
              ],
            ),
            if (_aiFeedback != null) ...[
              const SizedBox(height: 16),
              BentoCard(
                borderColor: BentoTheme.accentBlue,
                padding: const EdgeInsets.all(16),
                child: Text(
                  _aiFeedback!,
                  style: const TextStyle(fontSize: 13, color: BentoTheme.textPrimary, fontWeight: FontWeight.w500, height: 1.4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      borderColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: BentoTheme.textSecondary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
