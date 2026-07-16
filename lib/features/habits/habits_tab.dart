import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/bento_theme.dart';
import '../../core/models/habit_model.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/network/local_ai_client.dart';
import '../../core/utils/error_snackbar.dart';
import 'habit_detail_screen.dart';
import 'habit_form_dialog.dart';
import 'habit_template_picker.dart';
import 'widgets/habit_blob_header.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

double _incrementFor(String? unit) {
  final unitLower = (unit ?? '').toLowerCase();
  if (unitLower == 'l') return 0.25;
  if (unitLower == 'ml') return 250.0;
  if (unitLower == 'pasos' || unitLower == 'steps') return 1000.0;
  if (unitLower == 'min' || unitLower == 'minutos') return 5.0;
  return 1.0;
}

class HabitsTab extends ConsumerStatefulWidget {
  const HabitsTab({super.key});

  @override
  ConsumerState<HabitsTab> createState() => _HabitsTabState();
}

class _HabitsTabState extends ConsumerState<HabitsTab> {
  bool _analyzing = false;
  String? _aiFeedback;

  List<DateTime> _getCurrentWeekDays() {
    final today = _dateOnly(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return List.generate(7, (index) => monday.add(Duration(days: index)));
  }

  String _getWeekdayLetter(DateTime day) {
    switch (day.weekday) {
      case 1:
        return 'L';
      case 2:
        return 'M';
      case 3:
        return 'M';
      case 4:
        return 'J';
      case 5:
        return 'V';
      case 6:
        return 'S';
      case 7:
        return 'D';
      default:
        return '';
    }
  }

  Future<void> _analyzeHabitsWithAI(List<Habit> habits) async {
    setState(() {
      _analyzing = true;
      _aiFeedback = null;
    });

    final settings = ref.read(settingsProvider);
    final buffer = StringBuffer();
    buffer.writeln('Mi panel de hábitos:');
    for (final h in habits) {
      buffer.writeln(
        '- "${h.name}" (${h.category.label}): racha actual ${h.currentStreak()} días, '
        'mejor racha ${h.bestStreak()} días, cumplimiento 30 días ${(h.completionRate(days: 30) * 100).round()}%.',
      );
    }
    buffer.writeln('\nAnaliza de forma concisa mis patrones generales. Dame un tip específico y motivador como coach de vida para mejorar.');

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

  @override
  Widget build(BuildContext context) {
    final habits = ref.watch(habitsProvider);
    final days = _getCurrentWeekDays();
    final today = _dateOnly(DateTime.now());

    final activeToday = habits.where((h) => h.isActiveOn(today)).toList();
    final completedToday = activeToday.where((h) => h.isCompletedOn(today)).length;
    final longestStreak = habits.isEmpty ? 0 : habits.map((h) => h.currentStreak()).reduce((a, b) => a > b ? a : b);

    final goalHabitsToday = activeToday.where((h) => h.goalValue != null).toList();
    final featured = goalHabitsToday.isNotEmpty ? goalHabitsToday.first : null;
    final compactHabits = activeToday.where((h) => h.id != featured?.id).toList();

    return Container(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          _buildStatsGrid(completedToday, activeToday.length, longestStreak),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 110),
              children: [
                _buildSectionHeader(context, activeToday.length, habits),
                if (_aiFeedback != null) _buildAiFeedbackCard(context),
                if (habits.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
                    child: Text(
                      'No tienes hábitos creados todavía.',
                      style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.5), fontWeight: FontWeight.w600),
                    ),
                  )
                else if (activeToday.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
                    child: Text(
                      'No tienes hábitos activos hoy.',
                      style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.5), fontWeight: FontWeight.w600),
                    ),
                  ),
                if (featured != null) _buildFeaturedCard(context, featured, today, days),
                if (compactHabits.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final habit in compactHabits) ...[
                          _buildCompactRow(context, habit, today, days),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: NeuCard(
        width: 34,
        height: 34,
        borderRadius: 10,
        distance: 3,
        blur: 6,
        padding: EdgeInsets.zero,
        onTap: onPressed,
        child: Center(
          child: Icon(icon, size: 17, color: onPressed == null ? BentoTheme.creamAlpha(0.3) : BentoTheme.cream),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SizedBox(
      height: 92,
      child: Stack(
        children: [
          Positioned.fill(child: HabitBlobHeader(accentColor: BentoTheme.accentHabits)),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                'Hábitos',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w800,
                  fontSize: 42,
                  height: 0.92,
                  letterSpacing: -1.4,
                  color: BentoTheme.cream,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(int completedToday, int activeCount, int longestStreak) {
    // Panel de stats GRABADO en la superficie (hundido): la información se
    // lee como tallada en el material; lo accionable, en cambio, va extruido.
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 10, 22, 0),
      child: NeuPressed(
        borderRadius: 18,
        distance: 3,
        blur: 7,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$completedToday',
                          style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 38, height: 0.8, letterSpacing: -0.7, color: BentoTheme.cream),
                        ),
                        Text(
                          '/$activeCount',
                          style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 20, color: BentoTheme.creamAlpha(0.4)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'COMPLETADOS HOY',
                    style: GoogleFonts.montserrat(fontSize: 10.5, letterSpacing: 2.2, color: BentoTheme.creamAlpha(0.45)),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 64, color: BentoTheme.creamAlpha(0.10)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 0, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '$longestStreak',
                          style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 38, height: 0.8, letterSpacing: -0.7, color: BentoTheme.cream),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'días',
                          style: GoogleFonts.montserrat(fontWeight: FontWeight.w500, fontSize: 16, color: BentoTheme.creamAlpha(0.55)),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.local_fire_department, size: 15, color: BentoTheme.creamAlpha(0.28)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'MEJOR RACHA ACTIVA',
                    style: GoogleFonts.montserrat(fontSize: 10.5, letterSpacing: 2.2, color: BentoTheme.creamAlpha(0.45)),
                  ),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, int activeCount, List<Habit> habits) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'HOY',
                style: GoogleFonts.montserrat(fontSize: 12, letterSpacing: 2.4, fontWeight: FontWeight.w600, color: BentoTheme.cream),
              ),
              const SizedBox(width: 10),
              Text(
                '${activeCount.toString().padLeft(2, '0')} hábitos',
                style: GoogleFonts.montserrat(fontSize: 11, letterSpacing: 1.1, color: BentoTheme.creamAlpha(0.4)),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeaderIconButton(
                icon: Icons.auto_awesome_outlined,
                tooltip: 'Elegir hábito prearmado',
                onPressed: () => showHabitTemplatePicker(context, ref),
              ),
              const SizedBox(width: 8),
              _analyzing
                  ? NeuCard(
                      width: 34,
                      height: 34,
                      borderRadius: 10,
                      distance: 3,
                      blur: 6,
                      padding: EdgeInsets.zero,
                      child: Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: BentoTheme.cream),
                        ),
                      ),
                    )
                  : _buildHeaderIconButton(
                      icon: Icons.insights_outlined,
                      tooltip: 'Analizar hábitos con IA',
                      onPressed: habits.isEmpty ? null : () => _analyzeHabitsWithAI(habits),
                    ),
              const SizedBox(width: 10),
              NeuCard(
                onTap: () => showHabitFormDialog(context, ref),
                borderRadius: 100,
                distance: 3,
                blur: 6,
                color: BentoTheme.accentHabits,
                padding: const EdgeInsets.fromLTRB(11, 7, 13, 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, size: 13, color: Color(0xFF0C0C0D)),
                    const SizedBox(width: 6),
                    Text(
                      'Nuevo',
                      style: GoogleFonts.montserrat(fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: const Color(0xFF0C0C0D)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAiFeedbackCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: 18,
        backgroundColor: BentoTheme.accentHabits.withValues(alpha: 0.07),
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
            MarkdownBody(
              data: _aiFeedback!,
              shrinkWrap: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(fontSize: 13, color: BentoTheme.creamAlpha(0.85), fontWeight: FontWeight.w500, height: 1.4),
                strong: TextStyle(fontSize: 13, color: BentoTheme.cream, fontWeight: FontWeight.w900, height: 1.4),
                em: TextStyle(fontSize: 13, color: BentoTheme.creamAlpha(0.85), fontStyle: FontStyle.italic, height: 1.4),
                listBullet: TextStyle(fontSize: 13, color: BentoTheme.creamAlpha(0.85), height: 1.4),
                h1: TextStyle(fontSize: 16, color: BentoTheme.accentHabits, fontWeight: FontWeight.w900),
                h2: TextStyle(fontSize: 15, color: BentoTheme.accentHabits, fontWeight: FontWeight.w900),
                h3: TextStyle(fontSize: 14, color: BentoTheme.accentHabits, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturedCard(BuildContext context, Habit habit, DateTime today, List<DateTime> days) {
    final progress = habit.dailyProgress[today] ?? 0.0;
    final goal = habit.goalValue!;
    final ratio = (progress / goal).clamp(0.0, 1.0);
    final unit = habit.goalUnit ?? '';
    final fmtProgress = progress % 1 == 0 ? progress.toInt().toString() : progress.toStringAsFixed(2);
    final fmtGoal = goal % 1 == 0 ? goal.toInt().toString() : goal.toString();
    final increment = _incrementFor(unit);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: GlassCard(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HabitDetailScreen(habitId: habit.id))),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        borderRadius: 22,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (habit.hasReminder)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Icon(Icons.access_time, size: 12, color: BentoTheme.creamAlpha(0.5)),
                    const SizedBox(width: 5),
                    Text(
                      '${habit.reminderHour?.toString().padLeft(2, '0') ?? '--'}:${habit.reminderMinute?.toString().padLeft(2, '0') ?? '--'}',
                      style: GoogleFonts.montserrat(fontSize: 11, color: BentoTheme.creamAlpha(0.5)),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                // El emoji vive en un pocito hundido: identidad del hábito
                // engastada en el material, no flotando encima.
                _sunkenIconWell(habit.icon, size: 42, iconSize: 20, borderRadius: 13),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    habit.name,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 24, letterSpacing: -0.5, color: BentoTheme.cream),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
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
                          style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 34, height: 0.8, letterSpacing: -0.7, color: BentoTheme.cream),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '/ $fmtGoal $unit',
                          style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 17, color: BentoTheme.creamAlpha(0.4)),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    _stepperButton(
                      icon: Icons.remove,
                      filled: false,
                      onTap: () => ref.read(habitsProvider.notifier).updateHabitProgress(habit.id, today, -increment),
                    ),
                    const SizedBox(width: 12),
                    _stepperButton(
                      icon: Icons.add,
                      filled: true,
                      onTap: () => ref.read(habitsProvider.notifier).updateHabitProgress(habit.id, today, increment),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            _neuProgressBar(ratio, BentoTheme.accentHabits),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: days.map((day) {
                final isToday = day == today;
                final isCompleted = habit.isCompletedOn(day);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => ref.read(habitsProvider.notifier).toggleHabit(habit.id, day),
                  child: Column(
                    children: [
                      Text(
                        _getWeekdayLetter(day),
                        style: GoogleFonts.montserrat(
                          fontSize: 10,
                          letterSpacing: 0.8,
                          fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                          color: isToday ? BentoTheme.accentHabits : BentoTheme.creamAlpha(0.4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _neuDayDot(
                        completed: isCompleted,
                        isToday: isToday,
                        accent: BentoTheme.accentHabits,
                        size: 26,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepperButton({required IconData icon, required bool filled, required VoidCallback onTap}) {
    // Botones físicos: el "+" es la acción primaria (pieza acentuada), el "−"
    // es la misma pieza en material neutro. Ambos con física de presión.
    return NeuCard(
      onTap: onTap,
      width: 36,
      height: 36,
      borderRadius: 18,
      distance: 3,
      blur: 6,
      padding: EdgeInsets.zero,
      color: filled ? BentoTheme.accentHabits : null,
      child: Center(
        child: Icon(icon, size: 15, color: filled ? const Color(0xFF0C0C0D) : BentoTheme.cream),
      ),
    );
  }

  /// Pocito hundido cuadrado para engastar el emoji/identidad de un hábito.
  Widget _sunkenIconWell(String emoji, {required double size, required double iconSize, required double borderRadius}) {
    return NeuPressed(
      borderRadius: borderRadius,
      distance: 2.5,
      blur: 5,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(child: Text(emoji, style: TextStyle(fontSize: iconSize))),
      ),
    );
  }

  /// Pista de progreso física: canal hundido en la superficie con relleno de
  /// acento cilíndrico (brillo arriba, sombra abajo). Las sombras interiores
  /// del canal se pintan POR ENCIMA del relleno, así que el líquido se lee
  /// dentro del hueco.
  Widget _neuProgressBar(double ratio, Color accent) {
    return NeuPressed(
      borderRadius: 100,
      distance: 2,
      blur: 4,
      child: SizedBox(
        height: 10,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: ratio.clamp(0.0, 1.0),
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(accent, Colors.white, 0.30)!,
                      accent,
                      Color.lerp(accent, Colors.black, 0.22)!,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Toggle de día: vacío = hueco circular en la superficie (con punto de
  /// acento si es hoy); completado = disco de acento extruido con volumen
  /// cilíndrico. Estado leído por el tacto: hundido pide acción, extruido
  /// celebra lo hecho.
  Widget _neuDayDot({
    required bool completed,
    required bool isToday,
    required Color accent,
    required double size,
  }) {
    if (completed) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(accent, Colors.white, 0.28)!,
              accent,
              Color.lerp(accent, Colors.black, 0.18)!,
            ],
          ),
          boxShadow: BentoTheme.neuRaised(distance: 2, blur: 4),
        ),
        child: Icon(Icons.check, size: size * 0.54, color: Colors.white),
      );
    }
    return NeuPressed(
      borderRadius: size / 2,
      distance: 2,
      blur: 3.5,
      child: SizedBox(
        width: size,
        height: size,
        child: isToday
            ? Center(
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildCompactRow(BuildContext context, Habit habit, DateTime today, List<DateTime> days) {
    final isCompleted = habit.isCompletedOn(today);
    final metaParts = <String>[
      if (habit.goalLabel != null) habit.goalLabel!,
      if (habit.hasReminder)
        '${habit.reminderHour?.toString().padLeft(2, '0') ?? '--'}:${habit.reminderMinute?.toString().padLeft(2, '0') ?? '--'}',
    ];

    return GlassCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HabitDetailScreen(habitId: habit.id))),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      borderRadius: 16,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _sunkenIconWell(habit.icon, size: 34, iconSize: 15, borderRadius: 10),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        habit.name,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 16, letterSpacing: -0.2, color: BentoTheme.cream),
                      ),
                      if (metaParts.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          metaParts.join(' · ').toUpperCase(),
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.montserrat(fontSize: 10.5, letterSpacing: 1.1, color: BentoTheme.creamAlpha(0.4)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => ref.read(habitsProvider.notifier).toggleHabit(habit.id, today),
                  child: _neuDayDot(
                    completed: isCompleted,
                    isToday: true,
                    accent: habit.colorValue,
                    size: 26,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: days.map((day) {
                  final isToday = day == today;
                  final isCompletedDay = habit.isCompletedOn(day);
                  final color = habit.colorValue;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => ref.read(habitsProvider.notifier).toggleHabit(habit.id, day),
                    child: Column(
                      children: [
                        Text(
                          _getWeekdayLetter(day),
                          style: GoogleFonts.montserrat(
                            fontSize: 9,
                            letterSpacing: 0.8,
                            fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                            color: isToday ? BentoTheme.accentHabits : BentoTheme.creamAlpha(0.4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _neuDayDot(
                          completed: isCompletedDay,
                          isToday: isToday,
                          accent: color,
                          size: 22,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );
  }
}
