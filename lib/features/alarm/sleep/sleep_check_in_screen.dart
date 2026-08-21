import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';

import '../../../core/models/sleep_model.dart';
import '../../../core/providers/sleep_provider.dart';
import '../../../core/providers/appearance_provider.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/theme/editorial_theme.dart';
import '../../../core/widgets/editorial_kit.dart';
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

  /// Cuánto estuviste en cama esta noche, o `null` si no hay registro.
  Duration? get _timeInBed {
    final data = ref.watch(sleepProvider);
    final key = widget.nightKey ?? nightKeyFor(DateTime.now());
    return data.sessions[key]?.timeInBed;
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(designLanguageProvider).isEditorial) return _buildEditorial();

    final inBed = _timeInBed;

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

  // ─────────────────────── piel editorial ───────────────────────
  //
  // La estructura de preguntas no cambia: cuatro, en el orden en que se
  // responden solas al despertar. Lo que cambia es que las respuestas dejan de
  // ser píldoras con borde y pasan a ser bloques que se invierten al elegirse,
  // igual que en el resto del sistema.

  static final Color _edPending =
      EditorialTheme.accentAt(const Color(0xFFF4A261), 0.75);

  Widget _buildEditorial() {
    final inBed = _timeInBed;

    return Scaffold(
      backgroundColor: EditorialTheme.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  EditorialTheme.margin,
                  26,
                  EditorialTheme.margin,
                  16,
                ),
                children: [
                  Text(
                    'BUENOS DÍAS',
                    style: EditorialTheme.caps(
                      38,
                      color: EditorialTheme.paper,
                      letterSpacing: -1.4,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    inBed == null
                        ? 'Cuatro toques y listo.'
                        : 'Estuviste ${formatSleepMinutes(inBed.inMinutes)} en la '
                            'cama. Cuatro toques y listo.',
                    style: EditorialTheme.text(14,
                        color: EditorialTheme.muted, height: 1.4),
                  ),
                  const SizedBox(height: 30),

                  _edQuestion('¿Cómo dormiste?'),
                  const SizedBox(height: 12),
                  // Las caras van en una fila repartida: son una escala, y una
                  // escala se lee de izquierda a derecha o no es una escala.
                  Row(
                    children: [
                      for (final (value, emoji, label) in _qualityFaces) ...[
                        if (value > 1) const SizedBox(width: 6),
                        Expanded(
                          child: _edFace(
                            emoji: emoji,
                            label: label,
                            active: _quality == value,
                            onTap: () => setState(() => _quality = value),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 28),

                  _edQuestion('¿Te despertaste durante la noche?'),
                  const SizedBox(height: 12),
                  _edWrap([
                    for (final (value, label) in _awakeningOptions)
                      (
                        label: label,
                        active: _awakenings == value,
                        onTap: () => setState(() => _awakenings = value),
                      ),
                  ]),
                  const SizedBox(height: 28),

                  _edQuestion('¿Cuánto tardaste en dormirte?'),
                  const SizedBox(height: 12),
                  _edWrap([
                    for (final (value, label) in _latencyOptions)
                      (
                        label: label,
                        active: _latency == value,
                        onTap: () => setState(() => _latency = value),
                      ),
                  ]),
                  const SizedBox(height: 28),

                  // Sin esta pregunta el registro diría que te levantaste a la
                  // hora de la alarma aunque siguieras dos horas en la cama.
                  _edQuestion('Tras apagar la alarma, ¿te volviste a dormir?'),
                  const SizedBox(height: 12),
                  _edWrap([
                    (
                      label: 'Me levanté de una',
                      active: _backToSleep == false,
                      onTap: () => setState(() {
                        _backToSleep = false;
                        _finalWake = null;
                      }),
                    ),
                    (
                      label: 'Sí, volví a la cama',
                      active: _backToSleep == true,
                      onTap: () {
                        setState(() => _backToSleep = true);
                        _pickFinalWake();
                      },
                    ),
                  ]),
                  if (_backToSleep == true) ...[
                    const SizedBox(height: 12),
                    _edFinalWakeRow(),
                  ],
                ],
              ),
            ),
            _edFooter(),
          ],
        ),
      ),
    );
  }

  Widget _edQuestion(String text) => Text(
        text.toUpperCase(),
        style: EditorialTheme.label(11, color: EditorialTheme.muted),
      );

  /// Una cara de la escala de calidad. El emoji no se recolorea, así que la
  /// elección la marca la superficie de debajo — papel si está elegida.
  Widget _edFace({
    required String emoji,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return EditorialPressable(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      scale: 0.9,
      child: AnimatedContainer(
        duration: EditorialTheme.motion,
        curve: EditorialTheme.curve,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: active ? EditorialTheme.paper : EditorialTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Twemoji(emoji: emoji, height: 25, width: 25),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: EditorialTheme.text(
                10.5,
                weight: FontWeight.w600,
                color: active ? EditorialTheme.ink : EditorialTheme.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _edWrap(List<({String label, bool active, VoidCallback onTap})> options) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          EditorialPressable(
            onTap: () {
              HapticFeedback.selectionClick();
              option.onTap();
            },
            scale: 0.94,
            child: AnimatedContainer(
              duration: EditorialTheme.motion,
              curve: EditorialTheme.curve,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: option.active
                    ? EditorialTheme.paper
                    : EditorialTheme.surfaceHigh,
                borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
              ),
              child: Text(
                option.label,
                style: EditorialTheme.text(
                  13.5,
                  weight: FontWeight.w600,
                  color: option.active ? EditorialTheme.ink : EditorialTheme.paper,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// La hora real de levantarse. Mientras falta, el filete ámbar avisa de que
  /// el formulario está incompleto sin bloquear nada.
  Widget _edFinalWakeRow() {
    final missing = _finalWake == null;

    return EditorialPressable(
      onTap: _pickFinalWake,
      scale: 0.98,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: EditorialTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (missing) SizedBox(width: 4, child: ColoredBox(color: _edPending)),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(missing ? 12 : 14, 13, 14, 13),
                  child: Row(
                    children: [
                      Icon(Icons.schedule, size: 16, color: EditorialTheme.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          missing
                              ? 'Elige a qué hora te levantaste'
                              : 'Te levantaste a las '
                                  '${_finalWake!.hour.toString().padLeft(2, '0')}:'
                                  '${_finalWake!.minute.toString().padLeft(2, '0')}',
                          style: EditorialTheme.text(
                            13.5,
                            weight: FontWeight.w600,
                            color: missing ? _edPending : EditorialTheme.paper,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _edFooter() {
    final ready = _complete && !_saving;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EditorialTheme.margin,
        0,
        EditorialTheme.margin,
        12,
      ),
      child: Column(
        children: [
          EditorialPressable(
            onTap: ready ? _submit : null,
            scale: 0.97,
            child: AnimatedContainer(
              duration: EditorialTheme.motion,
              padding: const EdgeInsets.symmetric(vertical: 17),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // Apagado mientras falte una respuesta: el botón dice si el
                // formulario está listo, sin necesidad de un mensaje de error.
                color: ready
                    ? EditorialTheme.paper
                    : EditorialTheme.paperAlpha(0.14),
                borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
              ),
              child: Text(
                'Guardar',
                style: EditorialTheme.text(
                  16,
                  weight: FontWeight.w600,
                  color: ready ? EditorialTheme.ink : EditorialTheme.muted,
                ),
              ),
            ),
          ),
          EditorialPressable(
            onTap: _saving ? null : _skip,
            scale: 0.94,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Saltar',
                style: EditorialTheme.text(13,
                    color: EditorialTheme.paperAlpha(0.4)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
