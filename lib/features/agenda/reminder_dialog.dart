import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/providers/tasks_provider.dart';
import '../../core/theme/bento_theme.dart';
import '../alarm/widgets/bento_time_picker.dart';

/// Duración del bloque que respalda un recordatorio.
///
/// Un recordatorio es un bloque corto con aviso: no hace falta un tipo nuevo en
/// el modelo ni en la base de datos, y a cambio sale gratis que aparezca en el
/// timeline, se pueda arrastrar y se edite con el mismo formulario que todo lo
/// demás.
const _reminderMinutes = 15;

/// Abre el modal corto para poner un recordatorio en [day].
///
/// Existe aparte del formulario de bloque porque son dos intenciones distintas:
/// "voy a dedicar de 7 a 8 a esto" contra "que no se me olvide llamar al
/// dentista". Pedir duración, prioridad, lugar y MIT para lo segundo es lo que
/// hace que al final no lo apuntes.
Future<void> showReminderDialog(BuildContext context, WidgetRef ref, {required DateTime day}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ReminderSheet(day: day),
  );
}

class _ReminderSheet extends ConsumerStatefulWidget {
  final DateTime day;
  const _ReminderSheet({required this.day});

  @override
  ConsumerState<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends ConsumerState<_ReminderSheet> {
  final _titleController = TextEditingController();
  late TimeOfDay _time;
  String? _titleError;

  /// Solo cambia cuando un preset mueve la hora por fuera de la rueda. La rueda
  /// guarda su propia posición, así que se recrea únicamente en ese caso — usar
  /// la hora como key la reconstruiría a mitad de cada deslizamiento.
  int _pickerEpoch = 0;

  /// Horas de recordatorio típicas. Un toque cubre el caso normal; la rueda
  /// sigue ahí para el resto.
  static const _presets = [
    (label: 'Mañana', hour: 9),
    (label: 'Mediodía', hour: 13),
    (label: 'Tarde', hour: 17),
    (label: 'Noche', hour: 21),
  ];

  @override
  void initState() {
    super.initState();
    _time = _defaultTime();
  }

  /// En un día futuro, la mañana. En hoy, la siguiente hora en punto: poner un
  /// aviso a una hora que ya pasó no serviría de nada.
  TimeOfDay _defaultTime() {
    final now = DateTime.now();
    final isToday = DateTime(widget.day.year, widget.day.month, widget.day.day) ==
        DateTime(now.year, now.month, now.day);
    if (!isToday) return const TimeOfDay(hour: 9, minute: 0);
    final next = now.add(const Duration(hours: 1));
    if (next.day != now.day) return const TimeOfDay(hour: 23, minute: 30);
    return TimeOfDay(hour: next.hour, minute: 0);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  DateTime get _startAt =>
      DateTime(widget.day.year, widget.day.month, widget.day.day, _time.hour, _time.minute);

  bool get _isPast => _startAt.isBefore(DateTime.now());

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = '¿De qué te recordamos?');
      return;
    }

    final notifier = ref.read(tasksProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final startAt = _startAt;

    Navigator.pop(context);

    await notifier.addTask(
      title: title,
      dueDate: widget.day,
      startAt: startAt,
      endAt: startAt.add(const Duration(minutes: _reminderMinutes)),
      remindAt: startAt,
      plannedAt: DateTime.now(),
    );

    final error = notifier.takeSyncError();
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error, style: GoogleFonts.montserrat(fontWeight: FontWeight.w600)),
          backgroundColor: BentoTheme.darkCardAlt,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String get _dayLabel {
    final today = DateTime.now();
    final day = DateTime(widget.day.year, widget.day.month, widget.day.day);
    final diff = day.difference(DateTime(today.year, today.month, today.day)).inDays;
    if (diff == 0) return 'hoy';
    if (diff == 1) return 'mañana';
    return DateFormat("EEEE d 'de' MMMM", 'es').format(day);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: BentoTheme.darkCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: BentoTheme.creamAlpha(0.2),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                child: Row(
                  children: [
                    Icon(Icons.notifications_none_rounded, size: 20, color: BentoTheme.accentOrange),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recordatorio',
                            style: GoogleFonts.montserrat(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: BentoTheme.cream,
                            ),
                          ),
                          Text(
                            _dayLabel,
                            style: GoogleFonts.montserrat(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: BentoTheme.creamAlpha(0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: BentoTheme.creamAlpha(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: BentoTheme.creamAlpha(0.14)),
                        ),
                        child: Icon(Icons.close, size: 18, color: BentoTheme.creamAlpha(0.8)),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _titleController,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      onChanged: (_) {
                        if (_titleError != null) setState(() => _titleError = null);
                      },
                      style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
                      decoration: _fieldDecoration('Ej: llamar al dentista', _titleError),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final preset in _presets)
                          _presetChip(preset.label, preset.hour),
                      ],
                    ),
                    const SizedBox(height: 8),
                    BentoTimePicker(
                      key: ValueKey(_pickerEpoch),
                      initialTime: _time,
                      onChanged: (t) => setState(() => _time = t),
                    ),
                    if (_isPast)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 15, color: BentoTheme.accentOrange),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                'Esa hora ya pasó: quedará apuntado, pero no sonará.',
                                style: GoogleFonts.montserrat(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: BentoTheme.accentOrange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 18),
                    GestureDetector(
                      onTap: _submit,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: BentoTheme.accentOrange,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          'Recordármelo',
                          style: GoogleFonts.montserrat(
                            color: const Color(0xFF0C0C0D),
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetChip(String label, int hour) {
    final selected = _time.hour == hour && _time.minute == 0;
    return GestureDetector(
      onTap: () => setState(() {
        _time = TimeOfDay(hour: hour, minute: 0);
        _pickerEpoch++;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? BentoTheme.accentOrange.withValues(alpha: 0.18) : BentoTheme.creamAlpha(0.06),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected ? BentoTheme.accentOrange : BentoTheme.creamAlpha(0.14),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? BentoTheme.accentOrange : BentoTheme.creamAlpha(0.6),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint, String? errorText) {
    return InputDecoration(
      hintText: hint,
      errorText: errorText,
      errorStyle: GoogleFonts.montserrat(color: BentoTheme.errorRed, fontWeight: FontWeight.w600, fontSize: 12),
      hintStyle: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.35), fontWeight: FontWeight.w500),
      filled: true,
      fillColor: BentoTheme.creamAlpha(0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: BentoTheme.creamAlpha(0.12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: BentoTheme.creamAlpha(0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: BentoTheme.accentOrange, width: 1.5),
      ),
    );
  }
}
