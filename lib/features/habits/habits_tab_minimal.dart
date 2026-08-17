import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/achievement_catalog.dart';
import '../../core/models/habit_model.dart';
import '../../core/network/local_ai_client.dart';
import '../../core/providers/exercise_habit_link_provider.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/providers/rpg_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/minimal_theme.dart';
import '../../core/utils/error_snackbar.dart';
import '../exercise/exercise_capture_flow.dart';
import 'habit_detail_screen.dart';
import 'habit_form_dialog.dart';
import 'habit_template_picker.dart';
import 'widgets/habit_glyph.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

double _incrementFor(String? unit) {
  final unitLower = (unit ?? '').toLowerCase();
  if (unitLower == 'l') return 0.25;
  if (unitLower == 'ml') return 250.0;
  if (unitLower == 'pasos' || unitLower == 'steps') return 1000.0;
  if (unitLower == 'min' || unitLower == 'minutos') return 5.0;
  return 1.0;
}

/// Formato corto para valores de meta: sin decimales cuando son enteros, y
/// coma decimal (es-ES) cuando no.
String _fmtValue(double v) =>
    v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

/// Pestaña de Hábitos en el sistema minimalista.
///
/// Convive con [HabitsTab] (el diseño neumórfico) en vez de reemplazarlo: es un
/// piloto para probar el lenguaje sobre una pantalla real antes de invertir en
/// el contrato de skins. Cambiar entre las dos es cambiar una línea en
/// `dashboard_screen.dart`.
///
/// Diferencias de comportamiento respecto de [HabitsTab], todas deliberadas:
///
///  - No hay confeti, ni popup de XP, ni toast de logro al completar. La
///    recompensa de XP se sigue otorgando (el estado RPG no cambia), pero deja
///    de anunciarse: la celebración repetida es lo primero que se degrada de
///    delicia a molestia.
///  - Ningún hábito tiene color propio. Se distinguen por su nombre.
///  - La racha es texto plano, sin llama y sin escala de color.
class HabitsTabMinimal extends ConsumerStatefulWidget {
  const HabitsTabMinimal({super.key});

  @override
  ConsumerState<HabitsTabMinimal> createState() => _HabitsTabMinimalState();
}

class _HabitsTabMinimalState extends ConsumerState<HabitsTabMinimal> {
  bool _analyzing = false;
  String? _aiFeedback;

  List<DateTime> _currentWeek() {
    final today = _dateOnly(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return List.generate(7, (i) => monday.add(Duration(days: i)));
  }

  static const List<String> _weekdayLetters = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  // ─────────────────────────── acciones ───────────────────────────

  Future<void> _analyzeWithAI(List<Habit> habits) async {
    setState(() {
      _analyzing = true;
      _aiFeedback = null;
    });

    final settings = ref.read(settingsProvider);
    final buffer = StringBuffer()..writeln('Mi panel de hábitos:');
    for (final h in habits) {
      buffer.writeln(
        '- "${h.name}" (${h.category.label}): racha actual ${h.currentStreak()} días, '
        'mejor racha ${h.bestStreak()} días, cumplimiento 30 días ${(h.completionRate(days: 30) * 100).round()}%.',
      );
    }
    buffer.writeln(
        '\nAnaliza de forma concisa mis patrones generales. Dame un tip específico y motivador como coach de vida para mejorar.');

    try {
      final client = LocalAIClient(baseUrl: settings.localAiUrl, textModelName: settings.textModel);
      final response = await client.askText(
        buffer.toString(),
        systemPrompt:
            'Eres un coach de productividad amigable y analítico. Responde en español de forma directa, breve, estructurada y en un tono motivador.',
      );
      if (mounted) setState(() => _aiFeedback = response);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, message: 'Error al conectar con la IA Local: $e');
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _toggle(Habit habit, DateTime day) async {
    final wasCompleted = habit.isCompletedOn(day);
    await ref.read(habitsProvider.notifier).toggleHabit(habit.id, day);

    if (wasCompleted) {
      ref.read(rpgProvider.notifier).revertReward(15, 5, counterKeys: const [RpgCounters.habitsDone]);
      return;
    }

    ref.read(rpgProvider.notifier).gainXpAndGold(15, 5, counterKeys: const [RpgCounters.habitsDone]);

    // Único caso en que completar abre algo: el hábito vinculado a Ejercicio
    // ofrece registrar la sesión sin obligar a ir a buscar esa pestaña.
    final linkedExerciseHabitId = ref.read(exerciseHabitLinkProvider);
    if (linkedExerciseHabitId != habit.id || !mounted) return;

    final wantsToLog = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: MinimalTheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MinimalTheme.groupRadius)),
        title: Text('¿Guardar tu progreso de hoy?', style: MinimalTheme.title),
        content: Text(
          'Toma hasta 5 fotos y registra los datos de tu ejercicio.',
          style: MinimalTheme.body.copyWith(color: MinimalTheme.secondaryLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Ahora no', style: MinimalTheme.body.copyWith(color: MinimalTheme.secondaryLabel)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Guardar', style: MinimalTheme.bodyEmphasis),
          ),
        ],
      ),
    );
    if (wantsToLog == true && mounted) {
      await runExerciseCaptureFlow(context, ref, forDate: day, habitId: habit.id);
    }
  }

  Future<void> _addProgress(Habit habit, DateTime day) async {
    final wasCompleted = habit.isCompletedOn(day);
    await ref
        .read(habitsProvider.notifier)
        .updateHabitProgress(habit.id, day, _incrementFor(habit.goalUnit));

    final updated = ref.read(habitsProvider).where((h) => h.id == habit.id).firstOrNull;
    if (updated == null) return;

    final isCompletedNow = updated.isCompletedOn(day);
    if (!wasCompleted && isCompletedNow) {
      ref.read(rpgProvider.notifier).gainXpAndGold(15, 5, counterKeys: const [RpgCounters.habitsDone]);
    } else if (wasCompleted && !isCompletedNow) {
      ref.read(rpgProvider.notifier).revertReward(15, 5, counterKeys: const [RpgCounters.habitsDone]);
    }
  }

  // ─────────────────────────── build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final habits = ref.watch(habitsProvider);
    final days = _currentWeek();
    final today = _dateOnly(DateTime.now());

    final activeToday = habits.where((h) => h.isActiveOn(today)).toList();
    final pending = activeToday.where((h) => !h.isCompletedOn(today)).toList();
    final completed = activeToday.where((h) => h.isCompletedOn(today)).toList();
    final longestStreak =
        habits.isEmpty ? 0 : habits.map((h) => h.currentStreak()).reduce((a, b) => a > b ? a : b);

    return ColoredBox(
      color: MinimalTheme.canvas,
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 120),
        children: [
          _header(habits),
          _summaryLine(habits.isEmpty, completed.length, activeToday.length, longestStreak),
          _weekStrip(habits, days, today),
          if (_aiFeedback != null) _aiNote(),
          if (habits.isEmpty)
            _emptyNote('Todavía no tienes hábitos. Empieza por uno.')
          else if (activeToday.isEmpty)
            _emptyNote('Hoy no toca ninguno de tus hábitos.')
          else if (pending.isEmpty)
            _emptyNote('Todo hecho por hoy.'),
          if (pending.isNotEmpty)
            _group([for (final h in pending) _habitRow(h, today, done: false)]),
          if (completed.isNotEmpty) ...[
            _sectionLabel('Completados'),
            _group([for (final h in completed) _habitRow(h, today, done: true)]),
          ],
          _rpgFooter(),
        ],
      ),
    );
  }

  Widget _header(List<Habit> habits) {
    return Padding(
      // El margen derecho se reduce porque los botones ya traen su propia zona
      // táctil de 40: sin esto el último glifo queda visualmente hundido.
      padding: const EdgeInsets.fromLTRB(MinimalTheme.margin, 4, MinimalTheme.margin - 12, 0),
      child: Row(
        children: [
          Expanded(child: Text('Hábitos', style: MinimalTheme.largeTitle)),
          _action(
            icon: Icons.auto_awesome_outlined,
            tooltip: 'Elegir hábito prearmado',
            onTap: () => showHabitTemplatePicker(context, ref),
          ),
          _action(
            icon: Icons.insights_outlined,
            tooltip: 'Analizar hábitos con IA',
            busy: _analyzing,
            onTap: habits.isEmpty || _analyzing ? null : () => _analyzeWithAI(habits),
          ),
          _action(
            icon: Icons.add,
            tooltip: 'Nuevo hábito',
            onTap: () => showHabitFormDialog(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 44,
          child: Center(
            child: busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: MinimalTheme.secondaryLabel,
                    ),
                  )
                : Icon(
                    icon,
                    size: 22,
                    color: onTap == null ? MinimalTheme.quaternaryLabel : MinimalTheme.label,
                  ),
          ),
        ),
      ),
    );
  }

  /// La única frase de la pantalla. Sustituye al panel de rachas con llama: el
  /// mismo dato, sin el color ni la carga de deuda.
  Widget _summaryLine(bool noHabits, int done, int active, int streak) {
    final String text;
    if (noHabits) {
      text = 'Sin hábitos todavía';
    } else if (active == 0) {
      text = 'Día libre';
    } else {
      final base = '$done de $active hoy';
      text = streak > 0 ? '$base · racha de $streak ${streak == 1 ? 'día' : 'días'}' : base;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(MinimalTheme.margin, 2, MinimalTheme.margin, 0),
      child: Text(text, style: MinimalTheme.body.copyWith(color: MinimalTheme.secondaryLabel)),
    );
  }

  /// Una sola tira semanal agregada, en lugar de siete puntos por hábito.
  ///
  /// Con cinco hábitos, la versión anterior ponía 35 puntos de colores en
  /// pantalla; esta pone 7 barras monocromas. La altura de cada barra es la
  /// proporción de hábitos completados ese día.
  Widget _weekStrip(List<Habit> habits, List<DateTime> days, DateTime today) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(MinimalTheme.margin, 22, MinimalTheme.margin, 4),
      child: Row(
        children: [
          for (var i = 0; i < days.length; i++)
            Expanded(child: _weekColumn(habits, days[i], today, _weekdayLetters[i])),
        ],
      ),
    );
  }

  Widget _weekColumn(List<Habit> habits, DateTime day, DateTime today, String letter) {
    final active = habits.where((h) => h.isActiveOn(day)).length;
    final done = habits.where((h) => h.isActiveOn(day) && h.isCompletedOn(day)).length;
    final isFuture = day.isAfter(today);
    final isToday = day == today;
    final ratio = (isFuture || active == 0) ? 0.0 : done / active;

    return Column(
      children: [
        Text(
          letter,
          style: MinimalTheme.caption.copyWith(
            color: isToday ? MinimalTheme.label : MinimalTheme.tertiaryLabel,
            fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: SizedBox(
            height: 34,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: MinimalTheme.fill),
                  if (ratio > 0)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        // Suelo del 12%: un día con 1 de 8 hábitos tiene que
                        // verse como algo, no como vacío.
                        heightFactor: ratio.clamp(0.12, 1.0),
                        child: ColoredBox(color: MinimalTheme.label.withValues(alpha: 0.55)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _habitRow(Habit habit, DateTime today, {required bool done}) {
    final goal = habit.goalValue;
    final progress = goal == null ? 0.0 : (habit.dailyProgress[_dateOnly(today)] ?? 0.0);
    final ratio = (goal == null || goal == 0) ? 0.0 : (progress / goal).clamp(0.0, 1.0);

    return _PressableRow(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => HabitDetailScreen(habitId: habit.id)),
      ),
      child: SizedBox(
        height: MinimalTheme.rowHeight,
        child: Row(
          children: [
            // El control ocupa toda la banda hasta el inset del separador, así
            // su zona táctil es de 58×56 y no de 24×24.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => goal == null ? _toggle(habit, today) : _addProgress(habit, today),
              onLongPress: () => _toggle(habit, today),
              child: SizedBox(
                width: MinimalTheme.separatorInset,
                height: MinimalTheme.rowHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: MinimalTheme.margin),
                    child: _control(done: done, ratio: ratio),
                  ),
                ),
              ),
            ),
            Icon(
              HabitGlyph.of(habit),
              size: 18,
              color: done ? MinimalTheme.quaternaryLabel : MinimalTheme.tertiaryLabel,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                habit.name,
                overflow: TextOverflow.ellipsis,
                style: MinimalTheme.body.copyWith(
                  color: done ? MinimalTheme.tertiaryLabel : MinimalTheme.label,
                ),
              ),
            ),
            if (goal != null) ...[
              const SizedBox(width: 8),
              Text(
                '${_fmtValue(progress)}/${habit.goalLabel}',
                style: MinimalTheme.numeric.copyWith(
                  color: done ? MinimalTheme.tertiaryLabel : MinimalTheme.secondaryLabel,
                ),
              ),
            ],
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 18, color: MinimalTheme.quaternaryLabel),
            const SizedBox(width: MinimalTheme.margin - 6),
          ],
        ),
      ),
    );
  }

  /// Círculo de completar. El relleno parcial desde abajo usa el mismo lenguaje
  /// que las barras de la tira semanal: una sola metáfora para "cuánto llevas".
  Widget _control({required bool done, required double ratio}) {
    return AnimatedContainer(
      duration: MinimalTheme.motion,
      curve: MinimalTheme.motionCurve,
      width: MinimalTheme.controlSize,
      height: MinimalTheme.controlSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? MinimalTheme.label : Colors.transparent,
        // El borde se mantiene siempre (cambia de color, no de existencia) para
        // que AnimatedContainer pueda interpolar en vez de saltar.
        border: Border.all(
          color: done ? MinimalTheme.label : MinimalTheme.quaternaryLabel,
          width: 1.5,
        ),
      ),
      child: done
          ? Icon(Icons.check, size: 14, color: MinimalTheme.canvas)
          : (ratio > 0
              ? ClipOval(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: ratio,
                      child: ColoredBox(color: MinimalTheme.label.withValues(alpha: 0.35)),
                    ),
                  ),
                )
              : null),
    );
  }

  // ─────────────────────────── piezas menores ───────────────────────────

  Widget _group(List<Widget> rows) {
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) children.add(_separator());
      children.add(rows[i]);
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: MinimalTheme.margin),
      decoration: BoxDecoration(
        color: MinimalTheme.surface,
        borderRadius: BorderRadius.circular(MinimalTheme.groupRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  /// Entrado hasta el texto, nunca al borde del grupo.
  Widget _separator() => Padding(
        padding: const EdgeInsets.only(left: MinimalTheme.separatorInset),
        child: Container(height: 1, color: MinimalTheme.separator),
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(MinimalTheme.margin, 26, MinimalTheme.margin, 8),
        child: Text(text, style: MinimalTheme.footnote.copyWith(color: MinimalTheme.tertiaryLabel)),
      );

  Widget _emptyNote(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(MinimalTheme.margin, 24, MinimalTheme.margin, 0),
        child: Text(text, style: MinimalTheme.body.copyWith(color: MinimalTheme.tertiaryLabel)),
      );

  Widget _aiNote() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(MinimalTheme.margin, 24, MinimalTheme.margin, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: MinimalTheme.surface,
          borderRadius: BorderRadius.circular(MinimalTheme.groupRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Análisis',
                    style: MinimalTheme.footnote.copyWith(color: MinimalTheme.tertiaryLabel),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _aiFeedback = null),
                  child: Icon(Icons.close, size: 18, color: MinimalTheme.quaternaryLabel),
                ),
              ],
            ),
            const SizedBox(height: 8),
            MarkdownBody(
              data: _aiFeedback!,
              styleSheet: MarkdownStyleSheet(
                p: MinimalTheme.body.copyWith(color: MinimalTheme.secondaryLabel),
                strong: MinimalTheme.bodyEmphasis,
                listBullet: MinimalTheme.body.copyWith(color: MinimalTheme.secondaryLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// El RPG baja a una línea de texto al pie. Arriba va lo de hoy; los puntos
  /// no son lo de hoy.
  Widget _rpgFooter() {
    final rpg = ref.watch(rpgProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(MinimalTheme.margin, 28, MinimalTheme.margin, 0),
      child: Text(
        'Nivel ${rpg.level} · ${rpg.xp}/${rpg.xpNeeded} XP',
        style: MinimalTheme.footnote.copyWith(color: MinimalTheme.tertiaryLabel),
      ),
    );
  }
}

/// Realce sólido bajo el dedo, no ripple: iOS resalta la fila entera y la
/// suelta: no propaga una onda desde el punto de contacto.
class _PressableRow extends StatefulWidget {
  const _PressableRow({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_PressableRow> createState() => _PressableRowState();
}

class _PressableRowState extends State<_PressableRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        color: _pressed ? MinimalTheme.surfacePressed : MinimalTheme.surface,
        child: widget.child,
      ),
    );
  }
}
