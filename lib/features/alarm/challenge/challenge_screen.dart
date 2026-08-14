import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/bento_theme.dart';
import 'mental_challenge.dart';

/// Reto mental para apagar la alarma sin foto.
///
/// Es la alternativa a la cámara: sirve cuando el objeto no está a mano, cuando
/// el servidor de IA no responde, o simplemente cuando prefieres despertarte
/// pensando. Devuelve `true` por `Navigator.pop` si se supera.
///
/// Hay que acertar [requiredCorrect] seguidas: con una sola, un acierto por
/// azar en una pregunta de opción múltiple sería un botón de apagado. Un fallo
/// devuelve el contador a cero.
class ChallengeScreen extends StatefulWidget {
  /// Cuántos aciertos seguidos hacen falta.
  final int requiredCorrect;

  /// Texto que explica por qué se llegó aquí (p.ej. la IA no respondió).
  final String? reason;

  const ChallengeScreen({
    super.key,
    this.requiredCorrect = 3,
    this.reason,
  });

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  late MentalChallenge _challenge = MentalChallenges.next();
  String _typed = '';
  int _solved = 0;
  int _mistakes = 0;
  bool _wrong = false;

  void _answer(String given) {
    if (given.trim().isEmpty) return;
    if (_challenge.isCorrect(given)) {
      HapticFeedback.mediumImpact();
      final solved = _solved + 1;
      if (solved >= widget.requiredCorrect) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _solved = solved;
        _wrong = false;
        _typed = '';
        _challenge = MentalChallenges.next();
      });
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _mistakes++;
        _wrong = true;
        _solved = 0; // Volver a empezar: la racha es el reto.
        _typed = '';
        _challenge = MentalChallenges.next();
      });
    }
  }

  void _tapKey(String key) {
    setState(() {
      _wrong = false;
      if (key == '<') {
        if (_typed.isNotEmpty) {
          _typed = _typed.substring(0, _typed.length - 1);
        }
      } else if (_typed.length < 8) {
        _typed += key;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMath = _challenge.kind == ChallengeKind.math;

    return PopScope(
      // Igual que la pantalla de la alarma: salir con Atrás sería la escapatoria
      // obvia de alguien medio dormido.
      canPop: false,
      child: Scaffold(
        backgroundColor: BentoTheme.darkBg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                const SizedBox(height: 18),
                _progress(),
                const SizedBox(height: 24),
                Expanded(child: _questionCard(isMath)),
                const SizedBox(height: 16),
                if (isMath) _keypad() else _options(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Icon(Icons.psychology_alt_outlined,
            color: BentoTheme.accentAlarm, size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reto mental',
                style: GoogleFonts.montserrat(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: BentoTheme.cream,
                ),
              ),
              Text(
                widget.reason ??
                    'Acierta ${widget.requiredCorrect} seguidas para apagar la alarma.',
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  height: 1.35,
                  color: BentoTheme.creamAlpha(0.55),
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Volver',
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: BentoTheme.creamAlpha(0.45),
            ),
          ),
        ),
      ],
    );
  }

  Widget _progress() {
    return Row(
      children: [
        for (var i = 0; i < widget.requiredCorrect; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i < _solved
                    ? BentoTheme.successGreen
                    : BentoTheme.creamAlpha(0.12),
              ),
            ),
          ),
          if (i < widget.requiredCorrect - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }

  Widget _questionCard(bool isMath) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: BentoTheme.creamAlpha(0.06),
        border: Border.all(
          color: _wrong
              ? BentoTheme.errorRed
              : BentoTheme.creamAlpha(0.14),
          width: _wrong ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _challenge.kind == ChallengeKind.math
                ? 'CÁLCULO'
                : 'CULTURA GENERAL',
            style: GoogleFonts.montserrat(
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w800,
              color: BentoTheme.accentAlarm,
            ),
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _challenge.question,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: isMath ? 40 : 22,
                height: 1.25,
                fontWeight: FontWeight.w800,
                color: BentoTheme.cream,
              ),
            ),
          ),
          if (isMath) ...[
            const SizedBox(height: 22),
            Text(
              _typed.isEmpty ? '—' : _typed,
              style: GoogleFonts.montserrat(
                fontSize: 42,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: _typed.isEmpty
                    ? BentoTheme.creamAlpha(0.25)
                    : BentoTheme.accentAlarm,
              ),
            ),
          ],
          if (_wrong) ...[
            const SizedBox(height: 14),
            Text(
              'Incorrecto. Vuelta a empezar (fallos: $_mistakes).',
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: BentoTheme.errorRed,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Teclado propio en lugar del del sistema: sobre la pantalla de bloqueo y en
  /// modo pantalla fijada el teclado del sistema puede no aparecer, y además
  /// así los botones son grandes para dedos recién despiertos.
  Widget _keypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '<', '0', '='];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.9,
      children: [
        for (final key in keys)
          _KeypadButton(
            label: key,
            accent: key == '=',
            onTap: () => key == '=' ? _answer(_typed) : _tapKey(key),
          ),
      ],
    );
  }

  Widget _options() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in _challenge.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _answer(option),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BentoTheme.creamAlpha(0.08),
                  foregroundColor: BentoTheme.cream,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: BentoTheme.creamAlpha(0.14)),
                  ),
                ),
                child: Text(
                  option,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  final String label;
  final bool accent;
  final VoidCallback onTap;

  const _KeypadButton({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent ? BentoTheme.accentAlarm : BentoTheme.creamAlpha(0.08),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: label == '<'
              ? Icon(Icons.backspace_outlined,
                  color: BentoTheme.cream, size: 22)
              : Text(
                  label,
                  style: GoogleFonts.montserrat(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: accent
                        ? const Color(0xFF0C0C0D)
                        : BentoTheme.cream,
                  ),
                ),
        ),
      ),
    );
  }
}
