import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/sleep_model.dart';
import '../../../core/providers/sleep_provider.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/utils/error_snackbar.dart';
import '../widgets/bento_time_picker.dart';

/// Configuración del horario de sueño: a qué hora hay que acostarse, cuánto
/// hay que dormir y en qué días. De aquí salen todas las notificaciones y la
/// meta contra la que se miden las analíticas.
class SleepScheduleForm extends ConsumerStatefulWidget {
  const SleepScheduleForm({super.key});

  @override
  ConsumerState<SleepScheduleForm> createState() => _SleepScheduleFormState();
}

class _SleepScheduleFormState extends ConsumerState<SleepScheduleForm> {
  late TimeOfDay _bedtime;
  late Set<int> _days;
  late int _goalMinutes;
  late int _windDown;
  late bool _nag;
  late bool _enabled;
  late bool _wakeCheck;
  late int _wakeCheckInterval;
  late int _wakeCheckWindow;
  bool _saving = false;

  static const _dayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
  static const _weekdays = {1, 2, 3, 4, 5};
  static const _weekend = {6, 7};
  static const _allDays = {1, 2, 3, 4, 5, 6, 7};

  /// Metas en el rango que recomienda la literatura para adultos (7–9 h), más
  /// los extremos que la gente usa de verdad.
  static const _goalOptions = [360, 390, 420, 450, 480, 510, 540];
  static const _windDownOptions = [0, 15, 30, 45, 60];
  static const _wakeCheckIntervalOptions = [5, 10, 15, 20];
  static const _wakeCheckWindowOptions = [20, 40, 60, 90];

  @override
  void initState() {
    super.initState();
    final s = ref.read(sleepProvider).schedule;
    _bedtime = TimeOfDay(hour: s.bedtimeHour, minute: s.bedtimeMinute);
    _days = Set.of(s.daysOfWeek);
    _goalMinutes = s.goalMinutes;
    _windDown = s.windDownMinutes;
    _nag = s.nagEnabled;
    _wakeCheck = s.wakeCheckEnabled;
    _wakeCheckInterval = s.wakeCheckIntervalMinutes;
    _wakeCheckWindow = s.wakeCheckWindowMinutes;
    _enabled = true; // entrar aquí a guardar implica querer activarlo
  }

  /// Hora a la que tendrías que despertarte para cumplir la meta.
  String get _wakePreview {
    final bed = DateTime(2000, 1, 1, _bedtime.hour, _bedtime.minute);
    final wake = bed.add(Duration(minutes: _goalMinutes));
    return '${wake.hour.toString().padLeft(2, '0')}:'
        '${wake.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (_days.isEmpty) {
      showErrorSnackBar(context, message: 'Selecciona al menos un día');
      return;
    }
    setState(() => _saving = true);
    try {
      final days = _days.toList()..sort();
      await ref.read(sleepProvider.notifier).saveSchedule(
            SleepSchedule(
              enabled: _enabled,
              bedtimeHour: _bedtime.hour,
              bedtimeMinute: _bedtime.minute,
              windDownMinutes: _windDown,
              goalMinutes: _goalMinutes,
              daysOfWeek: days,
              nagEnabled: _nag,
              wakeCheckEnabled: _wakeCheck,
              wakeCheckIntervalMinutes: _wakeCheckInterval,
              wakeCheckWindowMinutes: _wakeCheckWindow,
            ),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, message: 'Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

  @override
  Widget build(BuildContext context) {
    final hasSchedule = ref.watch(sleepProvider).schedule.enabled;

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
          'Horario de sueño',
          style: GoogleFonts.montserrat(
              color: BentoTheme.cream, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (hasSchedule)
            IconButton(
              tooltip: 'Desactivar',
              icon: const Icon(Icons.notifications_off_outlined,
                  color: BentoTheme.errorRed),
              onPressed: () async {
                await ref.read(sleepProvider.notifier).saveSchedule(
                      ref
                          .read(sleepProvider)
                          .schedule
                          .copyWith(enabled: false),
                    );
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: BentoTheme.darkCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: BentoTheme.accentAlarm, width: 1.5),
              ),
              child: Column(
                children: [
                  BentoTimePicker(
                    initialTime: _bedtime,
                    onChanged: (t) => setState(() => _bedtime = t),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wb_twilight,
                          size: 14, color: BentoTheme.accentOrange),
                      const SizedBox(width: 6),
                      Text(
                        'Despertarías a las $_wakePreview',
                        style: GoogleFonts.montserrat(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: BentoTheme.accentOrange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            _divider(),

            _sectionTitle(
              'Cuánto quieres dormir',
              subtitle:
                  'Es la meta contra la que se calculan la deuda y la racha. '
                  'El panel te dirá con el tiempo cuánto necesitas de verdad.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _goalOptions
                  .map((m) => _chip(formatSleepMinutes(m),
                      active: _goalMinutes == m,
                      onTap: () => setState(() => _goalMinutes = m)))
                  .toList(),
            ),

            _divider(),

            _sectionTitle('Repetir'),
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
                'confirmes de un toque. Es lo que impide volver a la cama.',
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
                'Guardar horario',
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
