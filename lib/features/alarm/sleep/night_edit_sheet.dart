import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/sleep_model.dart';
import '../../../core/providers/sleep_provider.dart';
import '../../../core/theme/bento_theme.dart';

/// Corrección manual de las horas de una noche.
///
/// Existe porque la captura automática falla de formas previsibles: te dormiste
/// sin confirmar el bedtime, apagaste la alarma y seguiste en la cama, o el
/// móvil se quedó sin batería. Sin una forma de arreglarlo a mano, un fallo
/// suelto contamina las medias durante dos semanas.
class NightEditSheet extends ConsumerStatefulWidget {
  final SleepSession session;

  const NightEditSheet({super.key, required this.session});

  static Future<void> show(BuildContext context, SleepSession session) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => NightEditSheet(session: session),
    );
  }

  @override
  ConsumerState<NightEditSheet> createState() => _NightEditSheetState();
}

class _NightEditSheetState extends ConsumerState<NightEditSheet> {
  late TimeOfDay? _lightsOut;
  late TimeOfDay? _woke;
  late TimeOfDay? _finalWake;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    _lightsOut =
        s.lightsOutAt == null ? null : TimeOfDay.fromDateTime(s.lightsOutAt!);
    _woke = s.wokeAt == null ? null : TimeOfDay.fromDateTime(s.wokeAt!);
    _finalWake =
        s.finalWakeAt == null ? null : TimeOfDay.fromDateTime(s.finalWakeAt!);
  }

  /// Une la hora elegida con el día que le corresponde. Acostarse a partir de
  /// las 18:00 pertenece a la víspera; todo lo demás, al día del despertar.
  DateTime _resolve(TimeOfDay time, {required bool isBedtime}) {
    final date = widget.session.date;
    final base = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (isBedtime && time.hour >= 18) {
      return base.subtract(const Duration(days: 1));
    }
    return base;
  }

  Future<void> _pick({
    required TimeOfDay? current,
    required String help,
    required ValueChanged<TimeOfDay> onPicked,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: current ?? TimeOfDay.now(),
      helpText: help,
    );
    if (picked != null && mounted) setState(() => onPicked(picked));
  }

  /// Previsualiza la duración con los valores que hay ahora en el formulario,
  /// para que el usuario vea el efecto de su corrección antes de guardar.
  String get _preview {
    if (_lightsOut == null || _woke == null) return '—';
    final start = _resolve(_lightsOut!, isBedtime: true);
    final end = _resolve(_finalWake ?? _woke!, isBedtime: false);
    final preview = widget.session.copyWith(
      lightsOutAt: start,
      wokeAt: end,
      clearFinalWake: true,
    );
    return formatSleepMinutes(preview.sleepMinutes);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    await ref.read(sleepProvider.notifier).editNight(
          nightKey: widget.session.nightKey,
          lightsOutAt:
              _lightsOut == null ? null : _resolve(_lightsOut!, isBedtime: true),
          wokeAt: _woke == null ? null : _resolve(_woke!, isBedtime: false),
          finalWakeAt: _finalWake == null
              ? null
              : _resolve(_finalWake!, isBedtime: false),
          clearFinalWake: _finalWake == null,
        );

    if (mounted) Navigator.pop(context);
  }

  Widget _row({
    required String label,
    required String hint,
    required TimeOfDay? value,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: BentoTheme.darkCardAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: BentoTheme.creamAlpha(0.12)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    color: BentoTheme.creamAlpha(0.6),
                  ),
                ),
              ),
              Text(
                value == null
                    ? hint
                    : '${value.hour.toString().padLeft(2, '0')}:'
                        '${value.minute.toString().padLeft(2, '0')}',
                style: GoogleFonts.montserrat(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: value == null
                      ? BentoTheme.creamAlpha(0.3)
                      : BentoTheme.cream,
                ),
              ),
              if (onClear != null && value != null)
                GestureDetector(
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Icon(Icons.clear,
                        size: 16, color: BentoTheme.creamAlpha(0.4)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final date = widget.session.date;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: BentoTheme.darkCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: BentoTheme.creamAlpha(0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Noche del ${date.day}/${date.month}',
                  style: GoogleFonts.montserrat(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: BentoTheme.cream,
                  ),
                ),
              ),
              Text(
                _preview,
                style: GoogleFonts.montserrat(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: BentoTheme.accentAlarm,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _row(
            label: 'Me acosté',
            hint: 'Sin dato',
            value: _lightsOut,
            onTap: () => _pick(
              current: _lightsOut,
              help: '¿A qué hora te acostaste?',
              onPicked: (t) => _lightsOut = t,
            ),
          ),
          _row(
            label: 'Apagué la alarma',
            hint: 'Sin dato',
            value: _woke,
            onTap: () => _pick(
              current: _woke,
              help: '¿A qué hora apagaste la alarma?',
              onPicked: (t) => _woke = t,
            ),
          ),
          _row(
            label: 'Me levanté de verdad',
            hint: 'No volví a dormirme',
            value: _finalWake,
            onClear: () => setState(() => _finalWake = null),
            onTap: () => _pick(
              current: _finalWake ?? _woke,
              help: '¿A qué hora te levantaste de verdad?',
              onPicked: (t) => _finalWake = t,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Rellena la última solo si tras apagar la alarma te volviste a '
            'dormir; es lo que hace que la duración sea real.',
            style: GoogleFonts.montserrat(
              fontSize: 11,
              height: 1.4,
              color: BentoTheme.creamAlpha(0.4),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: BentoTheme.accentAlarm,
              foregroundColor: const Color(0xFF0C0C0D),
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(
              'Guardar',
              style: GoogleFonts.montserrat(
                  fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
