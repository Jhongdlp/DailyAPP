import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/appearance_provider.dart';
import '../../../core/theme/editorial_theme.dart';
import '../../../core/theme/bento_theme.dart';

const _kDayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
const _kMonthNames = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _monthOf(DateTime d) => DateTime(d.year, d.month);

/// Lo que hay en un día, resumido para pintar su celda.
///
/// El calendario necesita distinguir *cuánto* hay de *qué tipo* es: un día con
/// tres bloques de trabajo y uno con tres recordatorios sueltos no piden la
/// misma decisión al mirarlos, y con un solo contador se veían igual.
class DayStats {
  /// Bloques del día, recordatorios incluidos.
  final int blocks;

  /// Cuántos de esos bloques tienen aviso programado.
  final int reminders;

  const DayStats({this.blocks = 0, this.reminders = 0});

  bool get isEmpty => blocks == 0;
}

/// Vista de mes de la Agenda.
///
/// Complementa a la tira horizontal de días: la tira sirve para moverse un par
/// de días, pero elegir "el 14 del mes que viene" con ella son veinte
/// deslizamientos. Aquí el mes entero cabe de un vistazo, con la densidad de
/// cada día marcada en puntos para poder decidir *dónde* meter algo, no solo
/// cuándo.
/// Igual que el timeline, la piel se parametriza en vez de duplicarse: la
/// cuadrícula de 7×6, el alto de celda y la lectura de densidad son idénticas
/// en los dos lenguajes, y sólo cambian colores y tipografía. Ver
/// [_CalendarSkin].
class MonthCalendar extends ConsumerStatefulWidget {
  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelect;
  final Color accentColor;

  /// Qué tiene cada día. Se consulta para las 42 celdas visibles, así que debe
  /// ser una búsqueda barata (un mapa ya construido), no un filtrado de la
  /// lista completa.
  final DayStats Function(DateTime day) statsFor;

  /// Añadir un bloque por la vía corta: solo qué y a qué hora avisar.
  final VoidCallback onAddReminder;

  /// Crear un bloque con horario en el día seleccionado.
  final VoidCallback onAddBlock;

  const MonthCalendar({
    super.key,
    required this.selectedDay,
    required this.onSelect,
    required this.accentColor,
    required this.statsFor,
    required this.onAddReminder,
    required this.onAddBlock,
  });

  @override
  ConsumerState<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends ConsumerState<MonthCalendar> {
  late _CalendarSkin _skin;

  late final DateTime _today = _dateOnly(DateTime.now());
  late DateTime _visibleMonth = _monthOf(widget.selectedDay);

  /// Elegir un día desde fuera (botón "Hoy", volver de la planeación nocturna)
  /// debe traer el calendario a ese mes; si no, la selección desaparece.
  @override
  void didUpdateWidget(MonthCalendar old) {
    super.didUpdateWidget(old);
    if (old.selectedDay != widget.selectedDay) {
      final month = _monthOf(widget.selectedDay);
      if (month != _visibleMonth) setState(() => _visibleMonth = month);
    }
  }

  void _shiftMonth(int delta) {
    setState(() => _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta));
  }

  /// Primer día de la cuadrícula: el lunes de la semana en la que cae el 1.
  DateTime get _gridStart {
    final first = _visibleMonth;
    return first.subtract(Duration(days: first.weekday - 1));
  }

  /// Cuántas semanas hacen falta para cubrir el mes. Calcularlo (en vez de fijar
  /// seis) evita una fila vacía en los meses cortos, que descoloca todo lo que
  /// hay debajo al cambiar de mes.
  int get _weekCount {
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final leading = _visibleMonth.weekday - 1;
    return ((leading + daysInMonth) / 7).ceil();
  }

  @override
  Widget build(BuildContext context) {
    _skin = ref.watch(designLanguageProvider).isEditorial
        ? _CalendarSkin.editorial()
        : _CalendarSkin.neu(widget.accentColor);

    final start = _gridStart;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMonthBar(),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final label in _kDayLabels)
                Expanded(
                  child: Center(
                    child: Text(label, style: _skin.weekdayLabel),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // El arrastre horizontal cambia de mes: es el gesto que todo el mundo
          // prueba primero en una cuadrícula de fechas.
          GestureDetector(
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v.abs() < 120) return;
              _shiftMonth(v < 0 ? 1 : -1);
            },
            child: Column(
              children: [
                for (var week = 0; week < _weekCount; week++)
                  Row(
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(child: _buildCell(start.add(Duration(days: week * 7 + i)))),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _buildDayActions(),
        ],
      ),
    );
  }

  Widget _buildMonthBar() {
    final isCurrentMonth = _visibleMonth == _monthOf(_today);
    return Row(
      children: [
        _monthArrow(Icons.chevron_left_rounded, () => _shiftMonth(-1)),
        Expanded(
          child: Center(
            child: Text(
              '${_kMonthNames[_visibleMonth.month - 1]} ${_visibleMonth.year}',
              style: _skin.monthTitle,
            ),
          ),
        ),
        // Volver al mes de hoy solo aparece cuando te has ido de él.
        if (!isCurrentMonth)
          GestureDetector(
            onTap: () => setState(() => _visibleMonth = _monthOf(_today)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Text('Hoy', style: _skin.todayLink),
            ),
          ),
        _monthArrow(Icons.chevron_right_rounded, () => _shiftMonth(1)),
      ],
    );
  }

  Widget _monthArrow(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 22, color: _skin.arrowInk),
      ),
    );
  }

  Widget _buildCell(DateTime day) {
    final isSelected = day == widget.selectedDay;
    final isToday = day == _today;
    final inMonth = day.month == _visibleMonth.month && day.year == _visibleMonth.year;
    final isPast = day.isBefore(_today);
    // Los días de relleno no se resumen: no son de este mes y sus marcas
    // confundirían la lectura de densidad de la cuadrícula.
    final stats = inMonth ? widget.statsFor(day) : const DayStats();
    final count = stats.blocks;


    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onSelect(day),
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: 42,
          decoration: BoxDecoration(
            color: _skin.cellFill(selected: isSelected, hasBlocks: count > 0),
            borderRadius: BorderRadius.circular(13),
            border: _skin.cellBorder(isToday: isToday, selected: isSelected),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                // Los días de relleno se dejan visibles pero apagados: sirven
                // para orientarse en la semana, no para tocarlos por error.
                style: _skin.dayNumber(
                  selected: isSelected,
                  inMonth: inMonth,
                  isPast: isPast,
                  isToday: isToday,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(height: 4, child: _buildDots(stats, isSelected, isPast)),
            ],
          ),
        ),
      ),
    );
  }

  /// Densidad del día: uno, dos, o tres puntos para "tres o más". Es la misma
  /// lectura que la tira de días, para que cambiar de vista no cambie lo que
  /// significan las marcas.
  ///
  /// Los días que llevan aviso pintan sus puntos en el color de recordatorio,
  /// el mismo de la píldora del pie: es la diferencia entre "ese día tengo
  /// cosas" y "ese día algo va a sonar".
  Widget _buildDots(DayStats stats, bool isSelected, bool isPast) {
    if (stats.isEmpty) return const SizedBox.shrink();

    final shown = stats.blocks > 3 ? 3 : stats.blocks;
    // Cuántos de los puntos visibles se pintan como recordatorio, respetando la
    // proporción cuando el día está recortado a tres.
    final reminderDots = stats.reminders >= stats.blocks
        ? shown
        : (stats.reminders * shown / stats.blocks).round();

    final base = _skin.dot(selected: isSelected, isPast: isPast, reminder: false);
    final reminderColor =
        _skin.dot(selected: isSelected, isPast: isPast, reminder: true);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown; i++)
          Container(
            margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
            width: 3.5,
            height: 3.5,
            decoration: BoxDecoration(
              color: i < reminderDots ? reminderColor : base,
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }

  /// Pie del calendario: qué hay en el día elegido y las dos formas de añadir.
  ///
  /// Está aquí y no en la cabecera porque el momento de "quiero algo el día 14"
  /// es justo el toque siguiente a elegir el 14; obligar a cerrar el calendario
  /// primero rompe esa secuencia.
  Widget _buildDayActions() {
    final stats = widget.statsFor(widget.selectedDay);

    return Row(
      children: [
        Expanded(
          child: Text(_dayLabel(stats), style: _skin.footLabel(stats.isEmpty)),
        ),
        _actionPill(
          icon: Icons.notifications_none_rounded,
          label: 'Recordatorio',
          primary: false,
          onTap: widget.onAddReminder,
        ),
        const SizedBox(width: 8),
        _actionPill(
          icon: Icons.add_rounded,
          label: 'Bloque',
          primary: true,
          onTap: widget.onAddBlock,
        ),
      ],
    );
  }

  static String _dayLabel(DayStats stats) {
    if (stats.isEmpty) return 'Día libre';

    final blocks = '${stats.blocks} ${stats.blocks == 1 ? 'bloque' : 'bloques'}';
    if (stats.reminders == 0) return blocks;

    return '$blocks · ${stats.reminders} con aviso';
  }

  /// Las dos formas de añadir. [primary] distingue la principal —crear un
  /// bloque con horario— del atajo del aviso suelto.
  Widget _actionPill({
    required IconData icon,
    required String label,
    required bool primary,
    required VoidCallback onTap,
  }) {
    final ink = _skin.pillInk(primary);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
        decoration: BoxDecoration(
          color: _skin.pillFill(primary),
          borderRadius: BorderRadius.circular(100),
          border: _skin.pillBorder(primary),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: ink),
            const SizedBox(width: 5),
            Text(label, style: _skin.pillLabel(primary)),
          ],
        ),
      ),
    );
  }
}

/// Los tokens que separan una piel de la otra en el calendario.
///
/// Mismo criterio que `_TimelineSkin`: la cuadrícula es geometría común y esto
/// es lo único que cambia. Añadir un elemento obliga a darle su token aquí, y
/// entonces no se puede olvidar la otra piel.
class _CalendarSkin {
  const _CalendarSkin({
    required this.weekdayLabel,
    required this.monthTitle,
    required this.todayLink,
    required this.arrowInk,
    required this.cellFill,
    required this.cellBorder,
    required this.dayNumber,
    required this.dot,
    required this.footLabel,
    required this.pillFill,
    required this.pillBorder,
    required this.pillInk,
    required this.pillLabel,
  });

  final TextStyle weekdayLabel;
  final TextStyle monthTitle;
  final TextStyle todayLink;
  final Color arrowInk;

  final Color Function({required bool selected, required bool hasBlocks}) cellFill;
  final BoxBorder? Function({required bool isToday, required bool selected}) cellBorder;
  final TextStyle Function({
    required bool selected,
    required bool inMonth,
    required bool isPast,
    required bool isToday,
  }) dayNumber;

  /// Los puntos de densidad. [reminder] distingue "ese día tengo cosas" de
  /// "ese día algo va a sonar", que es la única diferencia que el calendario
  /// necesita comunicar a este tamaño.
  final Color Function({
    required bool selected,
    required bool isPast,
    required bool reminder,
  }) dot;

  final TextStyle Function(bool isEmpty) footLabel;

  final Color Function(bool primary) pillFill;
  final BoxBorder? Function(bool primary) pillBorder;
  final Color Function(bool primary) pillInk;
  final TextStyle Function(bool primary) pillLabel;

  factory _CalendarSkin.neu(Color accent) {
    const onAccent = Color(0xFF0C0C0D);
    return _CalendarSkin(
      weekdayLabel: GoogleFonts.montserrat(
        fontSize: 10,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
        color: BentoTheme.creamAlpha(0.35),
      ),
      monthTitle: GoogleFonts.montserrat(
        fontSize: 13.5,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        color: BentoTheme.cream,
      ),
      todayLink: GoogleFonts.montserrat(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: accent,
      ),
      arrowInk: BentoTheme.creamAlpha(0.55),
      cellFill: ({required selected, required hasBlocks}) => selected
          ? accent
          : (hasBlocks ? BentoTheme.creamAlpha(0.05) : Colors.transparent),
      cellBorder: ({required isToday, required selected}) => isToday && !selected
          ? Border.all(color: accent.withValues(alpha: 0.55), width: 1.5)
          : null,
      dayNumber: ({required selected, required inMonth, required isPast, required isToday}) =>
          GoogleFonts.montserrat(
        fontSize: 14.5,
        height: 1.0,
        fontWeight: isToday || selected ? FontWeight.w800 : FontWeight.w600,
        letterSpacing: -0.3,
        color: selected
            ? onAccent
            : !inMonth
                ? BentoTheme.creamAlpha(0.16)
                : (isPast ? BentoTheme.creamAlpha(0.38) : BentoTheme.cream),
      ),
      dot: ({required selected, required isPast, required reminder}) {
        if (selected) {
          return onAccent.withValues(alpha: reminder ? 0.65 : 0.5);
        }
        return reminder
            ? BentoTheme.accentOrange.withValues(alpha: isPast ? 0.35 : 0.75)
            : BentoTheme.creamAlpha(isPast ? 0.2 : 0.38);
      },
      footLabel: (isEmpty) => GoogleFonts.montserrat(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: BentoTheme.creamAlpha(isEmpty ? 0.35 : 0.55),
      ),
      pillFill: (primary) => (primary ? accent : BentoTheme.accentOrange)
          .withValues(alpha: 0.13),
      pillBorder: (primary) => Border.all(
        color: (primary ? accent : BentoTheme.accentOrange).withValues(alpha: 0.4),
      ),
      pillInk: (primary) => primary ? accent : BentoTheme.accentOrange,
      pillLabel: (primary) => GoogleFonts.montserrat(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: primary ? accent : BentoTheme.accentOrange,
      ),
    );
  }

  /// Editorial: el día elegido se invierte a papel y el resto es superficie.
  ///
  /// El día de hoy ya no lleva filete de acento sino **negrita**. En una
  /// cuadrícula de 42 celdas, un borde de color es una silueta más compitiendo
  /// con la del día elegido; el peso tipográfico distingue igual de bien y no
  /// añade geometría.
  ///
  /// Los puntos de recordatorio conservan el ámbar. Es el único color de la
  /// pieza y ahí sí es dato: separa "ese día tengo cosas" de "ese día algo va a
  /// sonar", que es lo que se viene a mirar en un calendario de mes.
  factory _CalendarSkin.editorial() {
    final amber = EditorialTheme.accentAt(const Color(0xFFF4A261), 0.72);

    return _CalendarSkin(
      weekdayLabel: EditorialTheme.label(9.5, color: EditorialTheme.muted),
      monthTitle: EditorialTheme.text(
        14.5,
        weight: FontWeight.w600,
        color: EditorialTheme.paper,
      ),
      todayLink: EditorialTheme.text(
        12,
        weight: FontWeight.w600,
        color: EditorialTheme.paperAlpha(0.75),
      ),
      arrowInk: EditorialTheme.paperAlpha(0.55),
      cellFill: ({required selected, required hasBlocks}) => selected
          ? EditorialTheme.paper
          : (hasBlocks ? EditorialTheme.surface : Colors.transparent),
      // Ver la nota de la clase: hoy se marca con peso, no con borde.
      cellBorder: ({required isToday, required selected}) => null,
      dayNumber: ({required selected, required inMonth, required isPast, required isToday}) =>
          EditorialTheme.text(
        15,
        weight: isToday || selected ? FontWeight.w700 : FontWeight.w500,
        color: selected
            ? EditorialTheme.ink
            : !inMonth
                ? EditorialTheme.paperAlpha(0.18)
                : EditorialTheme.paperAlpha(isPast ? 0.4 : 0.9),
      ),
      dot: ({required selected, required isPast, required reminder}) {
        if (selected) {
          return reminder ? amber : EditorialTheme.inkAlpha(0.45);
        }
        return reminder
            ? amber.withValues(alpha: isPast ? 0.45 : 0.9)
            : EditorialTheme.paperAlpha(isPast ? 0.22 : 0.4);
      },
      footLabel: (isEmpty) => EditorialTheme.text(
        12,
        weight: FontWeight.w500,
        color: isEmpty ? EditorialTheme.muted : EditorialTheme.paperAlpha(0.65),
      ),
      pillFill: (primary) => primary ? EditorialTheme.paper : EditorialTheme.surfaceHigh,
      pillBorder: (primary) => null,
      pillInk: (primary) => primary ? EditorialTheme.ink : EditorialTheme.paperAlpha(0.8),
      pillLabel: (primary) => EditorialTheme.text(
        12,
        weight: FontWeight.w600,
        color: primary ? EditorialTheme.ink : EditorialTheme.paperAlpha(0.85),
      ),
    );
  }
}
