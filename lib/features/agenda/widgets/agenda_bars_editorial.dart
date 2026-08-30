import 'package:flutter/material.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';

import '../../../core/models/habit_model.dart';
import '../../../core/theme/editorial_theme.dart';
import '../../../core/widgets/editorial_kit.dart';
import '../quick_parse.dart';

/// Las tres barras que van bajo la cabecera de la Agenda, en el sistema
/// editorial: la tira de días, la bandeja de hábitos sin hora y la captura
/// rápida por texto.
///
/// Van en un archivo y no en tres porque son **una sola banda de controles**.
/// Comparten margen, altura de fila y la misma pregunta implícita —"¿qué pongo
/// en el día que estoy mirando?"—, y separarlas fue lo que hizo que en la
/// versión neumórfica cada una acabara con su propio radio, su propio gris y su
/// propio acento. Aquí el orden de lectura es deliberado: primero *qué día*,
/// después *lo que ya toca*, y por último *lo que quieras añadir*.

const _dayLetters = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
const _monthLetters = [
  'ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN',
  'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC',
];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

// ─────────────────────────── tira de días ───────────────────────────

/// Tira horizontal de fechas.
///
/// El estado se dice por inversión, como en el resto del sistema: el día
/// elegido es papel con tinta encima y los demás son superficie. La versión
/// anterior teñía la celda del acento lima y le ponía un filete al día de hoy,
/// dos señales distintas para dos cosas parecidas; aquí "hoy" lleva **un punto
/// bajo la cifra** y "elegido" lleva la inversión, que no se pisan.
class DayStripEditorial extends StatefulWidget {
  const DayStripEditorial({
    super.key,
    required this.selectedDay,
    required this.onSelect,
    this.countFor,
  });

  final DateTime selectedDay;
  final ValueChanged<DateTime> onSelect;

  /// Cuántos bloques tiene cada día, para pintar la densidad bajo la cifra.
  final int Function(DateTime day)? countFor;

  static const double cellWidth = 50;
  static const double cellSpacing = 8;

  @override
  State<DayStripEditorial> createState() => _DayStripEditorialState();
}

class _DayStripEditorialState extends State<DayStripEditorial> {
  static const _daysBefore = 30;
  static const _daysAfter = 60;
  static const _slot = DayStripEditorial.cellWidth + DayStripEditorial.cellSpacing;

  late final DateTime _today = _dateOnly(DateTime.now());
  late final ScrollController _controller =
      ScrollController(initialScrollOffset: _offsetFor(widget.selectedDay));

  double _offsetFor(DateTime day) {
    final index = day.difference(_today).inDays + _daysBefore;
    return (index * _slot - _slot * 2).clamp(0.0, double.infinity);
  }

  /// El día puede cambiar desde fuera —el botón "Hoy", volver de la planeación
  /// nocturna, crear un bloque para mañana—. Sin esto la tira se queda mirando
  /// otra semana y la selección desaparece de pantalla.
  @override
  void didUpdateWidget(DayStripEditorial old) {
    super.didUpdateWidget(old);
    if (old.selectedDay == widget.selectedDay || !_controller.hasClients) return;
    final target =
        _offsetFor(widget.selectedDay).clamp(0.0, _controller.position.maxScrollExtent);
    if ((target - _controller.offset).abs() < 1) return;
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: EditorialTheme.curve,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: ListView.builder(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: EditorialTheme.margin - 2),
        itemCount: _daysBefore + _daysAfter + 1,
        itemBuilder: (context, index) {
          final day = _today.add(Duration(days: index - _daysBefore));
          return Padding(
            padding: const EdgeInsets.only(right: DayStripEditorial.cellSpacing),
            child: _DayCell(
              day: day,
              selected: day == widget.selectedDay,
              isToday: day == _today,
              isPast: day.isBefore(_today),
              count: widget.countFor?.call(day) ?? 0,
              onTap: () => widget.onSelect(day),
            ),
          );
        },
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.isPast,
    required this.count,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final bool isPast;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // El primer día de cada mes lleva el rótulo del mes en vez de la inicial
    // del día: sin él, cruzar de mes en una tira infinita desorienta.
    final showsMonth = day.day == 1;

    final ink = selected
        ? EditorialTheme.ink
        : (isPast ? EditorialTheme.muted : EditorialTheme.paper);
    final soft = selected
        ? EditorialTheme.grayText
        : EditorialTheme.paperAlpha(isPast ? 0.28 : 0.45);

    return EditorialPressable(
      onTap: onTap,
      scale: 0.92,
      child: AnimatedContainer(
        duration: EditorialTheme.motion,
        curve: EditorialTheme.curve,
        width: DayStripEditorial.cellWidth,
        decoration: BoxDecoration(
          color: selected ? EditorialTheme.paper : EditorialTheme.surface,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              showsMonth ? _monthLetters[day.month - 1] : _dayLetters[day.weekday - 1],
              style: EditorialTheme.label(showsMonth ? 8.5 : 9.5, color: soft),
            ),
            const SizedBox(height: 4),
            Text(
              '${day.day}',
              style: EditorialTheme.caps(18, color: ink, letterSpacing: -0.6, height: 1.0),
            ),
            const SizedBox(height: 5),
            SizedBox(height: 4, child: _marker(selected, soft)),
          ],
        ),
      ),
    );
  }

  /// Bajo la cifra caben dos informaciones y no se estorban: si el día es HOY,
  /// un punto lleno; si no, hasta tres puntitos de densidad de bloques.
  ///
  /// Hoy gana porque sólo hay un día que lo sea, y saber cuál es importa más
  /// que su carga — que además se ve entrando en él.
  Widget _marker(bool selected, Color soft) {
    if (isToday) {
      return Center(
        child: Container(
          width: 4.5,
          height: 4.5,
          decoration: BoxDecoration(
            color: selected ? EditorialTheme.ink : EditorialTheme.paper,
            shape: BoxShape.circle,
          ),
        ),
      );
    }
    if (count <= 0) return const SizedBox.shrink();

    // Uno, dos, o tres para "tres o más": es densidad, no cuenta exacta.
    final shown = count > 3 ? 3 : count;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown; i++)
          Container(
            margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
            width: 3.5,
            height: 3.5,
            decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
          ),
      ],
    );
  }
}

// ─────────────────────── bandeja de hábitos ───────────────────────

/// Los hábitos que tocan hoy y todavía no tienen hora.
///
/// Es la pieza que hace que planear sirva de algo para los hábitos: en vez de
/// recordar cuáles tocan, están delante pidiendo un hueco. Colocar uno es darle
/// un cuándo, y un hábito con hora concreta se cumple mucho más que uno que
/// "hay que hacer en algún momento".
class HabitTrayEditorial extends StatelessWidget {
  const HabitTrayEditorial({
    super.key,
    required this.pending,
    required this.onPlace,
    required this.withUsualTime,
    this.onPlaceAll,
  });

  final List<Habit> pending;
  final void Function(Habit habit) onPlace;

  /// Coloca de golpe todos los que tienen hora habitual guardada.
  final VoidCallback? onPlaceAll;

  final int withUsualTime;

  @override
  Widget build(BuildContext context) {
    if (pending.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              EditorialTheme.margin,
              0,
              EditorialTheme.margin,
              9,
            ),
            child: Row(
              children: [
                Text(
                  'SIN HORA TODAVÍA',
                  style: EditorialTheme.label(10, color: EditorialTheme.muted),
                ),
                const Spacer(),
                // Un solo toque coloca la columna vertebral del día. Es el
                // atajo que hace que el ritual dure un minuto y no diez.
                if (onPlaceAll != null && withUsualTime > 1)
                  EditorialPressable(
                    onTap: onPlaceAll,
                    scale: 0.93,
                    child: Text(
                      'usar mis horarios',
                      style: EditorialTheme.text(
                        12,
                        weight: FontWeight.w600,
                        color: EditorialTheme.paperAlpha(0.75),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: EditorialTheme.margin),
              itemCount: pending.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _HabitChip(
                habit: pending[i],
                onTap: () => onPlace(pending[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitChip extends StatelessWidget {
  const _HabitChip({required this.habit, required this.onTap});

  final Habit habit;
  final VoidCallback onTap;

  /// La hora a la que sueles hacerlo, si la tiene guardada. Es lo que convierte
  /// el chip en un botón de "colocar donde siempre" en vez de en una etiqueta.
  String? get _usualTime {
    if (habit.reminderTimes.isNotEmpty) return habit.reminderTimes.first;
    final h = habit.reminderHour;
    final m = habit.reminderMinute;
    if (h == null || m == null) return null;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final usual = _usualTime;

    return EditorialPressable(
      onTap: onTap,
      scale: 0.94,
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 9, 10, 9),
        decoration: BoxDecoration(
          // Superficie y no el color del hábito: en la Agenda el hábito es una
          // cosa que colocar, no una identidad que exhibir. Su color vive en su
          // propia pestaña; aquí sólo estorbaría a la lectura de la fila.
          color: EditorialTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Twemoji(emoji: habit.icon, height: 15, width: 15),
            const SizedBox(width: 7),
            Text(
              habit.name,
              style: EditorialTheme.text(
                13,
                weight: FontWeight.w600,
                color: EditorialTheme.paper,
              ),
            ),
            if (usual != null) ...[
              const SizedBox(width: 7),
              Text(
                usual,
                style: EditorialTheme.text(12, color: EditorialTheme.muted),
              ),
            ],
            const SizedBox(width: 6),
            Icon(Icons.add, size: 15, color: EditorialTheme.paperAlpha(0.6)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────── captura rápida ───────────────────────

/// Barra de captura por texto con vista previa de lo interpretado.
///
/// La vista previa no es adorno: un parser que adivina sin enseñar lo que
/// entendió obliga a revisar el resultado *después* de guardar. Mostrando
/// "correr 06:30 – 07:15" mientras escribes, la corrección ocurre antes de
/// confirmar.
///
/// En editorial la vista previa deja de ser una línea suelta bajo el campo y
/// pasa a ser un bloque de papel pegado a él: es el resultado, y el resultado
/// de este sistema se pinta en papel.
class QuickAddBarEditorial extends StatefulWidget {
  const QuickAddBarEditorial({
    super.key,
    required this.fallbackStartMinutes,
    required this.onSubmit,
  });

  /// Hora sugerida cuando la línea no dice ninguna, en minutos del día.
  final int fallbackStartMinutes;

  final Future<void> Function(ParsedBlock parsed) onSubmit;

  @override
  State<QuickAddBarEditorial> createState() => _QuickAddBarEditorialState();
}

class _QuickAddBarEditorialState extends State<QuickAddBarEditorial> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  ParsedBlock? _preview;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final parsed = _preview;
    if (parsed == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(parsed);
      _controller.clear();
      setState(() => _preview = null);
      // Se mantiene el foco: planear es escribir varias líneas seguidas, y
      // recuperar el teclado entre cada una es fricción tonta.
      _focus.requestFocus();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _fmt(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EditorialTheme.margin,
        0,
        EditorialTheme.margin,
        10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: EditorialTheme.surfaceHigh,
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(EditorialTheme.radiusChip),
                // Cuando hay vista previa, el campo y el resultado se pegan en
                // una sola pieza: son lo mismo visto de dos maneras.
                bottom: Radius.circular(preview == null ? EditorialTheme.radiusChip : 0),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              children: [
                Icon(
                  Icons.bolt,
                  size: 17,
                  color: EditorialTheme.paperAlpha(preview != null ? 0.85 : 0.35),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    onChanged: (value) =>
                        setState(() => _preview = parseQuickBlock(value)),
                    onSubmitted: (_) => _submit(),
                    textInputAction: TextInputAction.done,
                    cursorColor: EditorialTheme.paper,
                    style: EditorialTheme.text(
                      14,
                      weight: FontWeight.w500,
                      color: EditorialTheme.paper,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: false,
                      fillColor: Colors.transparent,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: 'correr 6:30 45min @parque',
                      hintStyle: EditorialTheme.text(14, color: EditorialTheme.muted),
                    ),
                  ),
                ),
                if (preview != null)
                  EditorialPressable(
                    onTap: _submitting ? null : _submit,
                    scale: 0.85,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: EditorialTheme.paper,
                              ),
                            )
                          : Icon(Icons.arrow_forward_rounded,
                              size: 19, color: EditorialTheme.paper),
                    ),
                  ),
              ],
            ),
          ),
          if (preview != null) _previewBlock(preview),
        ],
      ),
    );
  }

  /// Lo que el parser entendió, en papel. Que sea el único trozo blanco de la
  /// banda es el punto: es lo que hay que revisar antes de pulsar.
  Widget _previewBlock(ParsedBlock parsed) {
    final start = parsed.startMinutes ?? widget.fallbackStartMinutes;
    final end = start + (parsed.durationMinutes ?? 30);

    final extras = <String>[
      if (parsed.location != null) parsed.location!,
      if (parsed.dayOffset == 1) 'mañana',
      if (parsed.dayOffset == 2) 'pasado mañana',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 11),
      decoration: const BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(EditorialTheme.radiusChip),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              parsed.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: EditorialTheme.text(
                14,
                weight: FontWeight.w600,
                color: EditorialTheme.ink,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${_fmt(start)}–${_fmt(end)}'
            '${extras.isEmpty ? '' : '  ·  ${extras.join('  ·  ')}'}',
            style: EditorialTheme.text(12.5, color: EditorialTheme.grayText),
          ),
        ],
      ),
    );
  }
}
