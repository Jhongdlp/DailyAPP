import '../epub_internals.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/reader_theme_provider.dart';
import 'reader_sheet.dart';

/// Índice del libro. Se pinta a mano en vez de usar `EpubViewTableOfContents`
/// para poder marcar el capítulo actual y respetar los colores del modo de
/// lectura.
Future<void> showBookTocSheet(
  BuildContext context, {
  required ReaderPalette palette,
  required List<EpubViewChapter> chapters,
  required int currentParagraphIndex,
  required ValueChanged<int> onJumpToParagraph,
}) {
  return showReaderSheet(
    context,
    expand: true,
    builder: (sheetContext) {
      if (chapters.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Text(
            'Este libro no trae índice.',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(color: palette.foregroundAlpha(0.6)),
          ),
        );
      }

      // El capítulo actual es el último cuyo inicio queda por detrás de la
      // posición de lectura.
      var currentIndex = 0;
      for (var i = 0; i < chapters.length; i++) {
        if (chapters[i].startIndex <= currentParagraphIndex) currentIndex = i;
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReaderSheetTitle(text: 'Índice', palette: palette),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              itemCount: chapters.length,
              // Arranca mostrando dónde vas, no el principio del libro.
              controller: ScrollController(
                initialScrollOffset: (currentIndex * 48).toDouble(),
              ),
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                final isSub = chapter is EpubViewSubChapter;
                final isCurrent = index == currentIndex;

                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.only(left: isSub ? 22 : 0, right: 4),
                  leading: isCurrent
                      ? Icon(Icons.play_arrow_rounded,
                          size: 18, color: palette.foreground)
                      : null,
                  horizontalTitleGap: 6,
                  minLeadingWidth: isCurrent ? 18 : 0,
                  title: Text(
                    (chapter.title ?? 'Sin título').trim(),
                    style: GoogleFonts.montserrat(
                      color: isCurrent
                          ? palette.foreground
                          : palette.foregroundAlpha(isSub ? 0.6 : 0.8),
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      fontSize: isSub ? 12.5 : 14,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onJumpToParagraph(chapter.startIndex);
                  },
                );
              },
            ),
          ),
        ],
      );
    },
  );
}
