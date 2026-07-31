import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

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
      _quality != null && _awakenings != null && _latency != null;

  Future<void> _submit() async {
    if (!_complete || _saving) return;
    setState(() => _saving = true);

    final result = await ref.read(sleepProvider.notifier).submitCheckIn(
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
              Text(emoji, style: const TextStyle(fontSize: 26)),
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
