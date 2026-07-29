import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/models/book_highlight_model.dart';
import '../../../core/providers/book_highlights_provider.dart';
import '../../../core/providers/reader_theme_provider.dart';
import 'reader_sheet.dart';

/// Lista de resaltados del libro, con salto a la posición y edición del
/// comentario asociado.
Future<void> showBookHighlightsSheet(
  BuildContext context, {
  required ReaderPalette palette,
  required String bookId,
  required String bookTitle,
  required ValueChanged<int> onJumpToParagraph,
}) {
  return showReaderSheet(
    context,
    expand: true,
    builder: (_) => _BookHighlightsSheet(
      palette: palette,
      bookId: bookId,
      bookTitle: bookTitle,
      onJumpToParagraph: onJumpToParagraph,
    ),
  );
}

class _BookHighlightsSheet extends ConsumerWidget {
  final ReaderPalette palette;
  final String bookId;
  final String bookTitle;
  final ValueChanged<int> onJumpToParagraph;

  const _BookHighlightsSheet({
    required this.palette,
    required this.bookId,
    required this.bookTitle,
    required this.onJumpToParagraph,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(bookHighlightsProvider);
    final highlights = ref.read(bookHighlightsProvider.notifier).forBook(bookId);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReaderSheetTitle(
          text: 'Resaltados',
          palette: palette,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${highlights.length}',
                style: GoogleFonts.montserrat(
                  color: palette.foregroundAlpha(0.5),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (highlights.isNotEmpty)
                _iconButton(
                  icon: Icons.ios_share,
                  palette: palette,
                  tooltip: 'Exportar a Markdown',
                  onPressed: () => _export(context, highlights),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (highlights.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Text(
              'Selecciona texto mientras lees para resaltarlo.',
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(color: palette.foregroundAlpha(0.55)),
            ),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: highlights.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _tile(context, ref, highlights[index]),
            ),
          ),
      ],
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, BookHighlight highlight) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: highlight.paragraphIndex == null
          ? null
          : () {
              Navigator.of(context).pop();
              onJumpToParagraph(highlight.paragraphIndex!);
            },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(14),
          border: Border(
            left: BorderSide(color: highlight.color.color, width: 4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (highlight.chapterTitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  highlight.chapterTitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.montserrat(
                    color: palette.foregroundAlpha(0.45),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Text(
              highlight.text,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.montserrat(
                color: palette.foregroundAlpha(0.85),
                fontSize: 13,
                height: 1.45,
              ),
            ),
            if (highlight.note != null && highlight.note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.edit_note,
                        size: 15, color: palette.foregroundAlpha(0.5)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        highlight.note!,
                        style: GoogleFonts.montserrat(
                          color: palette.foregroundAlpha(0.6),
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (highlight.noteId != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.hub_outlined,
                        size: 15, color: palette.foregroundAlpha(0.45)),
                  ),
                const Spacer(),
                _iconButton(
                  icon: Icons.palette_outlined,
                  palette: palette,
                  tooltip: 'Cambiar color',
                  onPressed: () => _cycleColor(ref, highlight),
                ),
                _iconButton(
                  icon: Icons.copy_all_outlined,
                  palette: palette,
                  tooltip: 'Copiar',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: highlight.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Fragmento copiado')),
                    );
                  },
                ),
                _iconButton(
                  icon: Icons.delete_outline,
                  palette: palette,
                  tooltip: 'Eliminar',
                  onPressed: () => ref
                      .read(bookHighlightsProvider.notifier)
                      .deleteHighlight(highlight.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Vuelca los resaltados a un `.md` y lo abre con la app que el sistema
  /// tenga asociada, desde donde ya se puede compartir o guardar donde sea.
  Future<void> _export(BuildContext context, List<BookHighlight> highlights) async {
    final messenger = ScaffoldMessenger.of(context);
    final markdown = _buildMarkdown(highlights);

    // Aunque falle abrir el archivo, el contenido queda a mano.
    await Clipboard.setData(ClipboardData(text: markdown));

    try {
      final dir = await getApplicationDocumentsDirectory();
      final safeName = bookTitle
          .replaceAll(RegExp(r'[^\w\s\-]'), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '_');
      final file = File(
          '${dir.path}/resaltados_${safeName.isEmpty ? bookId : safeName}.md');
      await file.writeAsString(markdown);

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Resaltados copiados al portapapeles'),
        ));
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Resaltados copiados al portapapeles'),
      ));
    }
  }

  String _buildMarkdown(List<BookHighlight> highlights) {
    final now = DateTime.now();
    final date = '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/${now.year}';

    final buffer = StringBuffer()
      ..writeln('# Resaltados de "$bookTitle"')
      ..writeln()
      ..writeln('_${highlights.length} resaltados · exportado el ${date}_')
      ..writeln();

    String? currentChapter;
    for (final highlight in highlights) {
      final chapter = highlight.chapterTitle;
      if (chapter != null && chapter != currentChapter) {
        currentChapter = chapter;
        buffer
          ..writeln('## $chapter')
          ..writeln();
      }

      // Cada línea del fragmento va citada: si no, un resaltado de varios
      // párrafos rompe la cita en Markdown.
      for (final line in highlight.text.trim().split('\n')) {
        buffer.writeln('> ${line.trim()}');
      }
      buffer.writeln();

      if (highlight.note != null && highlight.note!.isNotEmpty) {
        buffer
          ..writeln('**Nota:** ${highlight.note}')
          ..writeln();
      }
    }

    return buffer.toString();
  }

  void _cycleColor(WidgetRef ref, BookHighlight highlight) {
    final next = HighlightColor.values[
        (highlight.color.index + 1) % HighlightColor.values.length];
    ref.read(bookHighlightsProvider.notifier).updateHighlight(
          highlight.id,
          color: next,
        );
  }

  Widget _iconButton({
    required IconData icon,
    required ReaderPalette palette,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 17, color: palette.foregroundAlpha(0.55)),
      onPressed: onPressed,
    );
  }
}
