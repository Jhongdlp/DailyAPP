import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/achievement_catalog.dart';
import '../../core/models/habit_model.dart';
import '../../core/network/local_ai_client.dart';
import '../../core/providers/exercise_habit_link_provider.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/providers/profile_provider.dart';
import '../../core/providers/rpg_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/utils/error_snackbar.dart';
import '../../core/widgets/rpg_celebration.dart';
import '../exercise/exercise_capture_flow.dart';
import 'habit_detail_screen.dart';
import 'widgets/notched_card.dart';
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

String _fmt(double v) =>
    v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

/// Pestaña de Hábitos: tarjetas apiladas al estilo de una lista de commits.
///
/// La composición viene de ahí: fila de ancho completo, icono a la izquierda en
/// su casilla, título en negrita, una línea de metadatos apagada debajo, el
/// estado a la derecha, y los cuadraditos de contribución abajo. Es una
/// estructura hecha para escanear muchas filas rápido sin que ninguna grite.
///
/// El mecanismo de estado sigue siendo la inversión: completar un hábito
/// invierte su tarjeta de crema-sobre-negro a negro-sobre-crema, ahora
/// interpolada en 280ms en vez de saltar.
class HabitsTabEditorial extends ConsumerStatefulWidget {
  const HabitsTabEditorial({super.key});

  @override
  ConsumerState<HabitsTabEditorial> createState() => _HabitsTabEditorialState();
}

class _HabitsTabEditorialState extends ConsumerState<HabitsTabEditorial> {
  bool _analyzing = false;
  String? _aiFeedback;

  /// Día que se está viendo y editando. Arranca en hoy; el selector de la
  /// cabecera lo mueve por la semana.
  DateTime _selectedDay = _dateOnly(DateTime.now());

  /// Hábitos recién marcados que todavía se muestran en "Pendientes".
  ///
  /// Sin esto, al tocar el check la tarjeta desaparece de golpe de su sitio y
  /// reaparece abajo: se lee como un salto, no como un movimiento. Reteniéndola
  /// un momento, la secuencia se vuelve legible — la tarjeta **se llena de
  /// color donde estaba** (ahí ves que la marcaste) y recién entonces baja al
  /// grupo de hechos.
  final Set<String> _settling = {};
  final Set<String> _shrinking = {};
  final Set<String> _expanding = {};

  // ─── Tiempos del viaje al grupo de hechos ───
  //
  // Las tres fases son una sola animación repartida entre dos listas, así que
  // los tiempos viven acá y [_HabitTransitionWrapper] los recibe: si el
  // temporizador que cambia de lista y el controlador que anima la tarjeta
  // llevaran duraciones distintas, la tarjeta saltaría de grupo antes o después
  // de terminar de moverse, que es el único bug que se ve a simple vista.
  //
  // El total ronda el segundo, y es a propósito. Marcar un hábito es la acción
  // que más se repite en la app y también la que se siente bien: acelerarla no
  // ahorra nada —la lista sigue siendo tuya mientras dura— y sí borra el único
  // momento en que la pantalla te devuelve algo.

  /// La tarjeta se queda quieta llenándose de color, en su sitio.
  static const Duration _settleDuration = Duration(milliseconds: 300);

  /// Se va hacia abajo mientras cierra su altura.
  static const Duration _collapseDuration = Duration(milliseconds: 340);

  /// Reaparece en "Hechos" llegando desde arriba. Un pelo más larga que la
  /// salida: entrar frenando se lee como llegar; entrar y parar en seco, como
  /// aparecer.
  static const Duration _expandDuration = Duration(milliseconds: 400);

  @override
  void dispose() {
    _settling.clear();
    _shrinking.clear();
    _expanding.clear();
    super.dispose();
  }

  void _settleThenRegroup(String habitId) {
    setState(() {
      _settling.add(habitId);
    });

    // Fase 2: la tarjeta empieza a irse hacia abajo y a colapsar.
    Future<void>.delayed(_settleDuration, () {
      if (mounted) {
        setState(() {
          _shrinking.add(habitId);
        });
      }
    });

    // Fase 3: reaparece en el grupo de hechos, llegando desde arriba.
    Future<void>.delayed(_settleDuration + _collapseDuration, () {
      if (mounted) {
        setState(() {
          _settling.remove(habitId);
          _shrinking.remove(habitId);
          _expanding.add(habitId);
        });

        // Limpia el estado de expansión una vez termina la animación
        Future<void>.delayed(_expandDuration, () {
          if (mounted) {
            setState(() {
              _expanding.remove(habitId);
            });
          }
        });
      }
    });
  }

  String _formattedDate() {
    final now = DateTime.now();
    final dayName = _dayNames[now.weekday - 1].toUpperCase();
    final monthName = _monthNames[now.month - 1];
    return '$dayName, ${now.day} DE $monthName';
  }

  static const List<String> _dayLetters = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
  static const List<String> _dayNames = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  /// Los últimos siete días, terminando HOY.
  ///
  /// Antes era la semana de calendario (lunes a domingo), lo que en lunes
  /// dejaba seis casillas futuras vacías ocupando la mayor parte del selector:
  /// justo lo contrario de lo que sirve, que es ver cómo vienen los días que ya
  /// pasaron. Con la ventana móvil los siete chips siempre tienen historia y el
  /// futuro deja de existir en la pantalla.
  List<DateTime> _visibleDays() {
    final today = _dateOnly(DateTime.now());
    return List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
  }

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
      '\nAnaliza de forma concisa mis patrones generales. Dame un tip específico y motivador como coach de vida para mejorar.',
    );

    try {
      final client = LocalAIClient(
        baseUrl: settings.localAiUrl,
        textModelName: settings.textModel,
      );
      final response = await client.askText(
        buffer.toString(),
        systemPrompt:
            'Eres un coach de productividad amigable y analítico. Responde en español de forma directa, breve, estructurada y en un tono motivador.',
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

  void _showUndoBar(String message, VoidCallback onUndo) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: EditorialTheme.text(14, color: EditorialTheme.ink)),
        backgroundColor: EditorialTheme.paper,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
        ),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 104),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Deshacer',
          textColor: EditorialTheme.ink,
          onPressed: onUndo,
        ),
      ),
    );
  }

  /// Un día futuro se puede mirar pero no marcar: dar por hecho mañana lo que
  /// no hiciste hoy casi siempre es un error de dedo, y ensucia rachas y
  /// porcentajes con datos que no ocurrieron.
  bool _blockIfFuture(DateTime day) {
    if (!day.isAfter(_dateOnly(DateTime.now()))) return false;
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Todavía no puedes marcar un día que no llegó',
            style: EditorialTheme.text(14, color: EditorialTheme.ink),
          ),
          backgroundColor: EditorialTheme.paper,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
          ),
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 104),
          duration: const Duration(seconds: 3),
        ),
      );
    return true;
  }

  Future<void> _toggle(Habit habit, DateTime day) async {
    if (_blockIfFuture(day)) return;
    final wasCompleted = habit.isCompletedOn(day);

    // Antes del await: el acuse táctil tiene que llegar en el mismo gesto, no
    // cuando vuelve la red.
    if (wasCompleted) {
      HapticFeedback.selectionClick();
    } else {
      HapticFeedback.mediumImpact();
    }

    await ref.read(habitsProvider.notifier).toggleHabit(habit.id, day);

    if (wasCompleted) {
      ref
          .read(rpgProvider.notifier)
          .revertReward(15, 5, counterKeys: const [RpgCounters.habitsDone]);
      if (mounted) {
        _showUndoBar('Desmarcado "${habit.name}"', () => _toggle(habit, day));
      }
      return;
    }

    final result = ref
        .read(rpgProvider.notifier)
        .gainXpAndGold(15, 5, counterKeys: const [RpgCounters.habitsDone]);
    if (mounted) {
      _settleThenRegroup(habit.id);
      AchievementToast.show(context, result['unlocked']);
    }

    final linkedExerciseHabitId = ref.read(exerciseHabitLinkProvider);
    if (linkedExerciseHabitId != habit.id || !mounted) return;

    final wantsToLog = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: EditorialTheme.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
        ),
        title: Text(
          '¿Guardar tu progreso de hoy?',
          style: EditorialTheme.text(19, weight: FontWeight.w600, color: EditorialTheme.ink),
        ),
        content: Text(
          'Toma hasta 5 fotos y registra los datos de tu ejercicio.',
          style: EditorialTheme.text(15, color: EditorialTheme.inkAlpha(0.6), height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Ahora no',
              style: EditorialTheme.text(
                15,
                weight: FontWeight.w600,
                color: EditorialTheme.inkAlpha(0.55),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Guardar',
              style: EditorialTheme.text(15, weight: FontWeight.w700, color: EditorialTheme.ink),
            ),
          ),
        ],
      ),
    );
    if (wantsToLog == true && mounted) {
      await runExerciseCaptureFlow(context, ref, forDate: day, habitId: habit.id);
    }
  }

  Future<void> _addProgress(Habit habit, DateTime day) =>
      _addProgressBy(habit, day, _incrementFor(habit.goalUnit));

  Future<void> _addProgressBy(Habit habit, DateTime day, double delta) async {
    if (_blockIfFuture(day)) return;
    final wasCompleted = habit.isCompletedOn(day);
    HapticFeedback.selectionClick();
    await ref.read(habitsProvider.notifier).updateHabitProgress(habit.id, day, delta);

    final updated = ref.read(habitsProvider).where((h) => h.id == habit.id).firstOrNull;
    if (updated == null) return;

    final isCompletedNow = updated.isCompletedOn(day);
    if (!wasCompleted && isCompletedNow) {
      HapticFeedback.mediumImpact();
      final result = ref
          .read(rpgProvider.notifier)
          .gainXpAndGold(15, 5, counterKeys: const [RpgCounters.habitsDone]);
      if (mounted) {
        _settleThenRegroup(habit.id);
        AchievementToast.show(context, result['unlocked']);
      }
    } else if (wasCompleted && !isCompletedNow) {
      ref
          .read(rpgProvider.notifier)
          .revertReward(15, 5, counterKeys: const [RpgCounters.habitsDone]);
    }
  }

  // ─────────────────────────── build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final habits = ref.watch(habitsProvider);
    final days = _visibleDays();
    final today = _dateOnly(DateTime.now());
    final day = _selectedDay;

    // Toda la pantalla cuelga del día ELEGIDO, no de hoy: qué hábitos tocan,
    // cuáles están hechos y qué hace el círculo de completar.
    final activeToday = habits.where((h) => h.isActiveOn(day)).toList();
    final done = activeToday.where((h) => h.isCompletedOn(day)).length;

    // Separar en dos grupos en vez de una lista corrida: lo pendiente es lo
    // accionable y va primero; lo hecho es historia del día y se aparta. Una
    // lista única obliga a barrer toda la pantalla para saber qué falta.
    final pending = activeToday
        .where((h) => !h.isCompletedOn(day) || _settling.contains(h.id))
        .toList();
    final finished = activeToday
        .where((h) => h.isCompletedOn(day) && !_settling.contains(h.id))
        .toList();

    return ColoredBox(
      color: EditorialTheme.canvas,
      child: Center(
        child: ConstrainedBox(
          // En un teléfono no hace nada (siempre mide menos). En escritorio
          // evita que la columna se estire hasta deformar las proporciones.
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.only(top: 14, bottom: 120),
            children: [
              _greetingRow(habits),
              _heroPanel(habits, days, done, activeToday.length, today, day),
              if (_aiFeedback != null) _aiCard(),
              if (habits.isEmpty)
                _emptyState(
                  'Todavía no tienes hábitos',
                  'Empieza por uno. Se construye de a poco.',
                )
              else if (activeToday.isEmpty)
                _emptyState(
                  _isSameDay(day, today) ? 'Hoy no toca ninguno' : 'Ese día no toca ninguno',
                  'Ningún hábito está programado para ${_dayLabel(day, today).toLowerCase()}.',
                ),
              if (pending.isNotEmpty)
                _groupLabel(
                  'Pendientes',
                  pending.length,
                  trailing: Text(
                    activeToday.isEmpty
                        ? 'NINGÚN HÁBITO'
                        : '$done DE ${activeToday.length} COMPLETADOS',
                    style: EditorialTheme.label(10, color: EditorialTheme.muted),
                  ),
                ),
              for (var i = 0; i < pending.length; i++)
                _cardSlot(pending[i], i, day, today, days),
              if (finished.isNotEmpty) _groupLabel('Hechos', finished.length),
              for (var i = 0; i < finished.length; i++)
                _cardSlot(finished[i], pending.length + i, day, today, days),
            ],
          ),
        ),
      ),
    );
  }

  static const List<String> _monthNames = [
    'ENERO', 'FEBRERO', 'MARZO', 'ABRIL', 'MAYO', 'JUNIO',
    'JULIO', 'AGOSTO', 'SEPTIEMBRE', 'OCTUBRE', 'NOVIEMBRE', 'DICIEMBRE',
  ];

  /// Saludo y acciones, sobre el lienzo. Va fuera del panel: el panel es un
  /// bloque de datos y el saludo es una voz — mezclarlos le quitaría a cada uno
  /// su registro.
  Widget _greetingRow(List<Habit> habits) {
    final greeting = greetingForHour(DateTime.now().hour);
    // El nombre llega por red. Mientras no esté, se saluda igual: hacer esperar
    // a la cabecera por un nombre sería peor que no tenerlo.
    final name = ref.watch(profileNameProvider).value;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EditorialTheme.margin,
        0,
        EditorialTheme.margin,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (name != null) ...[
                  Text(
                    '$greeting,',
                    style: EditorialTheme.text(15, color: EditorialTheme.muted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EditorialTheme.caps(
                      34,
                      color: EditorialTheme.paper,
                      letterSpacing: -0.8,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _formattedDate(),
                    style: EditorialTheme.label(10.5, color: EditorialTheme.muted),
                  ),
                ] else ...[
                  // Sin nombre, el saludo ocupa el lugar del título.
                  Text(
                    greeting.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EditorialTheme.caps(
                      32,
                      color: EditorialTheme.paper,
                      letterSpacing: -0.8,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _formattedDate(),
                    style: EditorialTheme.label(10.5, color: EditorialTheme.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _circleButton(
            icon: Icons.auto_awesome_outlined,
            tooltip: 'Elegir hábito prearmado',
            onTap: () => showHabitTemplatePicker(context, ref),
          ),
          const SizedBox(width: 8),
          _circleButton(
            icon: Icons.insights_outlined,
            tooltip: 'Analizar hábitos con IA',
            busy: _analyzing,
            onTap: habits.isEmpty || _analyzing ? null : () => _analyzeWithAI(habits),
          ),
          const SizedBox(width: 8),
          _circleButton(
            icon: Icons.add,
            tooltip: 'Nuevo hábito',
            onTap: () => showHabitFormDialog(context, ref),
          ),
        ],
      ),
    );
  }

  /// Panel protagonista.
  ///
  /// Se gana su espacio con información, que es lo que le faltaba a la tarjeta
  /// de resumen anterior: aquella ocupaba un tercio de pantalla para repetir un
  /// número. Aquí hay cuatro capas que responden preguntas distintas:
  ///
  ///  1. **Cuánto llevo hoy** — el número grande, único foco de la pantalla.
  ///  2. **Cómo vengo** — nueve semanas de historia en el mapa de calor.
  ///  3. **Qué día miro** — la semana actual, agrandada y accionable.
  ///  4. **Cómo me va en general** — racha, semana y mes.
  ///
  /// La unidad compositiva viene de que el selector de día ES la última fila
  /// del mapa: mismas siete columnas alineadas, el pasado arriba en pequeño y
  /// el presente abajo en grande. No son dos widgets apilados, es una sola
  /// pieza que se agranda donde se puede tocar.
  Widget _heroPanel(
    List<Habit> habits,
    List<DateTime> days,
    int done,
    int active,
    DateTime today,
    DateTime day,
  ) {
    final stats = _computeStats(habits, today);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EditorialTheme.margin,
        18,
        EditorialTheme.margin,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: EditorialTheme.paper,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _monthNames[today.month - 1],
                    style: EditorialTheme.label(11, color: EditorialTheme.inkAlpha(0.45)),
                  ),
                ),
                Text(
                  _dayLabel(day, today).toUpperCase(),
                  style: EditorialTheme.label(11, color: EditorialTheme.inkAlpha(0.45)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _HeatMap(habits: habits, today: today),
            // Mismo gap que entre filas del mapa: el selector se lee como su
            // última fila, agrandada porque es la que se puede tocar.
            const SizedBox(height: EditorialTheme.dayGap),
            _daySelector(habits, days, today),
            const SizedBox(height: 14),
            Container(height: 1, color: EditorialTheme.inkAlpha(0.10)),
            const SizedBox(height: 14),
            Row(
              children: [
                _stat(
                  'Racha',
                  stats.streak == 0 ? '—' : '${stats.streak}',
                  stats.streak == 0 ? '' : 'días',
                  trailing: stats.streak > 0
                      ? MinimalFlame(
                          streak: stats.streak,
                          color: const Color(0xFFD45B45),
                          size: 14.0,
                        )
                      : null,
                ),
                _statDivider(),
                _stat('Semana', '${stats.week}', '%'),
                _statDivider(),
                _stat('Mes', '${stats.month}', '%'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, String unit, {Widget? trailing}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: EditorialTheme.label(10, color: EditorialTheme.inkAlpha(0.40)),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value,
                      style: EditorialTheme.caps(
                        22,
                        weight: FontWeight.w800,
                        color: EditorialTheme.ink,
                        letterSpacing: -0.7,
                        height: 1.0,
                      ),
                    ),
                    if (unit.isNotEmpty) ...[
                      const SizedBox(width: 2),
                      Text(
                        unit,
                        style: EditorialTheme.label(
                          9.5,
                          color: EditorialTheme.inkAlpha(0.45),
                        ),
                      ),
                    ],
                  ],
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 5),
                  trailing,
                ],
              ],
            ),
          ],
        ),
      );

  Widget _statDivider() => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        color: EditorialTheme.inkAlpha(0.10),
      );

  /// Racha más larga viva, y cumplimiento de la semana y del mes sobre TODOS
  /// los hábitos: cuántas casillas activas se cerraron de las que tocaban.
  _HabitStats _computeStats(List<Habit> habits, DateTime today) {
    if (habits.isEmpty) return const _HabitStats(0, 0, 0);

    final streak = habits.map((h) => h.currentStreak()).reduce((a, b) => a > b ? a : b);

    int expectedWeek = 0, doneWeek = 0, expectedMonth = 0, doneMonth = 0;
    for (var i = 0; i < 30; i++) {
      final d = today.subtract(Duration(days: i));
      for (final h in habits) {
        if (!h.isActiveOn(d)) continue;
        final completed = h.isCompletedOn(d);
        expectedMonth++;
        if (completed) doneMonth++;
        // La semana corriente son los días desde el lunes hasta hoy, no los
        // últimos siete: comparar "mi semana" con una ventana móvil confunde.
        if (i < today.weekday) {
          expectedWeek++;
          if (completed) doneWeek++;
        }
      }
    }

    return _HabitStats(
      streak,
      expectedWeek == 0 ? 0 : (doneWeek * 100 / expectedWeek).round(),
      expectedMonth == 0 ? 0 : (doneMonth * 100 / expectedMonth).round(),
    );
  }

  Widget _groupLabel(String text, int count, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(
          EditorialTheme.margin,
          26,
          EditorialTheme.margin,
          12,
        ),
        child: Row(
          children: [
            Text(
              text.toUpperCase(),
              style: EditorialTheme.label(12, color: EditorialTheme.muted),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: EditorialTheme.paperAlpha(0.10),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: EditorialTheme.text(
                  12,
                  weight: FontWeight.w600,
                  color: EditorialTheme.paperAlpha(0.60),
                ),
              ),
            ),
            if (trailing != null) ...[
              const Spacer(),
              trailing,
            ],
          ],
        ),
      );

  Widget _cardSlot(Habit habit, int index, DateTime day, DateTime today, List<DateTime> days) {
    return _HabitTransitionWrapper(
      key: ValueKey('${habit.id}@${day.toIso8601String()}'),
      isShrinking: _shrinking.contains(habit.id),
      isExpanding: _expanding.contains(habit.id),
      index: index,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          EditorialTheme.margin,
          0,
          EditorialTheme.margin,
          10,
        ),
        child: _habitCard(habit, day, today, days),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Nombre del día para los encabezados: "Hoy" y "Ayer" ganan al nombre propio
  /// porque es como la gente se refiere a esos dos días.
  String _dayLabel(DateTime day, DateTime today) {
    if (_isSameDay(day, today)) return 'Hoy';
    if (_isSameDay(day, today.subtract(const Duration(days: 1)))) return 'Ayer';
    if (_isSameDay(day, today.add(const Duration(days: 1)))) return 'Mañana';
    return _dayNames[day.weekday - 1];
  }

  /// Selector de día de la semana. Reemplaza a la barra de progreso: ocupaba el
  /// mismo espacio para repetir un número que ya estaba escrito al lado, y
  /// marcar un día pasado obligaba a entrar al detalle de cada hábito.
  ///
  /// Los días futuros se pueden mirar pero no marcar (ver [_toggle]): dar por
  /// hecho mañana lo que no hiciste hoy casi siempre es un error de dedo.
  /// Proporción de hábitos completados ese día, 0–1. Es el nivel del vaso.
  double _dayRatio(List<Habit> habits, DateTime day) {
    var active = 0, done = 0;
    for (final h in habits) {
      if (!h.isActiveOn(day)) continue;
      active++;
      if (h.isCompletedOn(day)) done++;
    }
    return active == 0 ? 0 : done / active;
  }

  Widget _daySelector(List<Habit> habits, List<DateTime> days, DateTime today) {
    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: EditorialTheme.dayGap),
          Expanded(
            child: _DayChip(
              letter: _dayLetters[i],
              dayOfMonth: days[i].day,
              selected: _isSameDay(days[i], _selectedDay),
              isToday: _isSameDay(days[i], today),
              isFuture: days[i].isAfter(today),
              ratio: _dayRatio(habits, days[i]),
              onTap: () {
                if (_isSameDay(days[i], _selectedDay)) return;
                HapticFeedback.selectionClick();
                setState(() => _selectedDay = days[i]);
              },
            ),
          ),
        ],
      ],
    );
  }

  /// Botón circular crema flotando sobre el lienzo. Es la única forma circular
  /// de la pantalla, así que se lee como acción sin necesitar etiqueta.
  Widget _circleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: _Pressable(
        onTap: onTap,
        scale: 0.90,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? EditorialTheme.paper : EditorialTheme.paperAlpha(0.22),
          ),
          child: Center(
            child: busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: EditorialTheme.ink,
                    ),
                  )
                : Icon(
                    icon,
                    size: 20,
                    color: enabled ? EditorialTheme.ink : EditorialTheme.inkAlpha(0.35),
                  ),
          ),
        ),
      ),
    );
  }

  /// Tarjeta de hábito: papel blanco, un bloque de color a la izquierda y el
  /// botón de completar mordido fuera de la esquina superior derecha.
  ///
  /// Tres decisiones sostienen la pieza:
  ///
  ///  1. **Todo el color vive en el bloque del icono.** El resto de la tarjeta
  ///     es papel y tinta, sin excepción. Con siete hábitos en pantalla, siete
  ///     bloques de color en la misma columna izquierda se leen como un índice;
  ///     los mismos siete colores repartidos por texto, aros y cuadraditos se
  ///     leen como ruido.
  ///  2. **El bloque es el medidor.** Pendiente es un lavado del acento; hecho
  ///     es el acento pleno con el glifo en blanco. Completar no cambia la
  ///     temperatura de la pantalla: llena un bloque. Los hábitos con meta
  ///     suben ese relleno desde abajo, así que el color mismo dice cuánto
  ///     falta sin un número al lado.
  ///  3. **El botón está fuera de la silueta.** No flota encima de la tarjeta:
  ///     la tarjeta está mordida y él ocupa el hueco, separado por un canal de
  ///     aire constante. Ver [NotchedCardBorder] para por qué el radio de abajo
  ///     va invertido.
  Widget _habitCard(Habit habit, DateTime day, DateTime today, List<DateTime> days) {
    final isDone = habit.isCompletedOn(day);
    final goal = habit.goalValue;
    final progress = goal == null ? 0.0 : (habit.dailyProgress[_dateOnly(day)] ?? 0.0);
    final ratio = (goal == null || goal == 0) ? 0.0 : (progress / goal).clamp(0.0, 1.0);
    final streak = habit.currentStreak();

    Widget metaSeparator(Color fg) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: Text(
          '·',
          style: EditorialTheme.text(13, color: fg.withValues(alpha: 0.3)),
        ),
      );
    }

    // Queda UNA sola variante del acento en toda la tarjeta, y va a un solo
    // sitio: los cuadraditos de la semana. Es la versión profunda, calibrada
    // para dibujarse sobre el papel.
    //
    // Se resuelve acá, fuera del builder animado: `accent()` hace una búsqueda
    // binaria del gamut y recalcularla en cada fotograma sería tirar CPU.
    final accentInk = EditorialTheme.accent(habit.colorValue, onDark: false);

    return _Pressable(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => HabitDetailScreen(habitId: habit.id)),
      ),
      scale: 0.985,
      // La inversión se interpola en vez de saltar: `t` va de 0 (pendiente) a
      // 1 (hecho) y de él salen TODOS los colores de la tarjeta. Un cambio
      // instantáneo entre dos paletas se lee como parpadeo, no como acción.
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: isDone ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 280),
        curve: EditorialTheme.curve,
        builder: (context, t, _) {
          // La tarjeta NO se invierte. Es papel en los dos estados y la tinta
          // es siempre la misma; `t` sólo decide cuánto se apaga el texto y
          // cuánto se llena el bloque de color. Se probó invertirla a gris
          // oscuro al completar y el precio es una lista que alterna cartas
          // blancas y negras: cada hábito marcado cambiaba el peso de toda la
          // pantalla en vez de resolverse en su propia esquina.
          const fg = EditorialTheme.ink;
          final accent = accentInk;

          final metaStyle = EditorialTheme.text(
            13,
            color: fg.withValues(alpha: 0.5 - 0.28 * t),
          );

          final metaWidgets = <Widget>[
            if (goal != null)
              Text(
                '${_fmt(progress)}/${habit.goalLabel}',
                style: metaStyle,
              ),
            if (streak > 0) ...[
              if (goal != null) metaSeparator(fg),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // La llama va en tinta, no en acento. Es del tamaño de una
                  // letra y vive dentro de una línea de texto apagada: a 11px
                  // el color no informa de nada, sólo mancha el renglón.
                  MinimalFlame(
                    streak: streak,
                    color: fg.withValues(alpha: 0.45 - 0.2 * t),
                    size: 11.5,
                  ),
                  const SizedBox(width: 3.5),
                  Text(
                    '$streak ${streak == 1 ? 'día' : 'días'}',
                    style: metaStyle,
                  ),
                ],
              ),
            ],
            if (habit.hasReminder) ...[
              if (goal != null || streak > 0) metaSeparator(fg),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 12,
                    color: fg.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: 2.5),
                  Text(
                    '${habit.reminderHour?.toString().padLeft(2, '0') ?? '--'}:'
                    '${habit.reminderMinute?.toString().padLeft(2, '0') ?? '--'}',
                    style: metaStyle,
                  ),
                ],
              ),
            ],
            if (goal == null && streak == 0 && !habit.hasReminder)
              Text(
                habit.category.label,
                style: metaStyle,
              ),
          ];

          final card = ClipPath(
            // La silueta mordida se recorta una sola vez y de ella cuelga todo:
            // el bloque de color hereda el redondeo izquierdo sin declararlo,
            // que es lo que lo hace parecer parte de la tarjeta y no una tira
            // pegada encima.
            clipper: const ShapeBorderClipper(
              shape: NotchedCardBorder(radius: EditorialTheme.radiusCard),
            ),
            child: ColoredBox(
              color: EditorialTheme.paper,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _IconBlock(
                      icon: HabitGlyph.of(habit),
                      ratio: goal == null ? 0.0 : ratio,
                    ),
                    // Área de contenido derecha
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Sólo el bloque de texto le cede espacio al
                            // mordisco; la fila de datos de abajo ya pasa por
                            // debajo y usa el ancho completo. Esa diferencia de
                            // medida entre las dos líneas es deliberada: es lo
                            // que hace que el hueco se lea como parte de la
                            // composición y no como un recorte que aplastó el
                            // contenido.
                            Padding(
                              padding: const EdgeInsets.only(
                                right: NotchMetrics.contentInset - 16,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    habit.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: EditorialTheme.text(
                                      18,
                                      weight: FontWeight.w700,
                                      color: fg.withValues(alpha: 1.0 - 0.55 * t),
                                      letterSpacing: -0.4,
                                    ).copyWith(
                                      decoration: t > 0.5 ? TextDecoration.lineThrough : TextDecoration.none,
                                      decorationColor: fg.withValues(alpha: 0.35 * t),
                                      decorationThickness: 1.6,
                                    ),
                                  ),
                                  if (metaWidgets.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: metaWidgets,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (goal == null)
                              _weekSquares(habit, day, today, days, fg, accent)
                            else
                              // Los hábitos con meta recuperan su stepper explícito en una cápsula única agrupada.
                              Row(
                                children: [
                                  Container(
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: fg.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: fg.withValues(alpha: 0.10), width: 1.2),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _stepButton(
                                          icon: Icons.remove,
                                          fg: fg,
                                          onTap: () => _handleStep(habit, day, -_incrementFor(habit.goalUnit)),
                                        ),
                                        Container(
                                          width: 1.2,
                                          height: 16,
                                          color: fg.withValues(alpha: 0.12),
                                        ),
                                        _stepButton(
                                          icon: Icons.add,
                                          fg: fg,
                                          onTap: () => _handleStep(habit, day, _incrementFor(habit.goalUnit)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${(habit.completionRate(days: 30) * 100).round()}% este mes',
                                    style: EditorialTheme.text(12, color: fg.withValues(alpha: 0.4)),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );

          return Stack(
            children: [
              // La tarjeta baja para dejarle sitio al botón DENTRO del Stack.
              // Sacarlo con un Positioned de top negativo lo dibuja en el mismo
              // lugar, pero el hit test de un Stack se recorta a su caja: la
              // parte que asoma quedaría muerta al toque.
              Padding(
                padding: const EdgeInsets.only(top: NotchMetrics.overhang),
                child: card,
              ),
              Positioned(
                top: 0,
                right: 0,
                child: _NotchToggle(
                  done: isDone,
                  ratio: ratio,
                  // Con meta, tocar suma un paso y mantener pulsado cierra el
                  // día. El gesto corto es el que se repite; el que salta al
                  // final tiene que costar un poco más.
                  onTap: () =>
                      goal == null ? _toggle(habit, day) : _addProgress(habit, day),
                  onLongPress: () => _toggle(habit, day),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Botón del stepper. El "+" es la acción primaria y va relleno con el acento;
  /// el "−" es la misma pieza en contorno neutro. La jerarquía entre sumar y
  /// restar tiene que verse: se suma muchas veces al día y se resta por error.
  Widget _stepButton({
    required IconData icon,
    required Color fg,
    required VoidCallback onTap,
  }) {
    return _Pressable(
      onTap: onTap,
      scale: 0.86,
      child: SizedBox(
        width: 38,
        height: 30,
        child: Center(
          child: Icon(
            icon,
            size: 15,
            color: fg.withValues(alpha: 0.65),
          ),
        ),
      ),
    );
  }

  /// Paso del stepper. Restar por debajo de cero no tiene sentido y dejaría el
  /// progreso en negativo, así que se corta en el propio gesto.
  Future<void> _handleStep(Habit habit, DateTime day, double delta) async {
    if (delta < 0) {
      final current = habit.dailyProgress[_dateOnly(day)] ?? 0.0;
      if (current <= 0) {
        HapticFeedback.selectionClick();
        return;
      }
      delta = -math.min(-delta, current);
    }
    await _addProgressBy(habit, day, delta);
  }

  /// La semana en cuadraditos, como el grafo de contribuciones. Sólo lectura:
  /// editar días pasados vive en el detalle. Antes cada día era un objetivo
  /// táctil de 22px en una fila apretada, que es como se marca el día
  /// equivocado.
  Widget _weekSquares(
    Habit habit,
    DateTime day,
    DateTime today,
    List<DateTime> days,
    Color fg,
    Color accent,
  ) {
    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          _WeekSquare(
            done: habit.isCompletedOn(days[i]),
            // El aro marca el día que estás EDITANDO, no hoy: cuando te movés
            // al lunes, la fila tiene que decirte dónde estás parado.
            isToday: _isSameDay(days[i], day),
            isFuture: days[i].isAfter(today),
            fg: fg,
            accent: accent,
          ),
        ],
        const Spacer(),
        Text(
          '${(habit.completionRate(days: 30) * 100).round()}% este mes',
          style: EditorialTheme.text(12, color: fg.withValues(alpha: 0.4)),
        ),
      ],
    );
  }

  Widget _emptyState(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(EditorialTheme.margin, 30, EditorialTheme.margin, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: EditorialTheme.text(20, weight: FontWeight.w600, color: EditorialTheme.paper),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: EditorialTheme.text(15, color: EditorialTheme.muted, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _aiCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(EditorialTheme.margin, 22, EditorialTheme.margin, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: EditorialTheme.paper,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'COACH',
                    style: EditorialTheme.label(11, color: EditorialTheme.inkAlpha(0.45)),
                  ),
                ),
                _Pressable(
                  onTap: () => setState(() => _aiFeedback = null),
                  scale: 0.85,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.close, size: 18, color: EditorialTheme.inkAlpha(0.5)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            MarkdownBody(
              data: _aiFeedback!,
              shrinkWrap: true,
              styleSheet: MarkdownStyleSheet(
                p: EditorialTheme.text(15, color: EditorialTheme.inkAlpha(0.8), height: 1.45),
                strong: EditorialTheme.text(
                  15,
                  weight: FontWeight.w700,
                  color: EditorialTheme.ink,
                  height: 1.45,
                ),
                listBullet: EditorialTheme.text(
                  15,
                  color: EditorialTheme.inkAlpha(0.8),
                  height: 1.45,
                ),
                h1: EditorialTheme.caps(18, color: EditorialTheme.ink),
                h2: EditorialTheme.caps(17, color: EditorialTheme.ink),
                h3: EditorialTheme.caps(16, color: EditorialTheme.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════ micro-animaciones ══════════════════════

/// Realce por presión: la pieza se hunde levemente bajo el dedo y vuelve.
///
/// Reemplaza al ripple de Material, que en una superficie plana de dos tonos se
/// ve como una mancha. La escala se aplica al hijo entero, así que sirve igual
/// para una tarjeta (0.985, casi imperceptible pero se siente) que para un
/// botón chico (0.86, donde el gesto tiene que leerse).
class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.scale = 0.96,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        // Bajar rápido y subir con calma: es lo que hace que un botón se sienta
        // físico en vez de elástico.
        duration: Duration(milliseconds: _down ? 90 : 240),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Entrada escalonada de la lista: cada tarjeta aparece con un desfase corto.
///
/// Se anima UNA vez, al montarse. Las filas de un ListView se crean una sola
/// vez y se reutilizan, así que el efecto no se repite al hacer scroll ni al
/// marcar un hábito.
/// Envoltorio de animación unificado para cada tarjeta de hábito:
///
/// 1. **Entrada escalonada (Normal)**: se desliza hacia arriba y se desvanece al cargar.
/// 2. **Colapso (Shrink)**: reduce su tamaño y opacidad a cero cuando se marca listo.
/// 3. **Expansión (Expand)**: crece y se desvanece desde cero al agregarse a hechos.
class _HabitTransitionWrapper extends StatefulWidget {
  const _HabitTransitionWrapper({
    super.key,
    required this.child,
    required this.isShrinking,
    required this.isExpanding,
    required this.index,
  });

  final Widget child;
  final bool isShrinking;
  final bool isExpanding;
  final int index;

  @override
  State<_HabitTransitionWrapper> createState() => _HabitTransitionWrapperState();
}

class _HabitTransitionWrapperState extends State<_HabitTransitionWrapper>
    with TickerProviderStateMixin {
  late final AnimationController _entranceC = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  late final AnimationController _transitionC = AnimationController(
    vsync: this,
    duration: _HabitsTabEditorialState._expandDuration,
    reverseDuration: _HabitsTabEditorialState._collapseDuration,
    value: 1.0,
  );

  late final Animation<double> _entranceCurved = CurvedAnimation(
    parent: _entranceC,
    curve: Curves.easeOutCubic,
  );

  /// Curva enfática: sale despacio, cruza rápido y frena largo al llegar.
  ///
  /// Una `easeInOutCubic` normal reparte la velocidad de forma pareja y a esta
  /// duración eso se siente lento y no fluido — que son cosas distintas. La
  /// enfática gasta el tiempo extra en los extremos, donde el ojo lee el
  /// arranque y la llegada, y no en el medio, donde sólo lee desplazamiento.
  static const Curve _travel = Curves.easeInOutCubicEmphasized;

  late final Animation<double> _transitionCurved = CurvedAnimation(
    parent: _transitionC,
    curve: _travel,
    reverseCurve: _travel,
  );

  @override
  void initState() {
    super.initState();

    if (widget.isExpanding) {
      _entranceC.value = 1.0;
      _transitionC.value = 0.0;
      _transitionC.forward();
    } else if (widget.isShrinking) {
      _entranceC.value = 1.0;
      _transitionC.value = 1.0;
      _transitionC.reverse();
    } else {
      _transitionC.value = 1.0;
      final delayMs = 40 * (widget.index.clamp(0, 6));
      Future<void>.delayed(Duration(milliseconds: delayMs), () {
        if (mounted) _entranceC.forward();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _HabitTransitionWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.isShrinking && !oldWidget.isShrinking) {
      _transitionC.reverse();
    } else if (widget.isExpanding && !oldWidget.isExpanding) {
      _transitionC.forward();
    } else if (!widget.isShrinking && !widget.isExpanding && (oldWidget.isShrinking || oldWidget.isExpanding)) {
      _transitionC.forward();
    }
  }

  @override
  void dispose() {
    _entranceC.dispose();
    _transitionC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_entranceCurved, _transitionCurved]),
      builder: (context, child) {
        final entrance = _entranceCurved.value;
        final t = _transitionCurved.value; // 1 = presente, 0 = colapsada

        // La tarjeta marcada no se desvanece en el sitio: se va HACIA ABAJO,
        // que es adonde de verdad viaja, y reaparece en "Hechos" llegando desde
        // arriba. Colapsar la altura sin desplazar nada describe una tarjeta
        // que se apaga, no una que se muda; el par de traslaciones es lo que
        // convierte dos animaciones separadas en un solo movimiento continuo a
        // través del corte entre las dos listas.
        var yOffset = 12 * (1 - entrance);
        if (widget.isShrinking) {
          yOffset += 26 * (1 - t);
        } else if (widget.isExpanding) {
          yOffset -= 22 * (1 - t);
        }

        // La opacidad se queda atrás respecto del tamaño (raíz cuadrada): si
        // cae a la par, la tarjeta ya es invisible a mitad del recorrido y el
        // desplazamiento no se llega a ver.
        final opacity = entrance * math.sqrt(t.clamp(0.0, 1.0));

        return SizeTransition(
          sizeFactor: _transitionCurved,
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, yOffset),
                child: child,
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// El bloque del icono: identidad del hábito y medidor a la vez.
///
/// Carga con dos trabajos:
///
///  - **Identidad.** El glifo a 26px sobre una superficie propia se reconoce de
///    un vistazo en una lista larga, cosa que un icono de 20px suelto sobre el
///    papel no consigue.
///  - **Medida.** Para los hábitos con meta, el gris sube desde abajo con la
///    fracción del día que llevás. El bloque dice cuánto falta sin escribirlo.
///
/// **El bloque es gris siempre, en todas las tarjetas.** No se tiñe del color
/// del hábito ni al completarlo. Antes el bloque, el chip, los cuadraditos y la
/// llama llevaban todos el acento, y cuatro sitios con el mismo color no son un
/// acento: son un tema. En esta pantalla el color sobrevive en un solo sitio,
/// los cuadraditos de la semana, porque ahí es dato —qué días sí y qué días
/// no— y no decoración. Todo lo demás es la escala neutra.
///
/// El bloque no lleva estado, y eso es a propósito: dice **qué** hábito es, no
/// cómo va. El estado vive en el chip de la esquina, en el tachado del título y
/// en los cuadraditos. Repetirlo aquí era lo que obligaba a meterle color.
///
/// El gris es claro y no oscuro por una razón concreta: el bloque toca el filo
/// izquierdo de la tarjeta, que a su vez toca el lienzo casi negro. Un bloque
/// oscuro se funde con el fondo y la tarjeta parece empezar 64px más a la
/// derecha, con el glifo flotando fuera de ella.
class _IconBlock extends StatelessWidget {
  const _IconBlock({
    required this.icon,
    required this.ratio,
  });

  final IconData icon;

  /// Avance del día para hábitos con meta, 0–1. Sin meta va en 0.
  final double ratio;

  /// Ancho del bloque. Suficiente para que el glifo respire a 26px; más ancho
  /// y empieza a comerse el título en pantallas chicas.
  static const double width = 64;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: EditorialTheme.gray)),
          // El avance sube en el escalón siguiente de la misma escala. Dos
          // grises vecinos bastan para leer un nivel; un salto mayor convertiría
          // el bloque en un gráfico y le robaría el sitio al glifo.
          if (ratio > 0)
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: ratio),
                  duration: const Duration(milliseconds: 340),
                  curve: EditorialTheme.curve,
                  builder: (context, v, _) => FractionallySizedBox(
                    heightFactor: v,
                    child: const ColoredBox(color: EditorialTheme.grayStrong),
                  ),
                ),
              ),
            ),
          Center(
            child: Icon(icon, size: 26, color: EditorialTheme.ink),
          ),
        ],
      ),
    );
  }
}

/// El botón de completar, apoyado en el mordisco de la esquina.
///
/// Pendiente es oscuro —del mismo material que el lienzo, un escalón arriba—
/// y no blanco como la tarjeta. La tentación era pintarlo de papel para
/// reforzar el "salió de la tarjeta", pero eso pone una columna de cuadrados
/// blancos brillantes en el borde derecho de la lista, y esos cuadrados pesan
/// más que los hábitos. El mordisco ya cuenta esa historia solo.
///
/// Lo que sí lleva color desde el principio es la **marca**. Con el aro en
/// blanco al 28% sobre un chip casi negro no había contraste para verla de
/// reojo, que es como se mira esta pantalla; y subir ese blanco lo único que
/// hacía era devolverle al botón el peso que se le acababa de quitar. Con el
/// acento del hábito el aro salta sin necesidad de ser más grande ni más claro,
/// y de paso adelanta de qué color se va a poner el chip al marcarlo: la
/// transición deja de ser un cambio de color y pasa a ser el mismo color
/// llenándose.
///
/// Es la única concesión a la regla de que el color vive sólo en el bloque del
/// icono. Se la gana porque el aro es la pieza que dice "esto se puede tocar".
class _NotchToggle extends StatefulWidget {
  const _NotchToggle({
    required this.done,
    required this.ratio,
    required this.onTap,
    required this.onLongPress,
  });

  final bool done;
  final double ratio;

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_NotchToggle> createState() => _NotchToggleState();
}

class _NotchToggleState extends State<_NotchToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant _NotchToggle old) {
    super.didUpdateWidget(old);
    // Sólo al marcar. Desmarcar es una corrección, no un logro: no merece
    // rebote.
    if (widget.done && !old.done) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: EditorialTheme.curve,
      width: NotchMetrics.buttonWidth,
      height: NotchMetrics.buttonHeight,
      decoration: BoxDecoration(
        // Con el bloque del icono ya neutro, el chip es lo único que queda para
        // decir "hecho", y lo dice sin color: invierte. Apagado es el mismo gris
        // que el bloque; marcado es tinta plena con el check en blanco, que es
        // el contraste más alto que hay en la escala. Un chip de color decía lo
        // mismo pero volvía a meter el acento en una segunda pieza.
        color: widget.done ? EditorialTheme.ink : EditorialTheme.gray,
        borderRadius: BorderRadius.circular(NotchMetrics.buttonRadius),
        // El filete sólo existe apagado: es lo que separa el chip del papel de
        // la tarjeta al otro lado del canal, que si no son casi el mismo valor.
        // Con tinta plena encima ya no hace falta.
        border: widget.done
            ? null
            : Border.all(color: EditorialTheme.grayStrong, width: 1.2),
      ),
      child: Center(
        child: widget.done
            ? const Icon(Icons.check_rounded, size: 22, color: EditorialTheme.paper)
            : _pendingMark(),
      ),
    );

    return _Pressable(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      // Recorrido corto. El botón sólo tiene [NotchMetrics.gap] píxeles de
      // holgura en su hueco: un hundido profundo abriría el mordisco entero por
      // un instante y la pieza parecería caerse de la tarjeta en vez de
      // hundirse en ella.
      scale: 0.93,
      // El rectángulo mide 52×40 pero el objetivo del dedo crece
      // [NotchMetrics.touchPad] hacia adentro de la tarjeta. Por eso se alinea
      // arriba a la derecha de su caja en vez de centrarse: es lo que lo deja
      // calzado en el mordisco mientras el área táctil se derrama hacia el otro
      // lado.
      child: SizedBox(
        width: NotchMetrics.buttonWidth + NotchMetrics.touchPad,
        height: NotchMetrics.buttonHeight + NotchMetrics.touchPad,
        child: Align(
          alignment: Alignment.topRight,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.62, end: 1.0).animate(
              CurvedAnimation(parent: _pop, curve: Curves.elasticOut),
            ),
            child: body,
          ),
        ),
      ),
    );
  }

  /// Marca de estado apagado: un aro vacío, o el mismo aro llenándose desde
  /// abajo cuando el hábito tiene meta y ya lleva avance. Repite el gesto del
  /// bloque de la izquierda a escala chica, así el botón y el bloque cuentan lo
  /// mismo desde los dos extremos de la tarjeta.
  Widget _pendingMark() {
    const size = 18.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Gris de texto de la escala, opaco. El problema de contraste que
        // tenía el aro no era su color sino su alfa: en blanco al 28% sobre un
        // chip claro literalmente no había nada que ver. Un gris sólido de la
        // escala se lee de reojo sin necesitar color ni más grosor.
        border: Border.all(color: EditorialTheme.grayText, width: 2),
      ),
      child: widget.ratio > 0
          ? ClipOval(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: widget.ratio),
                  duration: const Duration(milliseconds: 340),
                  curve: EditorialTheme.curve,
                  builder: (context, v, _) => FractionallySizedBox(
                    heightFactor: v,
                    child: ColoredBox(color: EditorialTheme.grayText),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}


/// Métricas agregadas del panel.
class _HabitStats {
  const _HabitStats(this.streak, this.week, this.month);
  final int streak;
  final int week;
  final int month;
}

/// Mapa de calor: seis semanas de historia en siete columnas.
///
/// Es el elemento firma de la pantalla — lo que hace que una captura sea
/// reconocible sin leer una palabra, y lo que premia mirar la app el día 60 con
/// algo que el día 1 no existía.
///
/// Las columnas son días de la semana y están alineadas con el selector de
/// abajo: lunes sobre lunes. Así la pieza se lee como una sola —historia arriba
/// en pequeño, presente abajo en grande— y no como dos widgets apilados.
///
/// Las celdas son rectángulos y no cuadrados a propósito: con siete columnas
/// ocupando el ancho del panel, un cuadrado obligaría a un bloque de casi 300px
/// de alto. El ladrillo ancho conserva la lectura de rejilla sin comerse la
/// pantalla.
class _HeatMap extends StatelessWidget {
  const _HeatMap({required this.habits, required this.today});

  final List<Habit> habits;
  final DateTime today;

  static const int _weeks = 6;

  /// Altura de la celda. Estirarla al ancho de la columna crea un ladrillo
  /// horizontal que conserva la lectura de rejilla y la alineación perfecta
  /// con los chips semanales de abajo.
  static const double _cellHeight = 13;

  /// El MISMO gap que el selector de día. No es un detalle de gusto: si los dos
  /// no comparten separación, las columnas dejan de caer sobre sus chips y la
  /// pieza se parte en dos widgets apilados en vez de leerse como una.
  static const double _gap = EditorialTheme.dayGap;

  /// Escalones discretos en vez de una rampa continua: el ojo no distingue 40%
  /// de 45% de opacidad, pero sí distingue "nada", "a medias" y "completo".
  ///
  /// El reparto es deliberadamente desparejo. Repartir el rango en partes
  /// iguales amontona los escalones intermedios —0.28 y 0.50 se ven casi igual
  /// a 15px— y desperdicia los extremos. Estos valores están separados por
  /// saltos crecientes, que es como el ojo distingue luminosidad de verdad.
  double _alphaFor(DateTime day) {
    if (day.isAfter(today)) return 0.035;

    var active = 0, done = 0;
    for (final h in habits) {
      if (!h.isActiveOn(day)) continue;
      active++;
      if (h.isCompletedOn(day)) done++;
    }
    // Día sin nada programado: casi invisible, pero presente. No es lo mismo
    // "no tocaba" que "tocaba y no lo hice".
    if (active == 0) return 0.045;

    // La escala está sesgada hacia abajo a propósito: los escalones parciales
    // se agrupan en la zona clara y el día perfecto se queda solo arriba. Con
    // un reparto parejo, los grises medios dominan el mapa y los días completos
    // —lo único que de verdad querés ver de un vistazo— se pierden entre ellos.
    final ratio = done / active;
    if (ratio <= 0) return 0.10;
    if (ratio < 0.34) return 0.20;
    if (ratio < 0.67) return 0.36;
    if (ratio < 1) return 0.58;
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    // Primer día de la ventana visible: el selector muestra los últimos siete
    // terminando hoy, así que el mapa cuenta hacia atrás desde ahí de siete en
    // siete. Al saltar en múltiplos de 7, la columna `d` cae siempre en el
    // mismo día de la semana que el chip `d` de abajo, y la alineación se
    // mantiene sin depender del calendario.
    final windowStart = today.subtract(const Duration(days: 6));

    return Column(
      children: [
        for (var w = _weeks; w >= 1; w--) ...[
          if (w < _weeks) const SizedBox(height: _gap),
          Row(
            children: [
              for (var d = 0; d < 7; d++) ...[
                if (d > 0) const SizedBox(width: _gap),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final cellDate = windowStart.subtract(Duration(days: 7 * w - d));
                      final alpha = _alphaFor(cellDate);
                      return Container(
                        height: _cellHeight,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: EditorialTheme.inkAlpha(alpha),
                        ),
                        child: alpha == 1.0
                            ? Container(
                                width: 3.0,
                                height: 3.0,
                                decoration: BoxDecoration(
                                  color: EditorialTheme.paper,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// Un día en el selector: inicial arriba, número de mes abajo.
///
/// Vive DENTRO del panel crema, así que su paleta está invertida respecto del
/// resto de la pantalla: aquí la tinta es el negro y el resalte es el relleno
/// oscuro, no el claro.
class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.letter,
    required this.dayOfMonth,
    required this.selected,
    required this.isToday,
    required this.isFuture,
    required this.ratio,
    required this.onTap,
  });

  final String letter;
  final int dayOfMonth;
  final bool selected;
  final bool isToday;
  final bool isFuture;

  /// Proporción de hábitos completados ese día, 0–1. Es lo que llena el vaso.
  final double ratio;

  final VoidCallback onTap;

  /// La cara del chip. Se dibuja DOS veces —en tinta sobre el vaso vacío y en
  /// crema sobre el líquido— y la segunda copia se recorta a la altura del
  /// relleno. Es lo que hace que el texto siga siendo legible cuando el nivel
  /// del agua lo cruza por la mitad, sin recurrir a sombras ni contornos.
  Widget _face(Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          letter,
          style: EditorialTheme.text(
            11,
            weight: FontWeight.w600,
            color: color.withValues(alpha: color.a * 0.6),
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '$dayOfMonth',
              style: EditorialTheme.text(
                17,
                weight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
                letterSpacing: -0.3,
              ),
            ),
            if (ratio == 1.0) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.check,
                size: 9.5,
                color: color,
              ),
            ],
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(EditorialTheme.radiusChip);

    return _Pressable(
      onTap: onTap,
      scale: 0.92,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 52,
            child: ClipRRect(
              borderRadius: radius,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: ratio.clamp(0.0, 1.0)),
                // Lento a propósito: el vaso llenándose es el acuse de que
                // completaste algo, y a 250ms no se llega a ver.
                duration: const Duration(milliseconds: 620),
                curve: Curves.easeOutCubic,
                builder: (context, level, _) => Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: EditorialTheme.inkAlpha(0.07)),
                    Center(child: _face(EditorialTheme.ink)),
                    ClipRect(
                      clipper: _BottomFraction(level),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: EditorialTheme.ink),
                          Center(child: _face(EditorialTheme.paper)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Punto de selección, fuera del chip.
          //
          // El aro que lo rodeaba competía con el nivel del vaso: dos señales
          // sobre la misma pieza, una diciendo "elegido" y otra "completado".
          // Sacando la marca afuera, el chip queda libre para decir una sola
          // cosa y la selección se lee igual de rápido.
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            width: selected ? 14 : 4,
            height: 3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(1.5),
              color: selected ? EditorialTheme.ink : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Recorta a la franja inferior de altura `fraction`. Es el nivel del líquido.
class _BottomFraction extends CustomClipper<Rect> {
  const _BottomFraction(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
        0,
        size.height * (1 - fraction),
        size.width,
        size.height,
      );

  @override
  bool shouldReclip(_BottomFraction oldClipper) => oldClipper.fraction != fraction;
}

/// Un día de la semana como cuadradito de contribución.
class _WeekSquare extends StatelessWidget {
  const _WeekSquare({
    required this.done,
    required this.isToday,
    required this.isFuture,
    required this.fg,
    required this.accent,
  });

  final bool done;
  final bool isToday;
  final bool isFuture;
  final Color fg;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: EditorialTheme.curve,
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4.5),
        // El día hecho lleva el color del hábito; el vacío se queda en tinta
        // neutra. Así el color sólo aparece donde significa algo, y una fila de
        // siete casillas no se convierte en siete manchas.
        //
        // Una casilla vacía igual tiene que LEERSE como casilla: si desaparece,
        // la fila deja de ser un grafo y pasa a ser un punto suelto. El futuro
        // es más tenue que un día pasado sin hacer, pero sigue presente.
        color: done ? accent : fg.withValues(alpha: isFuture ? 0.08 : 0.18),
        border: isToday && !done
            ? Border.all(color: accent.withValues(alpha: 0.5), width: 1.2)
            : null,
      ),
      child: isToday && !done
          ? Center(
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
            )
          : null,
    );
  }
}

/// Widget animado que dibuja una llama minimalista con CustomPainter.
/// La complejidad y movimiento de la llama escalan con la racha.
class MinimalFlame extends StatefulWidget {
  const MinimalFlame({
    super.key,
    required this.streak,
    required this.color,
    this.size = 14.0,
  });

  final int streak;
  final Color color;
  final double size;

  @override
  State<MinimalFlame> createState() => _MinimalFlameState();
}

class _MinimalFlameState extends State<MinimalFlame> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final int speedMs = widget.streak >= 30 ? 600 : (widget.streak >= 10 ? 800 : 1000);
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: speedMs),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant MinimalFlame oldWidget) {
    super.didUpdateWidget(oldWidget);
    final int oldSpeed = oldWidget.streak >= 30 ? 600 : (oldWidget.streak >= 10 ? 800 : 1000);
    final int newSpeed = widget.streak >= 30 ? 600 : (widget.streak >= 10 ? 800 : 1000);
    if (oldSpeed != newSpeed) {
      _controller.duration = Duration(milliseconds: newSpeed);
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.streak <= 0) return const SizedBox.shrink();
    
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size(widget.size, widget.size * 1.3),
          painter: FlamePainter(
            animationValue: _controller.value,
            streak: widget.streak,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class FlamePainter extends CustomPainter {
  FlamePainter({
    required this.animationValue,
    required this.streak,
    required this.color,
  });

  final double animationValue;
  final int streak;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    int level = 1;
    if (streak >= 40) {
      level = 5;
    } else if (streak >= 30) {
      level = 4;
    } else if (streak >= 10) {
      level = 3;
    } else if (streak >= 5) {
      level = 2;
    }

    final double w = size.width;
    final double h = size.height;

    void drawFlameLayer(Canvas canvas, Rect bounds, double scale, double phaseShift) {
      final layerW = bounds.width * scale;
      final layerH = bounds.height * scale;
      final centerX = bounds.left + bounds.width / 2;
      final bottomY = bounds.bottom;

      final path = Path();
      final double wave = math.sin((animationValue + phaseShift) * 2 * math.pi);
      final double tipX = centerX + wave * (layerW * 0.15);
      final double tipY = bottomY - layerH + (math.cos((animationValue + phaseShift) * 3 * math.pi) * (layerH * 0.05));

      final double leftControlX = centerX - layerW * 0.5 + wave * (layerW * 0.05);
      final double rightControlX = centerX + layerW * 0.5 - wave * (layerW * 0.05);

      path.moveTo(centerX, bottomY);
      path.cubicTo(
        leftControlX, bottomY,
        centerX - layerW * 0.45, bottomY - layerH * 0.6,
        tipX, tipY,
      );
      path.cubicTo(
        centerX + layerW * 0.45, bottomY - layerH * 0.6,
        rightControlX, bottomY,
        centerX, bottomY,
      );
      path.close();

      canvas.drawPath(path, paint);
    }

    final Rect baseRect = Rect.fromLTWH(0, 0, w, h);

    if (level == 1) {
      paint.color = color.withValues(alpha: 0.85);
      drawFlameLayer(canvas, baseRect, 0.75, 0.0);
    } else if (level == 2) {
      paint.color = color.withValues(alpha: 0.4);
      drawFlameLayer(canvas, baseRect, 0.9, 0.0);
      paint.color = color;
      drawFlameLayer(canvas, baseRect, 0.6, 0.25);
    } else if (level == 3) {
      paint.color = color.withValues(alpha: 0.45);
      drawFlameLayer(canvas, baseRect, 1.0, 0.0);
      paint.color = color;
      drawFlameLayer(canvas, baseRect, 0.68, 0.3);
    } else if (level == 4) {
      paint.color = color.withValues(alpha: 0.3);
      drawFlameLayer(canvas, baseRect, 1.05, 0.0);
      paint.color = color.withValues(alpha: 0.6);
      drawFlameLayer(canvas, baseRect, 0.78, 0.2);
      paint.color = color;
      drawFlameLayer(canvas, baseRect, 0.52, 0.4);
    } else {
      paint.color = color.withValues(alpha: 0.3);
      drawFlameLayer(canvas, baseRect, 1.15, 0.0);
      paint.color = color.withValues(alpha: 0.65);
      drawFlameLayer(canvas, baseRect, 0.86, 0.25);
      paint.color = color;
      drawFlameLayer(canvas, baseRect, 0.58, 0.5);

      final sparkPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      for (int i = 0; i < 3; i++) {
        final double sparkProgress = (animationValue + i / 3.0) % 1.0;
        final double sparkY = baseRect.bottom - baseRect.height * 0.65 - (sparkProgress * baseRect.height * 0.55);
        final double sparkX = baseRect.left + baseRect.width / 2 + 
            math.sin(sparkProgress * 4 * math.pi + i) * (baseRect.width * 0.22);
        final double sparkSize = 2.4 * (1.0 - sparkProgress);
        canvas.drawCircle(Offset(sparkX, sparkY), sparkSize, sparkPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant FlamePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue || 
           oldDelegate.streak != streak || 
           oldDelegate.color != color;
  }
}
