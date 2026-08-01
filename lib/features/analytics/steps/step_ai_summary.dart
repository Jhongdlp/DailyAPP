import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/bento_theme.dart';
import 'step_numbers.dart';

/// Paso final: la lectura que hace el modelo y el foco de la semana que viene.
///
/// El resumen de IA es opcional de verdad. El servidor de Ollama es una máquina
/// remota que puede estar apagada, y una revisión semanal que no se puede
/// cerrar sin red no sirve para nada: si falla, se dice y se sigue.
class StepAiSummary extends StatefulWidget {
  const StepAiSummary({
    super.key,
    required this.initialSummary,
    required this.initialFocus,
    required this.generate,
    required this.onSummaryChanged,
    required this.onFocusChanged,
    required this.onFinish,
  });

  final String initialSummary;
  final String initialFocus;
  final Future<String> Function() generate;
  final ValueChanged<String> onSummaryChanged;
  final ValueChanged<String> onFocusChanged;
  final VoidCallback onFinish;

  @override
  State<StepAiSummary> createState() => _StepAiSummaryState();
}

class _StepAiSummaryState extends State<StepAiSummary> {
  late final TextEditingController _focusController =
      TextEditingController(text: widget.initialFocus);

  late String _summary = widget.initialSummary;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Si se llega por primera vez, se pide sola: hacer que el usuario pulse un
    // botón para algo que siempre va a querer es un paso de más.
    if (_summary.isEmpty) _generate();
  }

  @override
  void dispose() {
    _focusController.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final text = await widget.generate();
      if (!mounted) return;

      setState(() => _summary = text.trim());
      widget.onSummaryChanged(_summary);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No pude conectar con el servidor de IA.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                'Cierra la semana',
                style: GoogleFonts.outfit(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: BentoTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 18),
              _summaryCard(),
              const SizedBox(height: 22),
              Text(
                'Una sola cosa para la semana que viene',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: BentoTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Una. Tres cosas es no elegir ninguna.',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: BentoTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              NeuPressed(
                borderRadius: 18,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: TextField(
                  controller: _focusController,
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: widget.onFocusChanged,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    height: 1.5,
                    color: BentoTheme.textPrimary,
                  ),
                  cursorColor: BentoTheme.accentBlue,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    hintText: 'La semana que viene voy a…',
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
          label: 'Cerrar la revisión',
          onTap: () {
            widget.onFocusChanged(_focusController.text.trim());
            widget.onFinish();
          },
        ),
      ],
    );
  }

  Widget _summaryCard() {
    return NeuCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 15,
                color: BentoTheme.accentBlue,
              ),
              const SizedBox(width: 8),
              Text(
                'Lectura de la semana',
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: BentoTheme.textSecondary,
                ),
              ),
              const Spacer(),
              if (!_loading)
                GestureDetector(
                  onTap: _generate,
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: BentoTheme.creamAlpha(0.45),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: BentoTheme.accentBlue,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Leyendo tus números…',
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    color: BentoTheme.textSecondary,
                  ),
                ),
              ],
            )
          else if (_error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _error!,
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    height: 1.45,
                    color: BentoTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Puedes cerrar la revisión igual: lo que escribiste se guarda.',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: BentoTheme.creamAlpha(0.42),
                  ),
                ),
              ],
            )
          else
            Text(
              _summary.isEmpty ? 'Sin resumen.' : _summary,
              style: GoogleFonts.outfit(
                fontSize: 14.5,
                height: 1.5,
                color: BentoTheme.textPrimary,
              ),
            ),
        ],
      ),
    );
  }
}
