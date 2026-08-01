import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/bento_theme.dart';
import 'step_numbers.dart';

/// Paso de escritura libre. Lo usan tanto "¿qué funcionó?" como "¿qué
/// estorbó?": es la misma pieza con otro texto y otro acento.
///
/// Se puede seguir sin escribir nada. Obligar a rellenar convierte el ritual en
/// un trámite, y un trámite se abandona a la tercera semana.
class StepPrompt extends StatefulWidget {
  const StepPrompt({
    super.key,
    required this.title,
    required this.subtitle,
    required this.hint,
    required this.initialValue,
    required this.accent,
    required this.onNext,
  });

  final String title;
  final String subtitle;
  final String hint;
  final String initialValue;
  final Color accent;
  final ValueChanged<String> onNext;

  @override
  State<StepPrompt> createState() => _StepPromptState();
}

class _StepPromptState extends State<StepPrompt> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              Text(
                widget.title,
                style: GoogleFonts.outfit(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: BentoTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.subtitle,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  height: 1.45,
                  color: BentoTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              NeuPressed(
                borderRadius: 18,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: TextField(
                  controller: _controller,
                  maxLines: 7,
                  minLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    height: 1.5,
                    color: BentoTheme.textPrimary,
                  ),
                  cursorColor: widget.accent,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    hintText: widget.hint,
                    hintStyle: GoogleFonts.outfit(
                      fontSize: 15,
                      color: BentoTheme.creamAlpha(0.32),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        RitualButton(
          label: 'Seguir',
          onTap: () => widget.onNext(_controller.text.trim()),
        ),
      ],
    );
  }
}
