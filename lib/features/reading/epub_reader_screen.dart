import 'dart:async';
import 'package:epub_view/epub_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/models/book_model.dart';
import '../../core/providers/books_provider.dart';
import 'widgets/book_bookmarks_sheet.dart';

class EpubReaderScreen extends ConsumerStatefulWidget {
  final Book book;
  const EpubReaderScreen({super.key, required this.book});

  @override
  ConsumerState<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends ConsumerState<EpubReaderScreen> {
  EpubController? _controller;
  String? _currentPosition;
  Timer? _saveDebounce;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initController() async {
    final file = await resolveBookFile(widget.book.localFilename);
    if (!mounted) return;
    setState(() {
      _controller = EpubController(
        document: EpubDocument.openFile(file),
        epubCfi: widget.book.lastPosition,
      );
      _currentPosition = widget.book.lastPosition;
      _controller!.currentValueListenable.addListener(_onPositionChanged);
    });
  }

  void _onPositionChanged() {
    final cfi = _controller?.generateEpubCfi();
    if (cfi == null || cfi == _currentPosition) return;
    _currentPosition = cfi;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () {
      ref.read(booksProvider.notifier).updateProgress(widget.book.id, cfi);
    });
  }

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
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
            onPressed: controller == null
                ? null
                : () => showBookBookmarksSheet(
                      context,
                      bookId: widget.book.id,
                      currentPosition: _currentPosition ?? '',
                      onJumpTo: (position) => controller.gotoEpubCfi(position),
                    ),
          ),
        ],
      ),
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : EpubView(controller: controller),
    );
  }
}
