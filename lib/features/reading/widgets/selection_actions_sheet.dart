import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/book_highlight_model.dart';
import '../../../core/network/local_ai_client.dart';
import '../../../core/providers/book_highlights_provider.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../core/providers/reader_theme_provider.dart';
import '../../../core/providers/reading_stats_provider.dart';
import '../../../core/providers/settings_provider.dart';
import 'reader_sheet.dart';

/// Qué se le puede pedir a la IA sobre un fragmento seleccionado.
enum _AiAction {
  explain('Explícame esto', Icons.lightbulb_outline),
  translate('Traducir', Icons.translate),
  context('Dame contexto', Icons.history_edu_outlined);

  const _AiAction(this.label, this.icon);

  final String label;
  final IconData icon;

  String prompt(String fragment, String bookTitle) => switch (this) {
        _AiAction.explain =>
          'Explica de forma clara y breve este fragmento del libro "$bookTitle":\n\n"""$fragment"""',
        _AiAction.translate =>
          'Traduce al español este fragmento, manteniendo el tono del original. '
              'Responde solo con la traducción:\n\n"""$fragment"""',
        _AiAction.context =>
          'Da el contexto necesario para entender este fragmento del libro '
              '"$bookTitle": a qué se refiere, qué conceptos o referencias '
              'aparecen. Sé breve:\n\n"""$fragment"""',
      };
}

/// Acciones sobre el texto que el usuario acaba de seleccionar: resaltar,
/// mandarlo a las notas o preguntarle a la IA local.
Future<void> showSelectionActionsSheet(
  BuildContext context, {
  required ReaderPalette palette,
  required String bookId,
  required String bookTitle,
  required String selectedText,
  String? position,
  int? paragraphIndex,
  String? chapterTitle,
}) {
  return showReaderSheet(
    context,
    palette: palette,
    expand: true,
    builder: (_) => _SelectionActionsSheet(
      palette: palette,
      bookId: bookId,
      bookTitle: bookTitle,
      selectedText: selectedText,
      position: position,
      paragraphIndex: paragraphIndex,
      chapterTitle: chapterTitle,
    ),
  );
}

class _SelectionActionsSheet extends ConsumerStatefulWidget {
  final ReaderPalette palette;
  final String bookId;
  final String bookTitle;
  final String selectedText;
  final String? position;
  final int? paragraphIndex;
  final String? chapterTitle;

  const _SelectionActionsSheet({
    required this.palette,
    required this.bookId,
    required this.bookTitle,
    required this.selectedText,
    this.position,
    this.paragraphIndex,
    this.chapterTitle,
  });

  @override
  ConsumerState<_SelectionActionsSheet> createState() =>
      _SelectionActionsSheetState();
}

class _SelectionActionsSheetState extends ConsumerState<_SelectionActionsSheet> {
  String? _aiAnswer;
  bool _aiLoading = false;
  String? _aiError;

  ReaderPalette get palette => widget.palette;

  Future<void> _highlight(HighlightColor color) async {
    await ref.read(bookHighlightsProvider.notifier).addHighlight(
          bookId: widget.bookId,
          text: widget.selectedText,
          color: color,
          position: widget.position,
          paragraphIndex: widget.paragraphIndex,
          chapterTitle: widget.chapterTitle,
        );
    ref.read(readingStatsProvider.notifier).registerHighlight();

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fragmento resaltado')),
    );
  }

  /// Manda el fragmento a la Máquina de Conocimiento: la nota se embebe y
  /// aparece conectada con el resto del segundo cerebro.
  Future<void> _saveAsNote() async {
    final fragment = widget.selectedText;
    final title = fragment.length <= 60
        ? fragment
        : '${fragment.substring(0, 57).trimRight()}…';

    final chapterLine =
        widget.chapterTitle == null ? '' : ' — ${widget.chapterTitle}';
    final content = '> $fragment\n\n'
        '— *${widget.bookTitle}*$chapterLine';

    final note = await ref.read(notesProvider.notifier).addNote(title, content);

    final highlight = await ref.read(bookHighlightsProvider.notifier).addHighlight(
          bookId: widget.bookId,
          text: fragment,
          position: widget.position,
          paragraphIndex: widget.paragraphIndex,
          chapterTitle: widget.chapterTitle,
          noteId: note.id,
        );
    ref.read(readingStatsProvider.notifier).registerHighlight();

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Guardado en notas (${highlight.color.label})')),
    );
  }

  Future<void> _askAi(_AiAction action) async {
    setState(() {
      _aiLoading = true;
      _aiAnswer = '';
      _aiError = null;
    });

    final settings = ref.read(settingsProvider);
    final client = LocalAIClient(
      baseUrl: settings.localAiUrl,
      textModelName: settings.textModel,
    );

    try {
      final stream = client.askTextStream(
        action.prompt(widget.selectedText, widget.bookTitle),
        systemPrompt:
            'Eres un acompañante de lectura. Respondes en español, breve y '
            'directo, sin repetir el fragmento entero.',
      );
      await for (final token in stream) {
        if (!mounted) return;
        setState(() => _aiAnswer = (_aiAnswer ?? '') + token);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _aiError =
            'No se pudo contactar el servidor de IA. Revisa que Ollama esté activo.');
      }
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReaderSheetTitle(text: 'Fragmento', palette: palette),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              widget.selectedText,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.montserrat(
                color: palette.foregroundAlpha(0.8),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _sectionLabel('Resaltar'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final color in HighlightColor.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _highlight(color),
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.color.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.hub_outlined,
                  label: 'Guardar en notas',
                  onTap: _saveAsNote,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionButton(
                  icon: Icons.copy_all_outlined,
                  label: 'Copiar',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.selectedText));
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _sectionLabel('Preguntar a la IA'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final action in _AiAction.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _actionButton(
                      icon: action.icon,
                      label: action.label,
                      onTap: _aiLoading ? null : () => _askAi(action),
                    ),
                  ),
                ),
            ],
          ),
          if (_aiLoading || _aiAnswer != null || _aiError != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: _aiError != null
                    ? Text(
                        _aiError!,
                        style: GoogleFonts.montserrat(
                          color: palette.foregroundAlpha(0.7),
                          fontSize: 12.5,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((_aiAnswer ?? '').isNotEmpty)
                            SelectableText(
                              _aiAnswer!,
                              style: GoogleFonts.montserrat(
                                color: palette.foregroundAlpha(0.85),
                                fontSize: 13,
                                height: 1.55,
                              ),
                            ),
                          if (_aiLoading)
                            Padding(
                              padding: EdgeInsets.only(
                                  top: (_aiAnswer ?? '').isEmpty ? 0 : 10),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: palette.foregroundAlpha(0.5),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Pensando…',
                                    style: GoogleFonts.montserrat(
                                      color: palette.foregroundAlpha(0.5),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: GoogleFonts.montserrat(
          color: palette.foregroundAlpha(0.55),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      );

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.foregroundAlpha(0.18)),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 18,
                color: palette.foregroundAlpha(enabled ? 0.75 : 0.3)),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: GoogleFonts.montserrat(
                color: palette.foregroundAlpha(enabled ? 0.8 : 0.35),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
