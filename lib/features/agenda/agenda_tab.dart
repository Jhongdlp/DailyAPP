import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/task_model.dart';
import '../../core/providers/tasks_provider.dart';
import '../../core/theme/bento_theme.dart';
import 'task_form_dialog.dart';
import 'widgets/day_strip.dart';
import 'widgets/timeline_task_card.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

const double _hourHeight = 64.0;
const double _timelineHeight = _hourHeight * 24;

class AgendaTab extends ConsumerStatefulWidget {
  const AgendaTab({super.key});

  @override
  ConsumerState<AgendaTab> createState() => _AgendaTabState();
}

class _AgendaTabState extends ConsumerState<AgendaTab> {
  DateTime _selectedDay = _dateOnly(DateTime.now());
  late final ScrollController _timelineController;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final initialOffset = (now.hour - 2).clamp(0, 22) * _hourHeight;
    _timelineController = ScrollController(initialScrollOffset: initialOffset);
  }

  @override
  void dispose() {
    _timelineController.dispose();
    super.dispose();
  }

  double _minutesFromMidnight(DateTime d) => d.hour * 60.0 + d.minute;

  void _confirmDelete(Task task) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BentoTheme.darkCard,
        title: Text('¿Eliminar bloque?', style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w700)),
        content: Text(task.title, style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.6))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(tasksProvider.notifier).deleteTask(task.id);
            },
            child: Text('Eliminar', style: GoogleFonts.montserrat(color: BentoTheme.errorRed, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(tasksProvider);
    final dayTasks = ref.read(tasksProvider.notifier).tasksForDay(_selectedDay);
    final isToday = _selectedDay == _dateOnly(DateTime.now());
    final accent = BentoTheme.accentLime;

    return Container(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, dayTasks),
          DayStrip(
            selectedDay: _selectedDay,
            accentColor: accent,
            onSelect: (day) => setState(() => _selectedDay = day),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: dayTasks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Nada planeado para este día.\nToca "+" para agregar un bloque.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.4), fontWeight: FontWeight.w500),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    controller: _timelineController,
                    padding: const EdgeInsets.only(bottom: 120),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: SizedBox(
                        height: _timelineHeight,
                        child: Stack(
                          children: [
                            for (int hour = 0; hour < 24; hour++)
                              Positioned(
                                top: hour * _hourHeight,
                                left: 0,
                                right: 0,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 40,
                                      child: Text(
                                        '${hour.toString().padLeft(2, '0')}:00',
                                        style: GoogleFonts.montserrat(fontSize: 10, color: BentoTheme.creamAlpha(0.35)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Container(height: 1, color: BentoTheme.creamAlpha(0.08)),
                                    ),
                                  ],
                                ),
                              ),
                            if (isToday)
                              Positioned(
                                top: _minutesFromMidnight(DateTime.now()),
                                left: 48,
                                right: 0,
                                child: Container(height: 2, color: BentoTheme.errorRed),
                              ),
                            for (final task in dayTasks)
                              Padding(
                                padding: const EdgeInsets.only(left: 48),
                                child: TimelineTaskCard(
                                  task: task,
                                  top: _minutesFromMidnight(task.startAt),
                                  height: ((task.durationMinutes ?? 40).clamp(28, 1440)).toDouble(),
                                  onTap: () => showTaskFormDialog(context, ref, day: _selectedDay, existing: task),
                                  onToggleComplete: () => ref.read(tasksProvider.notifier).toggleComplete(task.id),
                                  onLongPress: () => _confirmDelete(task),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, List<Task> dayTasks) {
    final completed = dayTasks.where((t) => t.completed).length;
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
