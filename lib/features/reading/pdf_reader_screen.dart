import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../core/models/book_model.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/reader_theme_provider.dart';
import 'widgets/book_bookmarks_sheet.dart';

class PdfReaderScreen extends ConsumerStatefulWidget {
  final Book book;
  const PdfReaderScreen({super.key, required this.book});

  @override
  ConsumerState<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends ConsumerState<PdfReaderScreen> {
  final _controller = PdfViewerController();
  final _focusNode = FocusNode();
  int _currentPage = 1;
  int _totalPages = 0;
  Timer? _saveDebounce;
  bool _chromeVisible = true;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    SystemChrome.setEnabledSystemUIMode(
      _chromeVisible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.pageDown:
      case LogicalKeyboardKey.space:
        _controller.nextPage();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.pageUp:
        _controller.previousPage();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _controller.jumpToPage(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        if (_totalPages > 0) _controller.jumpToPage(_totalPages);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _scheduleSaveProgress() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final percent = _totalPages > 0 ? _currentPage / _totalPages : null;
      ref.read(booksProvider.notifier).updateProgress(
            widget.book.id,
            '$_currentPage',
            totalPages: _totalPages > 0 ? _totalPages : null,
            progressPercent: percent,
          );
    });
  }

  void _jumpToPosition(String position) {
    final page = int.tryParse(position);
    if (page != null) _controller.jumpToPage(page);
  }

  Widget _buildProgressBar(ReaderPalette palette) {
    final percent = _totalPages > 0 ? _currentPage / _totalPages : 0.0;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
        child: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: percent.clamp(0, 1),
                  minHeight: 4,
                  backgroundColor: palette.foregroundAlpha(0.12),
                  valueColor: AlwaysStoppedAnimation(palette.foregroundAlpha(0.7)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _totalPages > 0 ? '$_currentPage/$_totalPages' : '$_currentPage',
              style: GoogleFonts.montserrat(
                color: palette.foregroundAlpha(0.6),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readerMode = ref.watch(readerThemeProvider);
    final palette = readerPaletteFor(readerMode);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: _chromeVisible
          ? AppBar(
              backgroundColor: palette.background,
              foregroundColor: palette.foreground,
              elevation: 0,
              title: Text(
                widget.book.title,
                style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                IconButton(
                  tooltip: 'Modo de lectura: ${readerThemeLabel(readerMode)}',
                  icon: Icon(readerThemeIcon(readerMode)),
                  onPressed: () => ref.read(readerThemeProvider.notifier).cycle(),
                ),
                IconButton(
                  icon: const Icon(Icons.bookmark_outline),
                  onPressed: () => showBookBookmarksSheet(
                    context,
                    bookId: widget.book.id,
                    currentPosition: '$_currentPage',
                    onJumpTo: _jumpToPosition,
                  ),
                ),
              ],
            )
          : null,
      bottomNavigationBar: _chromeVisible ? _buildProgressBar(palette) : null,
      body: FutureBuilder(
        future: resolveBookFile(widget.book.localFilename),
        builder: (context, snapshot) {
          final file = snapshot.data;
          if (file == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final viewer = SfPdfViewer.file(
            file,
            controller: _controller,
            pageLayoutMode: PdfPageLayoutMode.single,
            scrollDirection: PdfScrollDirection.horizontal,
            onDocumentLoaded: (details) {
              setState(() => _totalPages = details.document.pages.count);
              final startPage = int.tryParse(widget.book.lastPosition ?? '');
              if (startPage != null && startPage > 1 && startPage <= _totalPages) {
                _controller.jumpToPage(startPage);
              }
            },
            onPageChanged: (details) {
              setState(() => _currentPage = details.newPageNumber);
              _scheduleSaveProgress();
            },
          );
          return Focus(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: _handleKey,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleChrome,
              child: Container(
                color: palette.background,
                child: palette.pdfFilter != null
                    ? ColorFiltered(colorFilter: palette.pdfFilter!, child: viewer)
                    : viewer,
              ),
            ),
          );
        },
      ),
    );
  }
}
