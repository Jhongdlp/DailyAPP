import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/models/book_model.dart';
import '../../core/providers/books_provider.dart';
import '../habits/widgets/habit_blob_header.dart';
import 'pdf_reader_screen.dart';
import 'epub_reader_screen.dart';

class ReadingTab extends ConsumerStatefulWidget {
  const ReadingTab({super.key});

  @override
  ConsumerState<ReadingTab> createState() => _ReadingTabState();
}

class _ReadingTabState extends ConsumerState<ReadingTab> {
  bool _importing = false;

  Future<void> _importBook() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'epub'],
      );
      final picked = result?.files.single;
      if (picked == null) return;
      await ref.read(booksProvider.notifier).addBookFromPicker(picked);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo importar el libro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _openBook(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => book.format == BookFormat.pdf
            ? PdfReaderScreen(book: book)
            : EpubReaderScreen(book: book),
      ),
    );
  }

  Future<void> _confirmDelete(Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: BentoTheme.neuSurface,
        title: Text('Eliminar libro', style: GoogleFonts.montserrat(color: BentoTheme.cream)),
        content: Text(
          '¿Eliminar "${book.title}" de tu biblioteca? Esto borra el archivo de este dispositivo.',
          style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Eliminar', style: TextStyle(color: BentoTheme.errorRed)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(booksProvider.notifier).deleteBook(book.id);
    }
  }

  Widget _buildHeaderIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: BentoTheme.creamAlpha(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: BentoTheme.creamAlpha(0.14)),
          ),
          child: _importing
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: BentoTheme.cream),
                )
              : Icon(icon, size: 17, color: BentoTheme.cream),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 92,
      child: Stack(
        children: [
          Positioned.fill(child: HabitBlobHeader(accentColor: BentoTheme.accentPurple)),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Biblioteca',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w800,
                    fontSize: 38,
                    height: 0.92,
                    letterSpacing: -1.2,
                    color: BentoTheme.cream,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _buildHeaderIconButton(
                    icon: Icons.add_outlined,
                    tooltip: 'Importar libro',
                    onPressed: _importing ? null : _importBook,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bookCard(Book book) {
    final progress = book.progressPercent;
    return NeuCard(
      borderRadius: 20,
      onTap: () => _openBook(book),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 62,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BentoTheme.accentPurple.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              book.format == BookFormat.pdf ? Icons.picture_as_pdf_outlined : Icons.menu_book_outlined,
              color: BentoTheme.accentPurple,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: GoogleFonts.montserrat(
                    color: BentoTheme.cream,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (book.author != null && book.author!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    book.author!,
                    style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.55), fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (progress != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0, 1),
                      minHeight: 5,
                      backgroundColor: BentoTheme.neuSurfaceSunken,
                      valueColor: AlwaysStoppedAnimation(BentoTheme.accentPurple),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: BentoTheme.creamAlpha(0.4)),
            onPressed: () => _confirmDelete(book),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(booksProvider);

    return BentoBackground(
      backgroundColor: BentoTheme.darkBg,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: books.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_stories_outlined, size: 56, color: BentoTheme.creamAlpha(0.3)),
                          const SizedBox(height: 16),
                          Text(
                            'Tu biblioteca está vacía',
                            style: GoogleFonts.montserrat(
                              color: BentoTheme.cream,
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Importa un PDF o EPUB para empezar a leer.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.5)),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                    itemCount: books.length,
                    separatorBuilder: (context, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _bookCard(books[index]),
                  ),
          ),
        ],
      ),
    );
  }
}
