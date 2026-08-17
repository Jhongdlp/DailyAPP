import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/bento_theme.dart';
import '../../core/models/habit_model.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/rpg_provider.dart';
import '../../core/providers/exercise_habit_link_provider.dart';
import '../exercise/exercise_capture_flow.dart';
import '../../core/models/achievement_catalog.dart';
import '../../core/widgets/rpg_celebration.dart';
import '../../core/network/local_ai_client.dart';
import '../../core/utils/error_snackbar.dart';
import '../../core/widgets/streak_flame.dart';
import '../../core/widgets/confetti_overlay.dart';
import 'habit_detail_screen.dart';
import 'habit_form_dialog.dart';
import 'habit_template_picker.dart';
import 'widgets/habit_blob_header.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

// ─── Escala de radios ───
//
// Antes convivían 10, 12, 16, 18, 20, 22, 24 y 100 en la misma pantalla, que es
// lo que hace que un conjunto de tarjetas se lea desordenado aunque cada pieza
// esté bien. Tres valores y las píldoras; nada más.
const double _rChip = 12.0;
const double _rCard = 20.0;
const double _rFeatured = 28.0;

// ─── Tipografía ───
//
// Una sola familia (Outfit, la del tema) y tres pesos. Fuera Montserrat, y
// fuera el micro-texto en mayúsculas con letterSpacing: ese recurso —
// 'COMPLETADO' a 7px con tracking— es lo que más fechaba la pantalla, y encima
// era ilegible. Todo en caja de frase.
TextStyle _t(
  double size, {
  FontWeight weight = FontWeight.w500,
  Color? color,
  double? letterSpacing,
  double? height,
}) =>
    GoogleFonts.outfit(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );

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

  static const List<String> _weekdayLetters = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  String _getWeekdayLetter(DateTime day) => _weekdayLetters[day.weekday - 1];

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

  /// Deshacer para el desmarcado accidental. Antes, tocar un día por error
  /// obligaba a volver a acertarle al mismo punto de 22px; ahora hay una salida
  /// explícita.
  void _showUndoBar(String message, VoidCallback onUndo) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: _t(14, color: BentoTheme.cream)),
        backgroundColor: BentoTheme.darkCardAlt,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rChip)),
        margin: const EdgeInsets.fromLTRB(22, 0, 22, 104),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Deshacer',
          textColor: BentoTheme.accentHabits,
          onPressed: onUndo,
        ),
      ),
    );
  }

  Future<void> _handleToggleHabit(Habit habit, DateTime day, [Offset? tapPosition]) async {
    final wasCompleted = habit.isCompletedOn(day);

    // La háptica va ANTES del await: el dedo todavía está en la pantalla y el
    // acuse tiene que llegar en el mismo gesto, no cuando vuelve la red.
    if (wasCompleted) {
      HapticFeedback.selectionClick();
    } else {
      HapticFeedback.mediumImpact();
    }

    if (!wasCompleted && mounted) {
      final spawnOffset = tapPosition ?? Offset(
        MediaQuery.of(context).size.width / 2,
        MediaQuery.of(context).size.height / 2,
      );
      triggerConfettiCelebration(context, spawnOffset);
    }

    await ref.read(habitsProvider.notifier).toggleHabit(habit.id, day);

    if (wasCompleted) {
      ref.read(rpgProvider.notifier).revertReward(
        15,
        5,
        counterKeys: const [RpgCounters.habitsDone],
      );
      if (mounted) {
        _showUndoBar(
          'Desmarcado "${habit.name}"',
          () => _handleToggleHabit(habit, day),
        );
      }
      return;
    }

    final result = ref.read(rpgProvider.notifier).gainXpAndGold(
      15,
      5,
      counterKeys: const [RpgCounters.habitsDone],
    );
    if (mounted) {
      RpgCelebration.show(
        context,
        xp: result['xpGained'] as int,
        gold: result['goldGained'] as int,
        levelUp: result['levelUp'] as bool,
        newLevel: result['newLevel'] as int?,
      );
      AchievementToast.show(context, result['unlocked']);
    }

    // Solo para el hábito vinculado a Ejercicio, y solo al completar (no al
    // desmarcar): ofrece guardar fotos + datos de la sesión de hoy sin que
    // el usuario tenga que ir a buscar la pestaña Ejercicio por su cuenta.
    final linkedExerciseHabitId = ref.read(exerciseHabitLinkProvider);
    if (linkedExerciseHabitId == habit.id && mounted) {
      final wantsToLog = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: BentoTheme.darkCard,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rCard)),
          title: Text(
            '¿Quieres guardar tu progreso de hoy?',
            style: _t(19, weight: FontWeight.w600, color: BentoTheme.cream, letterSpacing: -0.3),
          ),
          content: Text(
            'Toma hasta 5 fotos y registra los datos de tu ejercicio.',
            style: _t(15, color: BentoTheme.creamAlpha(0.6), height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('Ahora no', style: _t(15, weight: FontWeight.w600, color: BentoTheme.creamAlpha(0.6))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: BentoTheme.accentHabits,
                foregroundColor: const Color(0xFF0C0C0D),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rChip)),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('Guardar', style: _t(15, weight: FontWeight.w600, color: const Color(0xFF0C0C0D))),
            ),
          ],
        ),
      );
      if (wantsToLog == true && mounted) {
        await runExerciseCaptureFlow(context, ref, forDate: day, habitId: habit.id);
      }
    }
  }

  Future<void> _handleUpdateProgress(Habit habit, DateTime day, double increment) async {
    final wasCompleted = habit.isCompletedOn(day);
    HapticFeedback.selectionClick();
    await ref.read(habitsProvider.notifier).updateHabitProgress(habit.id, day, increment);

    final updatedHabits = ref.read(habitsProvider);
    final updatedHabit = updatedHabits.where((h) => h.id == habit.id).firstOrNull;
    if (updatedHabit == null) return;

    final isCompletedNow = updatedHabit.isCompletedOn(day);
    if (!wasCompleted && isCompletedNow) {
      HapticFeedback.mediumImpact();
      final result = ref.read(rpgProvider.notifier).gainXpAndGold(
        15,
        5,
        counterKeys: const [RpgCounters.habitsDone],
      );
      if (mounted) {
        RpgCelebration.show(
          context,
          xp: result['xpGained'] as int,
          gold: result['goldGained'] as int,
          levelUp: result['levelUp'] as bool,
          newLevel: result['newLevel'] as int?,
        );
        AchievementToast.show(context, result['unlocked']);
      }
    } else if (wasCompleted && !isCompletedNow) {
      ref.read(rpgProvider.notifier).revertReward(
        15,
        5,
        counterKeys: const [RpgCounters.habitsDone],
      );
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
          _buildHeader(context, longestStreak),
          _buildSummaryCard(context, completedToday, activeToday.length),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 110),
              // Pre-rasteriza filas fuera de pantalla antes de que entren en
              // vista: evita el hitch de blur/sombras al hacer scroll rápido.
              scrollCacheExtent: const ScrollCacheExtent.pixels(800),
              children: [
                _buildSectionHeader(context, activeToday.length, habits),
                if (_aiFeedback != null) _buildAiFeedbackCard(context),
                if (habits.isEmpty)
                  _emptyState('Todavía no tienes hábitos', 'Empieza por uno. Se construye de a poco.')
                else if (activeToday.isEmpty)
                  _emptyState('Hoy no toca ninguno', 'Ninguno de tus hábitos está programado para hoy.'),
                if (featured != null) _buildFeaturedCard(context, featured, today, days),
                // Cada fila es un hijo directo del ListView (mismo layout que
                // la Column anterior): así cada una recibe su propio
                // RepaintBoundary automático y un toggle o animación en una
                // fila no repinta las demás.
                for (int i = 0; i < compactHabits.length; i++)
                  Padding(
                    key: ValueKey(compactHabits[i].id),
                    padding: EdgeInsets.fromLTRB(22, i == 0 ? 14 : 0, 22, 12),
                    child: _buildCompactRow(context, compactHabits[i], today, days),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _t(19, weight: FontWeight.w600, color: BentoTheme.cream, letterSpacing: -0.3)),
          const SizedBox(height: 6),
          Text(subtitle, style: _t(15, color: BentoTheme.creamAlpha(0.45), height: 1.35)),
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
        width: 38,
        height: 38,
        borderRadius: _rChip,
        distance: 3,
        blur: 6,
        padding: EdgeInsets.zero,
        onTap: onPressed,
        child: Center(
          child: Icon(icon, size: 18, color: onPressed == null ? BentoTheme.creamAlpha(0.3) : BentoTheme.cream),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int longestStreak) {
    return SizedBox(
      height: 92,
      child: Stack(
        children: [
          Positioned.fill(child: HabitBlobHeader(accentColor: BentoTheme.accentHabits)),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Hábitos',
                  style: _t(
                    42,
                    weight: FontWeight.w600,
                    color: BentoTheme.cream,
                    letterSpacing: -1.2,
                    height: 0.95,
                  ),
                ),
                if (longestStreak > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: GlassCard(
                      borderRadius: _rChip,
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StreakFlame(streak: longestStreak, size: 18),
                          const SizedBox(width: 7),
                          Text(
                            '$longestStreak',
                            style: _t(
                              20,
                              weight: FontWeight.w600,
                              color: BentoTheme.isDark ? BentoTheme.neuText : Colors.black,
                              letterSpacing: -0.4,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            longestStreak == 1 ? 'día' : 'días',
                            style: _t(
                              13,
                              color: BentoTheme.isDark
                                  ? BentoTheme.creamAlpha(0.55)
                                  : Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
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

  /// Tarjeta de resumen del día. Reemplaza al panel que metía nivel, XP, HP y
  /// progreso en 50px de alto, todo al mismo tamaño y sin jerarquía.
  ///
  /// Ahora hay UN protagonista —cuántos llevas hoy, a 44px— y el RPG queda de
  /// acompañante a la derecha. El dato que más miras es el más grande.
  Widget _buildSummaryCard(BuildContext context, int completedToday, int activeCount) {
    final rpg = ref.watch(rpgProvider);
    final xpRatio = (rpg.xp / rpg.xpNeeded).clamp(0.0, 1.0);
    final dayRatio = activeCount == 0 ? 0.0 : (completedToday / activeCount).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 14),
      child: GlassCard(
        borderRadius: _rCard,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Protagonista: el conteo del día.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$completedToday',
                            style: _t(
                              44,
                              weight: FontWeight.w600,
                              color: BentoTheme.cream,
                              letterSpacing: -1.6,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '/ $activeCount',
                            style: _t(
                              20,
                              weight: FontWeight.w500,
                              color: BentoTheme.creamAlpha(0.35),
                              letterSpacing: -0.4,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        activeCount == 0 ? 'Sin hábitos hoy' : 'Completados hoy',
                        style: _t(14, color: BentoTheme.creamAlpha(0.5)),
                      ),
                    ],
                  ),
                ),
                // Acompañante: el estado del personaje, en voz baja.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shield_outlined, color: BentoTheme.accentPurple, size: 15),
                        const SizedBox(width: 5),
                        Text(
                          'Nivel ${rpg.level}',
                          style: _t(15, weight: FontWeight.w600, color: BentoTheme.cream, letterSpacing: -0.2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    SizedBox(
                      width: 96,
                      child: _neuProgressBar(xpRatio, BentoTheme.accentPurple, height: 7),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite, color: Color(0xFFFF4949), size: 12),
                        const SizedBox(width: 5),
                        Text(
                          '${rpg.hp}',
                          style: _t(13, weight: FontWeight.w600, color: BentoTheme.creamAlpha(0.7)),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${rpg.xp}/${rpg.xpNeeded} XP',
                          style: _t(13, color: BentoTheme.creamAlpha(0.4)),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _neuProgressBar(dayRatio, BentoTheme.accentHabits, height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, int activeCount, List<Habit> habits) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Hoy',
                style: _t(22, weight: FontWeight.w600, color: BentoTheme.cream, letterSpacing: -0.5),
              ),
              const SizedBox(width: 9),
              Text(
                activeCount == 1 ? '1 hábito' : '$activeCount hábitos',
                style: _t(15, color: BentoTheme.creamAlpha(0.4)),
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
                      width: 38,
                      height: 38,
                      borderRadius: _rChip,
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
                padding: const EdgeInsets.fromLTRB(13, 9, 15, 9),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, size: 16, color: Color(0xFF0C0C0D)),
                    const SizedBox(width: 5),
                    Text(
                      'Nuevo',
                      style: _t(14, weight: FontWeight.w600, color: const Color(0xFF0C0C0D), letterSpacing: -0.1),
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
        padding: const EdgeInsets.all(18),
        borderRadius: _rCard,
        backgroundColor: BentoTheme.accentHabits.withValues(alpha: 0.07),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.psychology, color: BentoTheme.accentHabits, size: 19),
                    const SizedBox(width: 8),
                    Text(
                      'Coach de IA',
                      style: _t(16, weight: FontWeight.w600, color: BentoTheme.accentHabits, letterSpacing: -0.2),
                    ),
                  ],
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _aiFeedback = null),
                  child: Padding(
                    // Zona táctil real: el icono es de 16px pero el objetivo
                    // no puede serlo.
                    padding: const EdgeInsets.all(8),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: BentoTheme.creamAlpha(0.06),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.close, color: BentoTheme.creamAlpha(0.6), size: 15),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            MarkdownBody(
              data: _aiFeedback!,
              shrinkWrap: true,
              styleSheet: MarkdownStyleSheet(
                p: _t(15, color: BentoTheme.creamAlpha(0.85), height: 1.45),
                strong: _t(15, weight: FontWeight.w600, color: BentoTheme.cream, height: 1.45),
                em: _t(15, color: BentoTheme.creamAlpha(0.85), height: 1.45).copyWith(fontStyle: FontStyle.italic),
                listBullet: _t(15, color: BentoTheme.creamAlpha(0.85), height: 1.45),
                h1: _t(18, weight: FontWeight.w600, color: BentoTheme.accentHabits, letterSpacing: -0.3),
                h2: _t(17, weight: FontWeight.w600, color: BentoTheme.accentHabits, letterSpacing: -0.3),
                h3: _t(16, weight: FontWeight.w600, color: BentoTheme.accentHabits, letterSpacing: -0.2),
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
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        borderRadius: _rFeatured,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (habit.hasReminder)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: BentoTheme.creamAlpha(0.45)),
                    const SizedBox(width: 6),
                    Text(
                      '${habit.reminderHour?.toString().padLeft(2, '0') ?? '--'}:${habit.reminderMinute?.toString().padLeft(2, '0') ?? '--'}',
                      style: _t(14, color: BentoTheme.creamAlpha(0.45)),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                // El emoji vive en un pocito hundido: identidad del hábito
                // engastada en el material, no flotando encima.
                _sunkenIconWell(habit.icon, size: 44, iconSize: 21, borderRadius: 14),
                const SizedBox(width: 14),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          habit.name,
                          overflow: TextOverflow.ellipsis,
                          style: _t(24, weight: FontWeight.w600, color: BentoTheme.cream, letterSpacing: -0.6),
                        ),
                      ),
                      if (habit.currentStreak() > 0) ...[
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StreakFlame(streak: habit.currentStreak(), size: 22, animate: false),
                            const SizedBox(width: 5),
                            Text(
                              '${habit.currentStreak()}',
                              style: _t(
                                17,
                                weight: FontWeight.w600,
                                color: StreakFlame.getColorForStreak(habit.currentStreak()),
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
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
                          style: _t(40, weight: FontWeight.w600, color: BentoTheme.cream, letterSpacing: -1.4, height: 1.0),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '/ $fmtGoal $unit',
                          style: _t(18, color: BentoTheme.creamAlpha(0.4), letterSpacing: -0.2),
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
                      onTap: () => _handleUpdateProgress(habit, today, -increment),
                    ),
                    const SizedBox(width: 12),
                    _stepperButton(
                      icon: Icons.add,
                      filled: true,
                      onTap: () => _handleUpdateProgress(habit, today, increment),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _neuProgressBar(ratio, BentoTheme.accentHabits, height: 10),
            const SizedBox(height: 10),
            _buildWeekRow(habit, today, days, accent: BentoTheme.accentHabits, dotSize: 26),
          ],
        ),
      ),
    );
  }

  /// Fila de la semana con objetivos táctiles reales.
  ///
  /// Los puntos siguen midiendo 22–26px porque visualmente funcionan, pero
  /// ahora cada uno vive dentro de una celda de 44px de alto que es la que
  /// recibe el toque. Antes el área tocable era el propio punto, y fallar el
  /// tiro marcaba el día de al lado.
  Widget _buildWeekRow(
    Habit habit,
    DateTime today,
    List<DateTime> days, {
    required Color accent,
    required double dotSize,
  }) {
    return Row(
      children: days.map((day) {
        final isToday = day == today;
        final isCompleted = habit.isCompletedOn(day);
        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _handleToggleHabit(habit, day, details.globalPosition),
            child: SizedBox(
              height: 48,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _getWeekdayLetter(day),
                    style: _t(
                      12,
                      weight: isToday ? FontWeight.w600 : FontWeight.w400,
                      color: isToday ? accent : BentoTheme.creamAlpha(0.4),
                    ),
                  ),
                  const SizedBox(height: 7),
                  _DayDot(
                    completed: isCompleted,
                    isToday: isToday,
                    accent: accent,
                    size: dotSize,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _stepperButton({required IconData icon, required bool filled, required VoidCallback onTap}) {
    // Botones físicos: el "+" es la acción primaria (pieza acentuada), el "−"
    // es la misma pieza en material neutro. Ambos con física de presión.
    return NeuCard(
      onTap: onTap,
      width: 40,
      height: 40,
      borderRadius: 20,
      distance: 3,
      blur: 6,
      padding: EdgeInsets.zero,
      color: filled ? BentoTheme.accentHabits : null,
      child: Center(
        child: Icon(icon, size: 17, color: filled ? const Color(0xFF0C0C0D) : BentoTheme.cream),
      ),
    );
  }

  /// Pocito hundido cuadrado para engastar el emoji/identidad de un hábito.
  ///
  /// `lite`: hay uno por fila y a 34px las sombras interiores desenfocadas no
  /// aportan nada que el degradado cóncavo no dé ya.
  Widget _sunkenIconWell(String emoji, {required double size, required double iconSize, required double borderRadius}) {
    return NeuPressed(
      lite: true,
      borderRadius: borderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(child: Twemoji(emoji: emoji, height: iconSize, width: iconSize)),
      ),
    );
  }

  /// Pista de progreso física: canal hundido en la superficie con relleno de
  /// acento cilíndrico (brillo arriba, sombra abajo). Las sombras interiores
  /// del canal se pintan POR ENCIMA del relleno, así que el líquido se lee
  /// dentro del hueco.
  ///
  /// Es la ÚNICA barra de progreso de la pantalla. Antes convivía con otra de
  /// 5px que llevaba un `boxShadow` del mismo color para simular resplandor —
  /// ese glow es lo que más fechaba el panel de cabecera.
  Widget _neuProgressBar(double ratio, Color accent, {double height = 10}) {
    return NeuPressed(
      borderRadius: 100,
      distance: 2,
      blur: 4,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: ratio.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => FractionallySizedBox(
                widthFactor: value,
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
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 12),
      borderRadius: _rCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _sunkenIconWell(habit.icon, size: 38, iconSize: 17, borderRadius: _rChip),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            habit.name,
                            overflow: TextOverflow.ellipsis,
                            style: _t(17, weight: FontWeight.w600, color: BentoTheme.cream, letterSpacing: -0.3),
                          ),
                        ),
                        if (habit.currentStreak() > 0) ...[
                          const SizedBox(width: 6),
                          StreakFlame(streak: habit.currentStreak(), size: 16, animate: false),
                          const SizedBox(width: 4),
                          Text(
                            '${habit.currentStreak()}',
                            style: _t(
                              14,
                              weight: FontWeight.w600,
                              color: StreakFlame.getColorForStreak(habit.currentStreak()),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (metaParts.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        metaParts.join(' · '),
                        overflow: TextOverflow.ellipsis,
                        style: _t(13.5, color: BentoTheme.creamAlpha(0.42)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Objetivo táctil de 48×48 alrededor del punto de hoy.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _handleToggleHabit(habit, today, details.globalPosition),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: _DayDot(
                      completed: isCompleted,
                      isToday: true,
                      accent: habit.colorValue,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _buildWeekRow(habit, today, days, accent: habit.colorValue, dotSize: 22),
        ],
      ),
    );
  }
}

/// Toggle de día: vacío = hueco circular en la superficie (con punto de acento
/// si es hoy); completado = disco de acento extruido con volumen cilíndrico.
/// Estado leído por el tacto: hundido pide acción, extruido celebra lo hecho.
///
/// Es un widget con estado propio sólo para poder animar el momento en que se
/// marca: la pieza sale del hueco con un rebote corto. Un cambio instantáneo
/// entre dos formas se lee como un parpadeo, no como una acción.
class _DayDot extends StatefulWidget {
  const _DayDot({
    required this.completed,
    required this.isToday,
    required this.accent,
    required this.size,
  });

  final bool completed;
  final bool isToday;
  final Color accent;
  final double size;

  @override
  State<_DayDot> createState() => _DayDotState();
}

class _DayDotState extends State<_DayDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant _DayDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sólo al marcar. Desmarcar es una corrección, no un logro: no merece
    // rebote.
    if (widget.completed && !oldWidget.completed) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget dot = widget.completed
        ? Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(widget.accent, Colors.white, 0.28)!,
                  widget.accent,
                  Color.lerp(widget.accent, Colors.black, 0.18)!,
                ],
              ),
              boxShadow: BentoTheme.neuRaisedLite(distance: 2, blur: 4),
            ),
            child: Icon(Icons.check, size: widget.size * 0.54, color: Colors.white),
          )
        : NeuPressed(
            lite: true,
            borderRadius: widget.size / 2,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: widget.isToday
                  ? Center(
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: widget.accent),
                      ),
                    )
                  : null,
            ),
          );

    if (!widget.completed) return dot;

    return ScaleTransition(
      scale: Tween<double>(begin: 0.55, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
      ),
      child: dot,
    );
  }
}
