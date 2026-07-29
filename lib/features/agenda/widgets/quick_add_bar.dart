import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/bento_theme.dart';
import '../quick_parse.dart';

/// Barra de captura por texto con vista previa de lo interpretado.
///
/// La vista previa no es adorno: un parser que adivina sin enseñar lo que
/// entendió obliga a revisar el resultado después de guardar. Mostrando
/// "▸ Correr 06:30 – 07:15" mientras escribes, la corrección ocurre antes de
/// confirmar y no después.
class QuickAddBar extends StatefulWidget {
  /// Hora sugerida cuando la línea no dice ninguna, en minutos del día.
  final int fallbackStartMinutes;

  final Future<void> Function(ParsedBlock parsed) onSubmit;

  const QuickAddBar({
    super.key,
    required this.fallbackStartMinutes,
    required this.onSubmit,
  });

  @override
  State<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<QuickAddBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  ParsedBlock? _preview;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() => _preview = parseQuickBlock(value));
  }

  Future<void> _submit() async {
    final parsed = _preview;
    if (parsed == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(parsed);
      _controller.clear();
      setState(() => _preview = null);
      // Se mantiene el foco: planear es escribir varias líneas seguidas, y
      // recuperar el teclado entre cada una es fricción tonta.
      _focus.requestFocus();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _fmt(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _previewLabel(ParsedBlock p) {
    final start = p.startMinutes ?? widget.fallbackStartMinutes;
    final end = start + (p.durationMinutes ?? 30);
    final buffer = StringBuffer('${p.title}   ${_fmt(start)} – ${_fmt(end)}');
    if (p.location != null) buffer.write('  ·  ${p.location}');
    if (p.dayOffset == 1) buffer.write('  ·  mañana');
    if (p.dayOffset == 2) buffer.write('  ·  pasado mañana');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: BentoTheme.creamAlpha(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: preview != null ? BentoTheme.accentLime.withValues(alpha: 0.5) : BentoTheme.creamAlpha(0.12),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.bolt, size: 17, color: BentoTheme.creamAlpha(preview != null ? 0.8 : 0.35)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    onChanged: _onChanged,
                    onSubmitted: (_) => _submit(),
                    textInputAction: TextInputAction.done,
                    style: GoogleFonts.montserrat(
                      color: BentoTheme.cream,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 13),
                      border: InputBorder.none,
                      hintText: 'correr 6:30 45min @parque',
                      hintStyle: GoogleFonts.montserrat(
                        color: BentoTheme.creamAlpha(0.3),
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                if (preview != null)
                  GestureDetector(
                    onTap: _submitting ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: _submitting
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: BentoTheme.accentLime),
                            )
                          : Icon(Icons.arrow_forward_rounded, size: 19, color: BentoTheme.accentLime),
                    ),
                  ),
              ],
            ),
          ),
          if (preview != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 6),
              child: Row(
                children: [
                  Text('▸ ', style: GoogleFonts.montserrat(fontSize: 11.5, color: BentoTheme.accentLime)),
                  Expanded(
                    child: Text(
                      _previewLabel(preview),
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.montserrat(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: BentoTheme.creamAlpha(0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
