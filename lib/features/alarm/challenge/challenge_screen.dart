import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/appearance_provider.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/theme/editorial_theme.dart';
import '../../../core/widgets/editorial_kit.dart';
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
class ChallengeScreen extends ConsumerStatefulWidget {
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
  ConsumerState<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends ConsumerState<ChallengeScreen> {
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

  // Dos pieles en el mismo archivo, por la misma razón que en
  // `alarm_dismiss_screen.dart`: la lógica de arriba —racha que se reinicia al
  // fallar, teclado propio porque el del sistema no aparece sobre el bloqueo—
  // es lo que hace que el reto no sea un botón de apagado, y no puede vivir por
  // duplicado.

  @override
  Widget build(BuildContext context) {
    if (ref.watch(designLanguageProvider).isEditorial) return _buildEditorial();

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

  // ─────────────────────── piel editorial ───────────────────────

  static final Color _edDanger =
      EditorialTheme.accentAt(const Color(0xFFE5484D), 0.62);

  Widget _buildEditorial() {
    final isMath = _challenge.kind == ChallengeKind.math;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: EditorialTheme.canvas,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _edHeader(),
                const SizedBox(height: 18),
                _edProgress(),
                const SizedBox(height: 22),
                Expanded(child: _edQuestion(isMath)),
                const SizedBox(height: 16),
                if (isMath) _edKeypad() else _edOptions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _edHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RETO MENTAL',
                style: EditorialTheme.caps(
                  26,
                  color: EditorialTheme.paper,
                  letterSpacing: -0.8,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                widget.reason ??
                    'Acierta ${widget.requiredCorrect} seguidas para apagar la alarma.',
                style: EditorialTheme.text(13,
                    color: EditorialTheme.muted, height: 1.35),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        EditorialPressable(
          onTap: () => Navigator.of(context).pop(false),
          scale: 0.9,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              'Volver',
              style: EditorialTheme.text(13,
                  weight: FontWeight.w600, color: EditorialTheme.muted),
            ),
          ),
        ),
      ],
    );
  }

  /// La racha, como tres barras. Es la única señal de progreso y por eso se
  /// pinta en papel pleno: en un sistema sin color de estado, "hecho" es
  /// "blanco" y "pendiente" es "apagado".
  Widget _edProgress() {
    return Row(
      children: [
        for (var i = 0; i < widget.requiredCorrect; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i < _solved
                    ? EditorialTheme.paper
                    : EditorialTheme.paperAlpha(0.12),
              ),
            ),
          ),
          if (i < widget.requiredCorrect - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }

  /// La pregunta va en papel: es lo que hay que leer, y a estas horas leer
  /// tinta sobre blanco cuesta bastante menos que al revés.
  Widget _edQuestion(bool isMath) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
        color: EditorialTheme.paper,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            isMath ? 'CÁLCULO' : 'CULTURA GENERAL',
            style: EditorialTheme.label(10.5, color: EditorialTheme.grayText),
          ),
          const SizedBox(height: 18),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _challenge.question,
              textAlign: TextAlign.center,
              style: isMath
                  ? EditorialTheme.caps(46,
                      color: EditorialTheme.ink, letterSpacing: -1.5, height: 1.1)
                  : EditorialTheme.text(23,
                      weight: FontWeight.w600,
                      color: EditorialTheme.ink,
                      height: 1.3),
            ),
          ),
          if (isMath) ...[
            const SizedBox(height: 20),
            // Lo tecleado se dibuja sobre un bloque gris para que se lea como
            // un campo y no como parte del enunciado.
            Container(
              constraints: const BoxConstraints(minWidth: 130),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: EditorialTheme.gray,
                borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
              ),
              child: Text(
                _typed.isEmpty ? '—' : _typed,
                textAlign: TextAlign.center,
                style: EditorialTheme.caps(
                  38,
                  color: _typed.isEmpty
                      ? EditorialTheme.grayText
                      : EditorialTheme.ink,
                  letterSpacing: 1,
                  height: 1.1,
                ),
              ),
            ),
          ],
          if (_wrong) ...[
            const SizedBox(height: 16),
            Text(
              'Incorrecto. Vuelta a empezar (fallos: $_mistakes).',
              textAlign: TextAlign.center,
              style: EditorialTheme.text(13,
                  weight: FontWeight.w600, color: _edDanger),
            ),
          ],
        ],
      ),
    );
  }

  /// Teclado propio y no el del sistema: sobre la pantalla de bloqueo y en modo
  /// pantalla fijada el del sistema puede no aparecer, y además así las teclas
  /// son grandes para dedos recién despiertos.
  Widget _edKeypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '<', '0', '='];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 9,
      crossAxisSpacing: 9,
      childAspectRatio: 1.9,
      children: [
        for (final key in keys)
          EditorialPressable(
            onTap: () => key == '=' ? _answer(_typed) : _tapKey(key),
            scale: 0.93,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                // El "=" es papel y el resto superficie: confirmar es la única
                // tecla que cambia de estado, y tiene que encontrarse sola.
                color: key == '='
                    ? EditorialTheme.paper
                    : EditorialTheme.surfaceHigh,
                borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
              ),
              child: key == '<'
                  ? Icon(Icons.backspace_outlined,
                      size: 21, color: EditorialTheme.paperAlpha(0.8))
                  : Text(
                      key,
                      style: EditorialTheme.caps(
                        24,
                        color: key == '='
                            ? EditorialTheme.ink
                            : EditorialTheme.paper,
                        letterSpacing: 0,
                      ),
                    ),
            ),
          ),
      ],
    );
  }

  Widget _edOptions() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in _challenge.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: EditorialPressable(
              onTap: () => _answer(option),
              scale: 0.98,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: EditorialTheme.surfaceHigh,
                  borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
                ),
                child: Text(
                  option,
                  textAlign: TextAlign.center,
                  style: EditorialTheme.text(16,
                      weight: FontWeight.w600, color: EditorialTheme.paper),
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
