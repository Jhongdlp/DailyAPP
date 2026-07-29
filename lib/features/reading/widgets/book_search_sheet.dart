import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/reader_theme_provider.dart';
import 'reader_sheet.dart';

/// Coincidencia de la búsqueda dentro del libro.
class BookSearchHit {
  final int paragraphIndex;
  final String snippet;
  final int matchStart;
  final int matchLength;
  final String? chapterTitle;

  const BookSearchHit({
    required this.paragraphIndex,
    required this.snippet,
    required this.matchStart,
    required this.matchLength,
    this.chapterTitle,
  });
}

typedef BookSearchRunner = List<BookSearchHit> Function(String query);

/// Búsqueda de texto dentro del libro abierto.
Future<void> showBookSearchSheet(
  BuildContext context, {
  required ReaderPalette palette,
  required BookSearchRunner search,
  required ValueChanged<int> onJumpToParagraph,
}) {
  return showReaderSheet(
    context,
    expand: true,
    builder: (_) => _BookSearchSheet(
      palette: palette,
      search: search,
      onJumpToParagraph: onJumpToParagraph,
    ),
  );
}

class _BookSearchSheet extends StatefulWidget {
  final ReaderPalette palette;
  final BookSearchRunner search;
  final ValueChanged<int> onJumpToParagraph;

  const _BookSearchSheet({
    required this.palette,
    required this.search,
    required this.onJumpToParagraph,
  });

  @override
  State<_BookSearchSheet> createState() => _BookSearchSheetState();
}

class _BookSearchSheetState extends State<_BookSearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<BookSearchHit> _hits = const [];
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Recorrer el libro entero en cada tecla es caro, así que se espera a que
  /// el usuario deje de escribir.
  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() {
        _hits = const [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _hits = widget.search(value.trim());
        _searched = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: GoogleFonts.montserrat(color: palette.foreground),
          cursorColor: palette.foreground,
          decoration: InputDecoration(
            hintText: 'Buscar en el libro…',
            hintStyle: GoogleFonts.montserrat(color: palette.foregroundAlpha(0.4)),
            prefixIcon: Icon(Icons.search, color: palette.foregroundAlpha(0.5)),
            filled: true,
            fillColor: palette.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          onChanged: _onChanged,
        ),
        const SizedBox(height: 12),
        if (_searched)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _hits.isEmpty
                  ? 'Sin coincidencias'
                  : '${_hits.length} coincidencia${_hits.length == 1 ? '' : 's'}',
              style: GoogleFonts.montserrat(
                color: palette.foregroundAlpha(0.5),
                fontSize: 12,
              ),
            ),
          ),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _hits.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              color: palette.foregroundAlpha(0.08),
            ),
            itemBuilder: (context, index) => _hitTile(_hits[index]),
          ),
        ),
      ],
    );
  }

  Widget _hitTile(BookSearchHit hit) {
    final palette = widget.palette;
    final before = hit.snippet.substring(0, hit.matchStart);
    final match = hit.snippet.substring(hit.matchStart, hit.matchStart + hit.matchLength);
    final after = hit.snippet.substring(hit.matchStart + hit.matchLength);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      title: RichText(
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: GoogleFonts.montserrat(
            color: palette.foregroundAlpha(0.75),
            fontSize: 13,
            height: 1.4,
          ),
          children: [
            TextSpan(text: before),
            TextSpan(
              text: match,
              style: TextStyle(
                color: palette.foreground,
                fontWeight: FontWeight.w800,
                backgroundColor: palette.highlight,
              ),
            ),
            TextSpan(text: after),
          ],
        ),
      ),
      subtitle: hit.chapterTitle == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                hit.chapterTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.montserrat(
                  color: palette.foregroundAlpha(0.45),
                  fontSize: 11,
                ),
              ),
            ),
      onTap: () {
        Navigator.of(context).pop();
        widget.onJumpToParagraph(hit.paragraphIndex);
      },
    );
  }
}
