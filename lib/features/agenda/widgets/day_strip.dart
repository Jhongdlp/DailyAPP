import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/bento_theme.dart';

const _kDayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
const _kMonthLabels = [
  'ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN',
  'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC',
];

const _cellWidth = 48.0;
const _cellSpacing = 8.0;
const _slotWidth = _cellWidth + _cellSpacing;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Tira horizontal de fechas para navegar entre días de la Agenda.
/// Centra el rango en torno a hoy, con [daysBefore]/[daysAfter] de margen.
class DayStrip extends StatefulWidget {
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelect;
  final Color accentColor;

  /// Cuántos bloques tiene cada día. Se pinta como puntitos bajo la fecha:
  /// permite ver de un vistazo qué días están cargados y cuáles vacíos sin
  /// tener que entrar en cada uno.
  final int Function(DateTime day)? countFor;

  const DayStrip({
    super.key,
    required this.selectedDay,
    required this.onSelect,
    required this.accentColor,
    this.countFor,
  });

  @override
  State<DayStrip> createState() => _DayStripState();
}

class _DayStripState extends State<DayStrip> {
  static const _daysBefore = 30;
  static const _daysAfter = 60;
  late final DateTime _today = _dateOnly(DateTime.now());
  late final ScrollController _controller;

  double _offsetFor(DateTime day) {
    final index = day.difference(_today).inDays + _daysBefore;
    return (index * _slotWidth - _slotWidth * 2).clamp(0.0, double.infinity);
  }

  @override
  void initState() {
    super.initState();
    _controller = ScrollController(initialScrollOffset: _offsetFor(widget.selectedDay));
  }

  /// El día puede cambiar desde fuera (botón "Hoy", volver de la planeación
  /// nocturna, crear un bloque para mañana). Sin esto la tira se quedaba
  /// mirando otra semana y la selección desaparecía de pantalla.
  @override
  void didUpdateWidget(DayStrip old) {
    super.didUpdateWidget(old);
    if (old.selectedDay == widget.selectedDay || !_controller.hasClients) return;
    final target = _offsetFor(widget.selectedDay).clamp(0.0, _controller.position.maxScrollExtent);
    if ((target - _controller.offset).abs() < 1) return;
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
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
      height: 66,
      child: ListView.builder(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: total,
        itemBuilder: (context, index) {
          final day = _today.add(Duration(days: index - _daysBefore));
          final isSelected = day == widget.selectedDay;
          final isToday = day == _today;
          final isPast = day.isBefore(_today);
          final isWeekend = day.weekday >= 6;
          // El primer día de cada mes lleva el rótulo en vez del día de la
          // semana: sin él, cruzar de mes en una tira infinita desorienta.
          final showsMonth = day.day == 1;
          final count = widget.countFor?.call(day) ?? 0;

          final Color fg = isSelected
              ? const Color(0xFF0C0C0D)
              : (isPast ? BentoTheme.creamAlpha(0.35) : BentoTheme.cream);

          return Padding(
            padding: const EdgeInsets.only(right: _cellSpacing),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSelect(day),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: _cellWidth,
                decoration: BoxDecoration(
                  color: isSelected ? widget.accentColor : BentoTheme.creamAlpha(isWeekend ? 0.03 : 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: isToday && !isSelected
                      ? Border.all(color: widget.accentColor.withValues(alpha: 0.55), width: 1.5)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      showsMonth ? _kMonthLabels[day.month - 1] : _kDayLabels[day.weekday - 1],
                      style: GoogleFonts.montserrat(
                        fontSize: showsMonth ? 8.5 : 10,
                        letterSpacing: showsMonth ? 0.4 : 0.6,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? const Color(0xFF0C0C0D).withValues(alpha: 0.65)
                            : BentoTheme.creamAlpha(isPast ? 0.28 : 0.45),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${day.day}',
                      style: GoogleFonts.montserrat(
                        fontSize: 17,
                        height: 1.0,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(height: 4, child: _buildDots(count, isSelected, isPast)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Hasta tres puntos: uno, dos, o tres para "tres o más". Es densidad, no
  /// cuenta exacta — el número exacto ya está dentro del día y aquí solo
  /// estorbaría.
  Widget _buildDots(int count, bool isSelected, bool isPast) {
    if (count <= 0) return const SizedBox.shrink();
    final shown = count > 3 ? 3 : count;
    final color = isSelected
        ? const Color(0xFF0C0C0D).withValues(alpha: 0.5)
        : BentoTheme.creamAlpha(isPast ? 0.2 : 0.38);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown; i++)
          Container(
            margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
            width: 3.5,
            height: 3.5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
      ],
    );
  }
}
