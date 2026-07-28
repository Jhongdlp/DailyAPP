import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/models/book_model.dart';
import '../../core/providers/books_provider.dart';
import 'widgets/book_bookmarks_sheet.dart';

class PdfReaderScreen extends ConsumerStatefulWidget {
  final Book book;
  const PdfReaderScreen({super.key, required this.book});

  @override
  ConsumerState<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends ConsumerState<PdfReaderScreen> {
  final _controller = PdfViewerController();
  int _currentPage = 1;
  int _totalPages = 0;
  Timer? _saveDebounce;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _controller.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BentoTheme.darkBg,
      appBar: AppBar(
        backgroundColor: BentoTheme.darkBg,
        foregroundColor: BentoTheme.cream,
        elevation: 0,
        title: Text(
          widget.book.title,
          style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
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
      ),
      body: FutureBuilder(
        future: resolveBookFile(widget.book.localFilename),
        builder: (context, snapshot) {
          final file = snapshot.data;
          if (file == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return SfPdfViewer.file(
            file,
            controller: _controller,
            onDocumentLoaded: (details) {
              _totalPages = details.document.pages.count;
              final startPage = int.tryParse(widget.book.lastPosition ?? '');
              if (startPage != null && startPage > 1 && startPage <= _totalPages) {
                _controller.jumpToPage(startPage);
              }
            },
            onPageChanged: (details) {
              _currentPage = details.newPageNumber;
              _scheduleSaveProgress();
            },
          );
        },
      ),
    );
  }
}
