import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/habit_model.dart';
import '../../../core/theme/bento_theme.dart';

const double _kCell = 13;
const double _kGap = 4;
const List<String> _kWeekdayLabels = ['L', '', 'X', '', 'V', '', ''];

/// Heatmap estilo "GitHub contributions" para un hábito: una columna por semana
/// (Lunes-Domingo), coloreado automáticamente según el historial real de
/// `habit.completedDates`. Es de solo lectura — no se puede editar el
/// historial tocando celdas, se llena solo a medida que se marcan hábitos.
class HabitHeatmap extends StatefulWidget {
  final Habit habit;
  final int weeks;

  const HabitHeatmap({
    super.key,
    required this.habit,
    this.weeks = 53,
  });

  @override
  State<HabitHeatmap> createState() => _HabitHeatmapState();
}

class _HabitHeatmapState extends State<HabitHeatmap> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final habit = widget.habit;
    final weeks = widget.weeks;
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final totalDays = weeks * 7;
    final rawStart = today.subtract(Duration(days: totalDays - 1));
    final start = rawStart.subtract(Duration(days: rawStart.weekday - 1)); // retrocede al Lunes

    final columns = <List<DateTime?>>[];
    var cursor = start;
    for (int w = 0; w < weeks + 1; w++) {
      final col = <DateTime?>[];
      for (int d = 0; d < 7; d++) {
        col.add(cursor.isAfter(today) ? null : cursor);
        cursor = cursor.add(const Duration(days: 1));
      }
      columns.add(col);
      if (col.every((d) => d == null)) break;
    }

    String? lastMonth;
    final monthLabels = <String>[];
    for (final col in columns) {
      final firstValid = col.firstWhere((d) => d != null, orElse: () => null);
      if (firstValid != null && firstValid.day <= 7) {
        final m = DateFormat('MMM').format(firstValid);
        if (m != lastMonth) {
          monthLabels.add(m);
          lastMonth = m;
          continue;
        }
      }
      monthLabels.add('');
    }

    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 18, right: 6),
              child: Column(
                children: _kWeekdayLabels
                    .map((l) => SizedBox(
                          height: _kCell + _kGap,
                          child: Text(
                            l,
                            style: const TextStyle(fontSize: 9, color: BentoTheme.textSecondary, fontWeight: FontWeight.bold),
                          ),
                        ))
                    .toList(),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(columns.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(right: _kGap),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 14,
                        width: _kCell,
                        child: Text(
                          monthLabels[i],
                          style: const TextStyle(fontSize: 9, color: BentoTheme.textSecondary, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...columns[i].map((day) => Padding(
                            padding: const EdgeInsets.only(bottom: _kGap),
                            child: _HeatCell(habit: habit, day: day),
                          )),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeatCell extends StatelessWidget {
  final Habit habit;
  final DateTime? day;

  const _HeatCell({required this.habit, required this.day});

  @override
  Widget build(BuildContext context) {
    if (day == null) {
      return const SizedBox(width: _kCell, height: _kCell);
    }

    final active = habit.isActiveOn(day!);
    final completed = habit.isCompletedOn(day!);
    final base = habit.colorValue;

    Color cellColor;
    if (completed) {
      cellColor = base;
    } else if (active) {
      cellColor = base.withOpacity(0.14);
    } else {
      cellColor = BentoTheme.borderMuted;
    }

    return Tooltip(
      message: DateFormat('d MMM yyyy').format(day!),
      child: Container(
        width: _kCell,
        height: _kCell,
        decoration: BoxDecoration(
          color: cellColor,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
