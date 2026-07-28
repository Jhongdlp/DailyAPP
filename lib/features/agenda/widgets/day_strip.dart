import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/bento_theme.dart';

const _kDayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Tira horizontal de fechas para navegar entre días de la Agenda.
/// Centra el rango en torno a hoy, con [daysBefore]/[daysAfter] de margen.
class DayStrip extends StatefulWidget {
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelect;
  final Color accentColor;

  const DayStrip({
    super.key,
    required this.selectedDay,
    required this.onSelect,
    required this.accentColor,
  });

  @override
  State<DayStrip> createState() => _DayStripState();
}

class _DayStripState extends State<DayStrip> {
  static const _daysBefore = 30;
  static const _daysAfter = 60;
  late final DateTime _today = _dateOnly(DateTime.now());
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.selectedDay.difference(_today).inDays + _daysBefore;
    const cellWidth = 56.0;
    _controller = ScrollController(
      initialScrollOffset: (initialIndex * cellWidth - cellWidth * 2).clamp(0.0, double.infinity),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _daysBefore + _daysAfter + 1;
    return SizedBox(
      height: 68,
      child: ListView.builder(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: total,
        itemBuilder: (context, index) {
          final day = _today.add(Duration(days: index - _daysBefore));
          final isSelected = day == widget.selectedDay;
          final isToday = day == _today;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSelect(day),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 48,
                decoration: BoxDecoration(
                  color: isSelected ? widget.accentColor : BentoTheme.creamAlpha(0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: isToday && !isSelected
                      ? Border.all(color: widget.accentColor.withValues(alpha: 0.6), width: 1.5)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _kDayLabels[day.weekday - 1],
                      style: GoogleFonts.montserrat(
                        fontSize: 10,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? const Color(0xFF0C0C0D) : BentoTheme.creamAlpha(0.45),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${day.day}',
                      style: GoogleFonts.montserrat(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? const Color(0xFF0C0C0D) : BentoTheme.cream,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
