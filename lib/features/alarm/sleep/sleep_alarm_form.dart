import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/alarm_model.dart';
import '../../../core/models/sleep_model.dart';
import '../../../core/providers/alarms_provider.dart';
import '../../../core/providers/sleep_provider.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/utils/error_snackbar.dart';
import '../widgets/bento_time_picker.dart';

/// Crear o editar **el** horario de sueño: acostarse y despertar en una sola
/// pieza, más los ajustes que no caben en una alarma normal.
///
/// Sustituye al antiguo formulario de horario suelto: tener la hora de dormir
/// en un sitio y la de despertar en otro obligaba a mantenerlas a mano en
/// sincronía, que es exactamente lo que nadie hace.
class SleepAlarmForm extends ConsumerStatefulWidget {
  /// Alarma de sueño existente, o `null` para crear una nueva.
  final AlarmModel? alarm;

  const SleepAlarmForm({super.key, this.alarm});

  static Future<void> open(BuildContext context, {AlarmModel? alarm}) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SleepAlarmForm(alarm: alarm)),
    );
  }

  @override
  ConsumerState<SleepAlarmForm> createState() => _SleepAlarmFormState();
}

class _SleepAlarmFormState extends ConsumerState<SleepAlarmForm> {
  late TimeOfDay _bedtime;
  late TimeOfDay _wake;
  late Set<int> _days;
  late TextEditingController _objectCtrl;
  late int _goalMinutes;
  late int _windDown;
  late bool _nag;
  late bool _wakeCheck;
  late int _wakeCheckInterval;
  late int _wakeCheckWindow;
  bool _saving = false;

  /// Qué extremo del rango está editando el selector de hora.
  bool _editingBedtime = true;

  static const _dayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
  static const _weekdays = {1, 2, 3, 4, 5};
  static const _weekend = {6, 7};
  static const _allDays = {1, 2, 3, 4, 5, 6, 7};

  static const _objectSuggestions = [
    'Taza de café',
    'Lavamanos del baño',
    'Cafetera',
    'Cepillo de dientes',
  ];
  static const _windDownOptions = [0, 15, 30, 45, 60];
  static const _wakeCheckIntervalOptions = [5, 10, 15, 20];
  static const _wakeCheckWindowOptions = [20, 40, 60, 90];

  @override
  void initState() {
    super.initState();
    final alarm = widget.alarm;
    final schedule = ref.read(sleepProvider).schedule;

    _bedtime = alarm != null && alarm.isSleepAlarm
        ? TimeOfDay(hour: alarm.bedtimeHour!, minute: alarm.bedtimeMinute!)
        : TimeOfDay(hour: schedule.bedtimeHour, minute: schedule.bedtimeMinute);
    _wake = alarm != null
        ? TimeOfDay(hour: alarm.hour, minute: alarm.minute)
        : const TimeOfDay(hour: 7, minute: 0);
    _days = alarm != null ? Set.of(alarm.daysOfWeek) : Set.of(_allDays);
    _objectCtrl =
        TextEditingController(text: alarm?.targetObject ?? 'Taza de café');
    _goalMinutes = schedule.goalMinutes;
    _windDown = schedule.windDownMinutes;
    _nag = schedule.nagEnabled;
    _wakeCheck = schedule.wakeCheckEnabled;
    _wakeCheckInterval = schedule.wakeCheckIntervalMinutes;
    _wakeCheckWindow = schedule.wakeCheckWindowMinutes;
  }

  @override
  void dispose() {
    _objectCtrl.dispose();
    super.dispose();
  }

  /// Minutos entre acostarse y despertar, cruzando medianoche.
  int get _windowMinutes {
    final start = _bedtime.hour * 60 + _bedtime.minute;
    final end = _wake.hour * 60 + _wake.minute;
    final diff = end - start;
    return diff <= 0 ? diff + 1440 : diff;
  }

  Future<void> _save() async {
    if (_objectCtrl.text.trim().isEmpty) {
      showErrorSnackBar(context, message: 'Escribe el objeto a fotografiar');
      return;
    }
    if (_days.isEmpty) {
      showErrorSnackBar(context, message: 'Selecciona al menos un día');
      return;
    }
    setState(() => _saving = true);

    try {
      final alarms = ref.read(alarmsProvider.notifier);
      final days = _days.toList()..sort();
      final object = _objectCtrl.text.trim();

      AlarmModel saved;
      if (widget.alarm == null) {
        saved = await alarms.addAlarm(AlarmModel(
          id: '',
          userId: '',
          enabled: true,
          hour: _wake.hour,
          minute: _wake.minute,
          targetObject: object,
          label: 'Horario de sueño',
          daysOfWeek: days,
          createdAt: DateTime.now(),
          bedtimeHour: _bedtime.hour,
          bedtimeMinute: _bedtime.minute,
        ));
      } else {
        saved = widget.alarm!.copyWith(
          hour: _wake.hour,
          minute: _wake.minute,
          targetObject: object,
          daysOfWeek: days,
          bedtimeHour: _bedtime.hour,
          bedtimeMinute: _bedtime.minute,
        );
        await alarms.updateAlarm(saved);
      }

      final sleep = ref.read(sleepProvider.notifier);
      // Primero los ajustes que solo viven en el horario, y luego el sync con
      // la alarma: así la reprogramación de avisos ya usa los valores nuevos.
      await sleep.saveSchedule(ref.read(sleepProvider).schedule.copyWith(
            goalMinutes: _goalMinutes,
            windDownMinutes: _windDown,
            nagEnabled: _nag,
            wakeCheckEnabled: _wakeCheck,
            wakeCheckIntervalMinutes: _wakeCheckInterval,
            wakeCheckWindowMinutes: _wakeCheckWindow,
          ));
      await sleep.syncFromAlarm(saved);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, message: 'Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final alarm = widget.alarm;
    if (alarm == null) return;
    final nav = Navigator.of(context);
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: BentoTheme.darkCard,
            title: Text('Eliminar horario',
                style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w800, color: BentoTheme.cream)),
            content: Text(
              'Se borra la alarma y dejan de llegar los avisos de dormir. '
              'El historial de noches se conserva.',
              style: TextStyle(color: BentoTheme.creamAlpha(0.7)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(
                    foregroundColor: BentoTheme.creamAlpha(0.7)),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Eliminar',
                    style: TextStyle(color: BentoTheme.errorRed)),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;

    await ref.read(alarmsProvider.notifier).deleteAlarm(alarm.id);
    await ref.read(sleepProvider.notifier).syncFromAlarm(null);
    if (mounted) nav.pop();
  }

  Widget _sectionTitle(String text, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text,
            style: GoogleFonts.montserrat(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: BentoTheme.cream)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle,
              style: GoogleFonts.montserrat(
                  fontSize: 12, color: BentoTheme.creamAlpha(0.55))),
        ],
      ],
    );
  }

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child:
            Divider(height: 1, thickness: 1, color: BentoTheme.creamAlpha(0.12)),
      );

  Widget _chip(String label,
      {required bool active, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: active ? BentoTheme.accentAlarm : BentoTheme.darkCardAlt,
          border: active ? null : Border.all(color: BentoTheme.creamAlpha(0.14)),
        ),
        child: Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color:
                active ? const Color(0xFF0C0C0D) : BentoTheme.creamAlpha(0.55),
          ),
        ),
      ),
    );
  }

  bool _sameDays(Set<int> preset) =>
      _days.length == preset.length && _days.containsAll(preset);

  /// Extremo del rango: se toca para elegir cuál edita la rueda de abajo.
  Widget _endpoint({
    required String label,
    required IconData icon,
    required TimeOfDay time,
    required bool active,
    required VoidCallback onTap,
  }) {
    final h12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: active
                ? BentoTheme.accentAlarm.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active
                  ? BentoTheme.accentAlarm
                  : BentoTheme.creamAlpha(0.12),
              width: active ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon,
                      size: 13,
                      color: active
                          ? BentoTheme.accentAlarm
                          : BentoTheme.creamAlpha(0.45)),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: GoogleFonts.montserrat(
                      fontSize: 10,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? BentoTheme.accentAlarm
                          : BentoTheme.creamAlpha(0.45),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$h12:${time.minute.toString().padLeft(2, '0')}',
                    style: GoogleFonts.montserrat(
                      fontSize: 28,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                      color: BentoTheme.cream,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    time.period == DayPeriod.am ? 'AM' : 'PM',
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: BentoTheme.creamAlpha(0.55),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.alarm != null;
    final window = _windowMinutes;
    final short = window < 360;

    return Scaffold(
      backgroundColor: BentoTheme.darkBg,
      appBar: AppBar(
        backgroundColor: BentoTheme.darkBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: BentoTheme.cream),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          editing ? 'Horario de sueño' : 'Nuevo horario de sueño',
          style: GoogleFonts.montserrat(
              color: BentoTheme.cream, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (editing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: BentoTheme.errorRed),
              onPressed: _delete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // El rango completo arriba: es lo que el usuario tiene en la cabeza
            // ("de 11 a 7"), no dos horas sueltas.
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              decoration: BoxDecoration(
                color: BentoTheme.darkCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: BentoTheme.accentAlarm, width: 1.5),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _endpoint(
                        label: 'ME ACUESTO',
                        icon: Icons.bedtime_outlined,
                        time: _bedtime,
                        active: _editingBedtime,
                        onTap: () => setState(() => _editingBedtime = true),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward,
                            size: 16, color: BentoTheme.creamAlpha(0.35)),
                      ),
                      _endpoint(
                        label: 'SUENA',
                        icon: Icons.wb_sunny_outlined,
                        time: _wake,
                        active: !_editingBedtime,
                        onTap: () => setState(() => _editingBedtime = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  BentoTimePicker(
                    // La clave fuerza reconstruir la rueda al cambiar de
                    // extremo: sin ella seguiría mostrando la hora anterior.
                    key: ValueKey(_editingBedtime),
                    initialTime: _editingBedtime ? _bedtime : _wake,
                    onChanged: (t) => setState(() {
                      if (_editingBedtime) {
                        _bedtime = t;
                      } else {
                        _wake = t;
                      }
                    }),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.hotel,
                          size: 14,
                          color: short
                              ? BentoTheme.errorRed
                              : BentoTheme.accentOrange),
                      const SizedBox(width: 6),
                      Text(
                        '${formatSleepMinutes(window)} en la cama'
                        '${short ? ' · muy poco' : ''}',
                        style: GoogleFonts.montserrat(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: short
                              ? BentoTheme.errorRed
                              : BentoTheme.accentOrange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            _divider(),

            _sectionTitle(
              'Objeto a fotografiar',
              subtitle: 'La IA validará que estés con este objeto para apagar '
                  'la alarma de la mañana.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _objectCtrl,
              style: TextStyle(color: BentoTheme.cream),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Ej: Taza de café',
                hintStyle: TextStyle(color: BentoTheme.creamAlpha(0.3)),
                prefixIcon: Icon(Icons.camera_alt_outlined,
                    color: BentoTheme.creamAlpha(0.55)),
                filled: true,
                fillColor: BentoTheme.darkCardAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: BentoTheme.creamAlpha(0.14)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: BentoTheme.creamAlpha(0.14)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  borderSide:
                      BorderSide(color: BentoTheme.accentAlarm, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _objectSuggestions
                  .map((s) => _chip(s,
                      active: _objectCtrl.text == s,
                      onTap: () => setState(() => _objectCtrl.text = s)))
                  .toList(),
            ),

            _divider(),

            _sectionTitle(
              'Repetir',
              subtitle: 'Los días marcados son los de despertar.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('Todos los días',
                    active: _sameDays(_allDays),
                    onTap: () => setState(() => _days = Set.of(_allDays))),
                _chip('Lun – Vie',
                    active: _sameDays(_weekdays),
                    onTap: () => setState(() => _days = Set.of(_weekdays))),
                _chip('Fin de semana',
                    active: _sameDays(_weekend),
                    onTap: () => setState(() => _days = Set.of(_weekend))),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(7, (i) {
                final day = i + 1;
                final active = _days.contains(day);
                return GestureDetector(
                  onTap: () => setState(() {
                    if (active) {
                      _days.remove(day);
                    } else {
                      _days.add(day);
                    }
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? BentoTheme.accentAlarm
                          : BentoTheme.darkCardAlt,
                      border: active
                          ? null
                          : Border.all(color: BentoTheme.creamAlpha(0.14)),
                    ),
                    child: Center(
                      child: Text(
                        _dayLabels[i],
                        style: TextStyle(
                          color: active
                              ? const Color(0xFF0C0C0D)
                              : BentoTheme.creamAlpha(0.55),
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),

            _divider(),

            _sectionTitle(
              'Meta de sueño',
              subtitle: 'Contra esto se calculan la deuda y la racha.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in const [360, 390, 420, 450, 480, 510, 540])
                  _chip(formatSleepMinutes(m),
                      active: _goalMinutes == m,
                      onTap: () => setState(() => _goalMinutes = m)),
              ],
            ),

            _divider(),

            _sectionTitle(
              'Aviso previo',
              subtitle:
                  'Cuánto antes te avisa para que bajes luces y sueltes pantallas.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _windDownOptions
                  .map((m) => _chip(m == 0 ? 'Sin aviso' : '$m min antes',
                      active: _windDown == m,
                      onTap: () => setState(() => _windDown = m)))
                  .toList(),
            ),

            _divider(),

            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _nag,
              activeThumbColor: BentoTheme.accentAlarm,
              onChanged: (v) => setState(() => _nag = v),
              title: Text('Insistir si lo ignoro',
                  style: GoogleFonts.montserrat(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: BentoTheme.cream)),
              subtitle: Text(
                'Repite el aviso a los 15, 30 y 45 min hasta que confirmes.',
                style: GoogleFonts.montserrat(
                    fontSize: 12, color: BentoTheme.creamAlpha(0.55)),
              ),
            ),

            _divider(),

            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _wakeCheck,
              activeThumbColor: BentoTheme.accentAlarm,
              onChanged: (v) => setState(() => _wakeCheck = v),
              title: Text('Comprobar que sigo despierto',
                  style: GoogleFonts.montserrat(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: BentoTheme.cream)),
              subtitle: Text(
                'Un rato después de apagar la alarma vuelve a sonar hasta que '
                'confirmes de un toque.',
                style: GoogleFonts.montserrat(
                    fontSize: 12, color: BentoTheme.creamAlpha(0.55)),
              ),
            ),
            if (_wakeCheck) ...[
              const SizedBox(height: 16),
              _sectionTitle('Cada cuánto comprueba'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _wakeCheckIntervalOptions
                    .map((m) => _chip('$m min',
                        active: _wakeCheckInterval == m,
                        onTap: () => setState(() => _wakeCheckInterval = m)))
                    .toList(),
              ),
              const SizedBox(height: 20),
              _sectionTitle(
                'Durante cuánto rato',
                subtitle: 'Pasado este tiempo desde que apagas la alarma, '
                    'deja de vigilar.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _wakeCheckWindowOptions
                    .map((m) => _chip('$m min',
                        active: _wakeCheckWindow == m,
                        onTap: () => setState(() => _wakeCheckWindow = m)))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: BentoTheme.creamAlpha(0.12))),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: BentoTheme.accentAlarm,
                foregroundColor: const Color(0xFF0C0C0D),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF0C0C0D)))
                  : const Icon(Icons.check),
              label: Text(
                editing ? 'Guardar cambios' : 'Crear horario',
                style: GoogleFonts.montserrat(
                    fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
