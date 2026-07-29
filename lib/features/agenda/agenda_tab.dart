import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/habit_model.dart';
import '../../core/models/task_model.dart';
import '../../core/providers/day_plan_provider.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/providers/tasks_provider.dart';
import '../../core/theme/bento_theme.dart';
import 'quick_parse.dart';
import 'timeline_scale.dart';
import 'task_form_dialog.dart';
import 'widgets/day_strip.dart';
import 'widgets/day_timeline.dart';
import 'widgets/habit_tray.dart';
import 'night_planning/night_planning_screen.dart';
import 'widgets/quick_add_bar.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Ventana de vigilia con la que se calcula cuánto queda libre. No pretende
/// ser exacta: es la referencia para avisar cuando el día ya está demasiado
/// lleno, que es la causa número uno de abandonar un sistema de planeación.
const _wakingStartHour = 7;
const _wakingEndHour = 23;
const _overbookedRatio = 0.7;

/// A partir de esta hora la Agenda propone planear mañana.
const _planPromptHour = 20;

class AgendaTab extends ConsumerStatefulWidget {
  const AgendaTab({super.key});

  @override
  ConsumerState<AgendaTab> createState() => _AgendaTabState();
}

class _AgendaTabState extends ConsumerState<AgendaTab> {
  DateTime _selectedDay = _dateOnly(DateTime.now());

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
        backgroundColor: BentoTheme.darkCardAlt,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _createBlock(String title, DateTime start, DateTime end) async {
    final notifier = ref.read(tasksProvider.notifier);
    await notifier.addTask(
      title: title,
      dueDate: _selectedDay,
      startAt: start,
      endAt: end,
      // Un plan sin aviso es un plan que se olvida: el recordatorio a la hora
      // de inicio es lo que convierte la intención en acción. Se puede quitar
      // desde el formulario del bloque.
      remindAt: start,
      plannedAt: DateTime.now(),
    );
    final error = notifier.takeSyncError();
    if (error != null) _showMessage(error);
  }

  Future<void> _reschedule(Task task, DateTime start, DateTime end) async {
    final notifier = ref.read(tasksProvider.notifier);
    await notifier.updateTask(task.copyWith(
      startAt: start,
      endAt: end,
      // El recordatorio sigue al bloque; si no tenía, no se le inventa uno.
      remindAt: task.hasReminder ? start : null,
      clearReminder: !task.hasReminder,
    ));
    final error = notifier.takeSyncError();
    if (error != null) _showMessage(error);
  }

  /// Hora en la que cae un bloque que no dice a qué hora va: justo después de
  /// lo último planeado, o la hora en curso si el día está vacío. Elegir bien
  /// este valor es lo que permite escribir solo el nombre y seguir.
  int _suggestedStartMinutes(List<Task> dayTasks) {
    if (dayTasks.isNotEmpty) {
      final lastEnd = dayTasks
          .map((t) => endMinutesOf(t))
          .reduce((a, b) => a > b ? a : b);
      if (lastEnd < TimelineScale.minutesPerDay - 15) return TimelineScale.snap(lastEnd);
    }
    final isToday = _selectedDay == _dateOnly(DateTime.now());
    if (isToday) return TimelineScale.snap(minutesOfDay(DateTime.now()));
    return _wakingStartHour * 60 + 60;
  }

  Future<void> _createFromQuickAdd(ParsedBlock parsed) async {
    // El desplazamiento de día que trae la línea ("dentista mañana 10:00") se
    // aplica sobre el día que estás mirando, no sobre hoy.
    final day = _dateOnly(_selectedDay.add(Duration(days: parsed.dayOffset)));
    final startMinutes = parsed.startMinutes ?? _suggestedStartMinutes(
      ref.read(tasksProvider.notifier).tasksForDay(day),
    );
    final start = day.add(Duration(minutes: startMinutes));
    final end = start.add(Duration(minutes: parsed.durationMinutes ?? 30));

    final notifier = ref.read(tasksProvider.notifier);
    await notifier.addTask(
      title: parsed.title,
      dueDate: day,
      startAt: start,
      endAt: end,
      remindAt: start,
      priority: parsed.priority,
      blockType: parsed.blockType ?? BlockType.task,
      location: parsed.location,
      plannedAt: DateTime.now(),
    );
    final error = notifier.takeSyncError();
    if (error != null) _showMessage(error);

    // Si el bloque cayó en otro día, saltamos allí: es lo que se acaba de
    // planear y quedarse mirando el día anterior sería desconcertante.
    if (parsed.dayOffset != 0 && mounted) {
      setState(() => _selectedDay = day);
    }
  }

  // ------------------------------------------------------------- hábitos

  /// Hábitos que tocan el día seleccionado y todavía no tienen bloque.
  List<Habit> _pendingHabits(List<Task> dayTasks) {
    final placed = dayTasks.map((t) => t.habitId).whereType<String>().toSet();
    return ref
        .read(habitsProvider)
        .where((h) => !h.archived && h.isActiveOn(_selectedDay) && !placed.contains(h.id))
        .toList();
  }

  /// Hora habitual del hábito, si la tiene guardada como recordatorio.
  int? _usualMinutesOf(Habit habit) {
    if (habit.reminderTimes.isNotEmpty) {
      final parts = habit.reminderTimes.first.split(':');
      if (parts.length == 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) return h * 60 + m;
      }
    }
    if (habit.reminderHour != null && habit.reminderMinute != null) {
      return habit.reminderHour! * 60 + habit.reminderMinute!;
    }
    return null;
  }

  /// Dónde colocar un hábito que no trae hora habitual.
  ///
  /// Se ancla al final del bloque fijo más cercano en lugar de buscar el
  /// primer hueco cualquiera: encadenar un hábito nuevo a algo que ya haces
  /// sin pensar ("después de desayunar") es lo que lo sostiene los primeros
  /// días, cuando todavía no hay costumbre que lo empuje.
  int _anchorMinutesFor(List<Task> dayTasks) {
    if (dayTasks.isEmpty) return _wakingStartHour * 60 + 60;
    final lastEnd = dayTasks.map(endMinutesOf).reduce((a, b) => a > b ? a : b);
    if (lastEnd >= TimelineScale.minutesPerDay - 30) return _wakingStartHour * 60;
    return TimelineScale.snap(lastEnd);
  }

  Future<void> _placeHabit(Habit habit, {int? atMinutes}) async {
    final dayTasks = ref.read(tasksProvider.notifier).tasksForDay(_selectedDay);
    final usual = _usualMinutesOf(habit);
    final minutes = atMinutes ?? usual ?? _anchorMinutesFor(dayTasks);
    final start = _selectedDay.add(Duration(minutes: minutes));

    // Si el bloque queda a la hora habitual del hábito, el recordatorio del
    // propio hábito ya suena a esa hora: añadir el del bloque haría sonar dos
    // notificaciones en el mismo minuto. Solo se pone aviso propio cuando el
    // bloque se coloca a una hora distinta de la de siempre.
    final needsOwnReminder = usual == null || minutes != usual;

    await ref.read(tasksProvider.notifier).addTask(
          title: habit.name,
          dueDate: _selectedDay,
          startAt: start,
          endAt: start.add(const Duration(minutes: 30)),
          remindAt: needsOwnReminder ? start : null,
          habitId: habit.id,
          blockType: BlockType.habit,
          plannedAt: DateTime.now(),
        );
  }

  Future<void> _placeAllHabitsWithUsualTime() async {
    final dayTasks = ref.read(tasksProvider.notifier).tasksForDay(_selectedDay);
    final toPlace = _pendingHabits(dayTasks).where((h) => _usualMinutesOf(h) != null).toList();
    for (final habit in toPlace) {
      await _placeHabit(habit);
    }
    if (mounted && toPlace.isNotEmpty) {
      _showMessage('Colocados ${toPlace.length} hábitos en su hora de siempre.');
    }
  }

  /// Para un bloque de hábito la verdad vive en el hábito (`habit_logs`), no en
  /// `task.completed`. Manteniendo una sola fuente no hay dos estados que
  /// puedan discrepar, y marcar desde el timeline o desde la pestaña Hábitos
  /// es exactamente lo mismo.
  bool _isBlockCompleted(Task task) {
    final habitId = task.habitId;
    if (habitId == null) return task.completed;
    final habits = ref.read(habitsProvider);
    final index = habits.indexWhere((h) => h.id == habitId);
    // Si el hábito ya no existe, el bloque vuelve a valerse por sí mismo.
    if (index == -1) return task.completed;
    return habits[index].isCompletedOn(task.dueDate);
  }

  Future<void> _toggleBlock(Task task) async {
    final habitId = task.habitId;
    if (habitId == null) {
      await ref.read(tasksProvider.notifier).toggleComplete(task.id);
      return;
    }
    await ref.read(habitsProvider.notifier).toggleHabit(habitId, task.dueDate);
  }

  Future<void> _copyDay({required int daysBack}) async {
    final source = _dateOnly(_selectedDay.subtract(Duration(days: daysBack)));
    final notifier = ref.read(tasksProvider.notifier);
    final copied = await notifier.copyDay(from: source, to: _selectedDay);
    if (!mounted) return;
    final error = notifier.takeSyncError();
    if (error != null) {
      _showMessage(error);
    } else {
      _showMessage(copied == 0
          ? 'No había bloques que copiar de ese día.'
          : 'Copiados $copied bloques.');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(tasksProvider);
    // Se observa también para que marcar un hábito desde su propia pestaña
    // repinte aquí el bloque correspondiente.
    ref.watch(habitsProvider);
    final dayTasks = ref.read(tasksProvider.notifier).tasksForDay(_selectedDay);
    final pendingHabits = _pendingHabits(dayTasks);
    final accent = BentoTheme.accentLime;

    return Container(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(dayTasks),
          DayStrip(
            selectedDay: _selectedDay,
            accentColor: accent,
            onSelect: (day) => setState(() => _selectedDay = day),
          ),
          ?_buildPlanTomorrowBanner(),
          _buildLoadBar(dayTasks),
          HabitTray(
            pending: pendingHabits,
            withUsualTime: pendingHabits.where((h) => _usualMinutesOf(h) != null).length,
            onPlace: (habit) => _placeHabit(habit),
            onPlaceAll: _placeAllHabitsWithUsualTime,
          ),
          QuickAddBar(
            // Sin hora explícita, el bloque cae en el siguiente cuarto de hora
            // libre y no a medianoche.
            fallbackStartMinutes: _suggestedStartMinutes(dayTasks),
            onSubmit: _createFromQuickAdd,
          ),
          Expanded(
            child: Stack(
              children: [
                DayTimeline(
                  // La key fuerza un timeline nuevo por día: así cada día
                  // arranca en su propia hora relevante y no hereda el scroll
                  // ni un borrador a medias del día anterior.
                  key: ValueKey(_selectedDay),
                  day: _selectedDay,
                  tasks: dayTasks,
                  onCreate: _createBlock,
                  onReschedule: _reschedule,
                  isCompleted: _isBlockCompleted,
                  onTapBlock: (task) => showTaskFormDialog(context, ref, day: _selectedDay, existing: task),
                  onToggleBlock: _toggleBlock,
                ),
                if (dayTasks.isEmpty) _buildEmptyHint(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<int> _copyMenuItem(int daysBack, String label) {
    return PopupMenuItem(
      value: daysBack,
      child: Text(
        label,
        style: GoogleFonts.montserrat(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: BentoTheme.cream,
        ),
      ),
    );
  }

  /// Invitación a planear mañana, a partir de la tarde y solo si mañana no
  /// está planeado.
  ///
  /// El disparador es la hora del día y no un "siempre visible" porque un
  /// aviso permanente se vuelve invisible en una semana. Aparece cuando de
  /// verdad toca, y desaparece en cuanto el ritual está hecho.
  Widget? _buildPlanTomorrowBanner() {
    final now = DateTime.now();
    if (now.hour < _planPromptHour) return null;

    final tomorrow = _dateOnly(now.add(const Duration(days: 1)));
    ref.watch(dayPlansProvider);
    if (ref.read(dayPlansProvider.notifier).hasPlanFor(tomorrow)) return null;

    final streak = ref.read(dayPlansProvider.notifier).planningStreak;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: GestureDetector(
        onTap: _openNightPlanning,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: BentoTheme.accentPurple.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: BentoTheme.accentPurple.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.nights_stay_outlined, size: 19, color: BentoTheme.accentPurple),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Planea mañana',
                      style: GoogleFonts.montserrat(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: BentoTheme.cream,
                      ),
                    ),
                    Text(
                      streak > 1
                          ? '$streak noches seguidas. No la rompas.'
                          : 'Dos minutos ahora, mañana sin improvisar.',
                      style: GoogleFonts.montserrat(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: BentoTheme.creamAlpha(0.55),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, size: 18, color: BentoTheme.accentPurple),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openNightPlanning() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NightPlanningScreen()),
    );
    if (!mounted) return;
    // Al volver, saltamos al día que se acaba de planear: es lo que se quiere
    // ver, y confirma de un vistazo que quedó guardado.
    setState(() => _selectedDay = _dateOnly(DateTime.now().add(const Duration(days: 1))));
  }

  Widget _buildEmptyHint() {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 60, 40, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined, size: 30, color: BentoTheme.creamAlpha(0.25)),
              const SizedBox(height: 10),
              Text(
                'Mantén y arrastra sobre una hora\npara crear un bloque',
                textAlign: TextAlign.center,
                style: GoogleFonts.montserrat(
                  color: BentoTheme.creamAlpha(0.4),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Cuánto del día está comprometido. Sobreplanificar es lo que rompe el
  /// hábito de planear, así que el contador está para frenar, no para animar
  /// a llenar más.
  Widget _buildLoadBar(List<Task> dayTasks) {
    if (dayTasks.isEmpty) return const SizedBox(height: 8);

    final plannedMinutes = dayTasks.fold<int>(0, (sum, t) => sum + (t.durationMinutes ?? 40));
    final availableMinutes = (_wakingEndHour - _wakingStartHour) * 60;
    final ratio = (plannedMinutes / availableMinutes).clamp(0.0, 1.0);
    final overbooked = ratio > _overbookedRatio;
    final freeMinutes = (availableMinutes - plannedMinutes).clamp(0, availableMinutes);

    String fmtHours(int minutes) {
      final h = minutes / 60;
      return h % 1 == 0 ? '${h.toInt()}h' : '${h.toStringAsFixed(1)}h';
    }

    final barColor = overbooked ? BentoTheme.accentOrange : BentoTheme.accentLime;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '${fmtHours(plannedMinutes)} planeadas',
                style: GoogleFonts.montserrat(fontSize: 11.5, fontWeight: FontWeight.w700, color: BentoTheme.creamAlpha(0.65)),
              ),
              Text(
                '  ·  ${fmtHours(freeMinutes)} libres',
                style: GoogleFonts.montserrat(fontSize: 11.5, fontWeight: FontWeight.w500, color: BentoTheme.creamAlpha(0.4)),
              ),
              const Spacer(),
              if (overbooked)
                Text(
                  'día muy lleno',
                  style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.w700, color: BentoTheme.accentOrange),
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
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(List<Task> dayTasks) {
    final completed = dayTasks.where(_isBlockCompleted).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Agenda',
            style: GoogleFonts.montserrat(
              fontWeight: FontWeight.w800,
              fontSize: 34,
              height: 0.92,
              letterSpacing: -1.0,
              color: BentoTheme.cream,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dayTasks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    '$completed/${dayTasks.length}',
                    style: GoogleFonts.montserrat(fontSize: 13, fontWeight: FontWeight.w700, color: BentoTheme.creamAlpha(0.5)),
                  ),
                ),
              PopupMenuButton<int>(
                tooltip: 'Copiar un día',
                color: BentoTheme.darkCard,
                onSelected: (daysBack) => _copyDay(daysBack: daysBack),
                itemBuilder: (context) => [
                  _copyMenuItem(1, 'Copiar el día anterior'),
                  _copyMenuItem(7, 'Copiar el mismo día de la semana pasada'),
                ],
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.copy_all_outlined, size: 19, color: BentoTheme.creamAlpha(0.55)),
                ),
              ),
              NeuCard(
                onTap: () => showTaskFormDialog(context, ref, day: _selectedDay),
                borderRadius: 100,
                distance: 3,
                blur: 6,
                color: BentoTheme.accentLime,
                padding: const EdgeInsets.all(10),
                child: const Icon(Icons.add, size: 18, color: Color(0xFF0C0C0D)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
