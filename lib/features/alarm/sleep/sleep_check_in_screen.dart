import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';

import '../../../core/models/sleep_model.dart';
import '../../../core/providers/sleep_provider.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/widgets/rpg_celebration.dart';

/// Check-in de tres toques justo después de apagar la alarma.
///
/// La duración se mide sola, pero la calidad percibida no: sin ella no hay
/// forma de responder "¿cuántas horas necesito yo?", que es la pregunta que de
/// verdad cambia el comportamiento. Por eso se pide aquí, medio dormido pero
/// con el recuerdo fresco, y no más tarde.
class SleepCheckInScreen extends ConsumerStatefulWidget {
  /// Noche a la que pertenece el check-in. Por defecto, la de esta mañana.
  final String? nightKey;

  const SleepCheckInScreen({super.key, this.nightKey});

  @override
  ConsumerState<SleepCheckInScreen> createState() => _SleepCheckInScreenState();
}

class _SleepCheckInScreenState extends ConsumerState<SleepCheckInScreen> {
  int? _quality;
  int? _awakenings;
  int? _latency;
  bool _saving = false;

  /// `null` = sin responder, `false` = me levanté de una, `true` = volví a
  /// dormirme (y entonces hace falta la hora real).
  bool? _backToSleep;
  TimeOfDay? _finalWake;

  static const _qualityFaces = [
    (1, '😵', 'Fatal'),
    (2, '😪', 'Mal'),
    (3, '😐', 'Normal'),
    (4, '🙂', 'Bien'),
    (5, '😄', 'Genial'),
  ];

  static const _awakeningOptions = [
    (0, 'Ninguna'),
    (1, '1 vez'),
    (2, '2 veces'),
    (3, '3 o más'),
  ];

  // Puntos medios de cada tramo: la latencia se usa para descontar del tiempo
  // en cama, así que necesita un número, no una etiqueta.
  static const _latencyOptions = [
    (7, 'Al instante'),
    (22, '15–30 min'),
    (45, '30–60 min'),
    (75, 'Más de 1 h'),
  ];

  bool get _complete =>
      _quality != null &&
      _awakenings != null &&
      _latency != null &&
      // Decir que te volviste a dormir sin la hora dejaría la noche peor que
      // no responder: sabríamos que el dato está mal pero no cuál es el bueno.
      (_backToSleep != true || _finalWake != null);

  Future<void> _submit() async {
    if (!_complete || _saving) return;
    setState(() => _saving = true);

    final notifier = ref.read(sleepProvider.notifier);

    // El "me volví a dormir" va antes del check-in: cambia la duración de la
    // noche, y el premio se calcula con ella.
    if (_backToSleep == true && _finalWake != null) {
      await notifier.registerBackToSleep(
        finalWakeAt: _resolveFinalWake(_finalWake!),
        nightKey: widget.nightKey,
      );
    }

    final result = await notifier.submitCheckIn(
      quality: _quality!,
      awakenings: _awakenings!,
      latencyMinutes: _latency!,
      nightKey: widget.nightKey,
    );

    if (!mounted) return;
    if (result != null) {
      RpgCelebration.show(
        context,
        xp: result['xpGained'] as int,
        gold: result['goldGained'] as int,
        levelUp: result['levelUp'] as bool,
        newLevel: result['newLevel'] as int?,
      );
      AchievementToast.show(context, result['unlocked']);
      await Future.delayed(const Duration(milliseconds: 900));
    }
    if (mounted) Navigator.pop(context);
  }

  /// Convierte la hora elegida en un instante del día del despertar.
  DateTime _resolveFinalWake(TimeOfDay time) {
    final key = widget.nightKey ?? nightKeyFor(DateTime.now());
    final date = ref.read(sleepProvider).sessions[key]?.date ?? DateTime.now();
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickFinalWake() async {
    final session =
        ref.read(sleepProvider).sessions[widget.nightKey ?? nightKeyFor(DateTime.now())];
    final picked = await showTimePicker(
      context: context,
      // Arranca en la hora en que apagaste la alarma: lo que se pide es cuánto
      // más tarde te levantaste, no una hora en abstracto.
      initialTime: _finalWake ??
          (session?.wokeAt != null
              ? TimeOfDay.fromDateTime(session!.wokeAt!)
              : TimeOfDay.now()),
      helpText: '¿A qué hora te levantaste de verdad?',
    );
    if (picked != null && mounted) setState(() => _finalWake = picked);
  }

  Future<void> _skip() async {
    await ref.read(sleepProvider.notifier).skipCheckIn(nightKey: widget.nightKey);
    if (mounted) Navigator.pop(context);
  }

  Widget _question(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          text,
          style: GoogleFonts.montserrat(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: BentoTheme.cream,
          ),
        ),
      );

  Widget _option({
    required String label,
    required bool active,
    required VoidCallback onTap,
    String? emoji,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: emoji == null ? 14 : 10,
          vertical: emoji == null ? 10 : 8,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(emoji == null ? 20 : 16),
          color: active ? BentoTheme.accentAlarm : BentoTheme.darkCardAlt,
          border: active ? null : Border.all(color: BentoTheme.creamAlpha(0.14)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null) ...[
              Twemoji(emoji: emoji, height: 26, width: 26),
              const SizedBox(height: 2),
            ],
            Text(
              label,
              style: GoogleFonts.montserrat(
                fontSize: emoji == null ? 13 : 10,
                fontWeight: FontWeight.w700,
                color: active
                    ? const Color(0xFF0C0C0D)
                    : BentoTheme.creamAlpha(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(sleepProvider);
    final key = widget.nightKey ?? nightKeyFor(DateTime.now());
    final session = data.sessions[key];
    final inBed = session?.timeInBed;

    return Scaffold(
      backgroundColor: BentoTheme.darkBg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Buenos días',
                        style: GoogleFonts.montserrat(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                          letterSpacing: -1,
                          color: BentoTheme.cream,
                        )),
                    const SizedBox(height: 8),
                    Text(
                      inBed == null
                          ? 'Tres toques y listo.'
                          : 'Estuviste ${formatSleepMinutes(inBed.inMinutes)} '
                              'en la cama. Tres toques y listo.',
                      style: GoogleFonts.montserrat(
                        fontSize: 14,
                        color: BentoTheme.creamAlpha(0.55),
                      ),
                    ),
                    const SizedBox(height: 32),

                    _question('¿Cómo dormiste?'),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final (value, emoji, label) in _qualityFaces)
                          _option(
                            emoji: emoji,
                            label: label,
                            active: _quality == value,
                            onTap: () => setState(() => _quality = value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    _question('¿Te despertaste durante la noche?'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (value, label) in _awakeningOptions)
                          _option(
                            label: label,
                            active: _awakenings == value,
                            onTap: () => setState(() => _awakenings = value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    _question('¿Cuánto tardaste en dormirte?'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (value, label) in _latencyOptions)
                          _option(
                            label: label,
                            active: _latency == value,
                            onTap: () => setState(() => _latency = value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Sin esta pregunta el registro diría que te levantaste a
                    // la hora de la alarma aunque siguieras dos horas en cama.
                    _question('Tras apagar la alarma, ¿te volviste a dormir?'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _option(
                          label: 'Me levanté de una',
                          active: _backToSleep == false,
                          onTap: () => setState(() {
                            _backToSleep = false;
                            _finalWake = null;
                          }),
                        ),
                        _option(
                          label: 'Sí, volví a la cama',
                          active: _backToSleep == true,
                          onTap: () {
                            setState(() => _backToSleep = true);
                            _pickFinalWake();
                          },
                        ),
                      ],
                    ),
                    if (_backToSleep == true) ...[
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: _pickFinalWake,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: BentoTheme.darkCardAlt,
                            border: Border.all(
                              color: _finalWake == null
                                  ? BentoTheme.accentOrange
                                  : BentoTheme.creamAlpha(0.14),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.schedule,
                                  size: 16, color: BentoTheme.creamAlpha(0.55)),
                              const SizedBox(width: 10),
                              Text(
                                _finalWake == null
                                    ? 'Elige a qué hora te levantaste'
                                    : 'Te levantaste a las '
                                        '${_finalWake!.hour.toString().padLeft(2, '0')}:'
                                        '${_finalWake!.minute.toString().padLeft(2, '0')}',
                                style: GoogleFonts.montserrat(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _finalWake == null
                                      ? BentoTheme.accentOrange
                                      : BentoTheme.cream,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _complete && !_saving ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BentoTheme.accentAlarm,
                        foregroundColor: const Color(0xFF0C0C0D),
                        disabledBackgroundColor: BentoTheme.creamAlpha(0.08),
                        disabledForegroundColor: BentoTheme.creamAlpha(0.3),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                      child: Text(
                        'Guardar',
                        style: GoogleFonts.montserrat(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving ? null : _skip,
                    child: Text(
                      'Saltar',
                      style: GoogleFonts.montserrat(
                        fontSize: 13,
                        color: BentoTheme.creamAlpha(0.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
