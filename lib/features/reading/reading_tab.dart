import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/models/book_model.dart';
import '../../core/providers/book_metrics_provider.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/library_view_provider.dart';
import '../../core/providers/reader_prefs_provider.dart';
import '../habits/widgets/habit_blob_header.dart';
import 'pdf_reader_screen.dart';
import 'epub_reader_screen.dart';
import 'widgets/book_cover.dart';
import 'widgets/reading_stats_strip.dart';

class ReadingTab extends ConsumerStatefulWidget {
  const ReadingTab({super.key});

  @override
  ConsumerState<ReadingTab> createState() => _ReadingTabState();
}

class _ReadingTabState extends ConsumerState<ReadingTab> {
  bool _importing = false;
  bool _showSearch = false;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  // ─── Acciones sobre libros ────────────────────────────────────────────────

  Future<void> _importBooks() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'epub'],
        allowMultiple: true,
      );
      final picked = result?.files ?? const [];
      if (picked.isEmpty) return;

      final paths = [
        for (final file in picked)
          if (file.path != null) file.path!,
      ];
      final added = await ref.read(booksProvider.notifier).addBooksFromPaths(paths);

      if (mounted && added.length < paths.length) {
        _toast('Se importaron ${added.length} de ${paths.length} archivos');
      }
    } catch (e) {
      _toast('No se pudo importar: $e');
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

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmDelete(Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: BentoTheme.neuSurface,
        title: Text('Eliminar libro',
            style: GoogleFonts.montserrat(color: BentoTheme.cream)),
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

  Future<void> _editBook(Book book) async {
    final titleController = TextEditingController(text: book.title);
    final authorController = TextEditingController(text: book.author ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: BentoTheme.neuSurface,
        title: Text('Editar libro',
            style: GoogleFonts.montserrat(color: BentoTheme.cream)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogField(titleController, 'Título', autofocus: true),
            const SizedBox(height: 12),
            _dialogField(authorController, 'Autor'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Guardar',
                style: TextStyle(color: BentoTheme.accentPurple)),
          ),
        ],
      ),
    );

    final title = titleController.text;
    final author = authorController.text;
    titleController.dispose();
    authorController.dispose();

    if (saved != true) return;
    await ref.read(booksProvider.notifier).updateBookDetails(
          book.id,
          title: title,
          author: author,
        );
  }

  Widget _dialogField(
    TextEditingController controller,
    String label, {
    bool autofocus = false,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      style: GoogleFonts.montserrat(color: BentoTheme.cream),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.5)),
      ),
    );
  }

  Future<void> _changeCover(Book book) async {
    try {
      final picked =
          await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;
      await ref.read(booksProvider.notifier).setCoverImage(book.id, File(picked.path));
    } catch (e) {
      _toast('No se pudo cambiar la portada: $e');
    }
  }

  Future<void> _refreshMetadata(Book book) async {
    final ok = await ref.read(booksProvider.notifier).refreshEpubMetadata(book.id);
    _toast(ok
        ? 'Metadata actualizada desde el EPUB'
        : 'El EPUB no trae metadata utilizable');
  }

  void _showBookActions(Book book) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: BentoTheme.neuSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          top: 10,
          bottom: MediaQuery.viewPaddingOf(sheetContext).bottom + 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: BentoTheme.creamAlpha(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _sheetAction(sheetContext, Icons.edit_outlined, 'Editar título y autor',
                () => _editBook(book)),
            _sheetAction(sheetContext, Icons.image_outlined, 'Cambiar portada',
                () => _changeCover(book)),
            if (book.format == BookFormat.epub)
              _sheetAction(sheetContext, Icons.refresh, 'Releer metadata del EPUB',
                  () => _refreshMetadata(book)),
            _sheetAction(sheetContext, Icons.delete_outline, 'Eliminar',
                () => _confirmDelete(book),
                danger: true),
          ],
        ),
      ),
    );
  }

  Widget _sheetAction(
    BuildContext sheetContext,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    final color = danger ? BentoTheme.errorRed : BentoTheme.cream;
    return ListTile(
      leading: Icon(icon, color: color, size: 20),
      title: Text(label,
          style: GoogleFonts.montserrat(color: color, fontSize: 14)),
      onTap: () {
        Navigator.of(sheetContext).pop();
        onTap();
      },
    );
  }

  // ─── Cabecera ─────────────────────────────────────────────────────────────

  Widget _headerIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool busy = false,
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
          child: busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: BentoTheme.cream),
                )
              : Icon(icon, size: 17, color: BentoTheme.cream),
        ),
      ),
    );
  }

  Widget _buildHeader(LibraryView view) {
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
                  child: Row(
                    children: [
                      _headerIconButton(
                        icon: _showSearch ? Icons.close : Icons.search,
                        tooltip: 'Buscar libro',
                        onPressed: _toggleSearch,
                      ),
                      const SizedBox(width: 8),
                      _headerIconButton(
                        icon: view.layout == LibraryLayout.grid
                            ? LibraryLayout.list.icon
                            : LibraryLayout.grid.icon,
                        tooltip: view.layout == LibraryLayout.grid
                            ? 'Ver en lista'
                            : 'Ver en cuadrícula',
                        onPressed: () =>
                            ref.read(libraryViewProvider.notifier).toggleLayout(),
                      ),
                      const SizedBox(width: 8),
                      _headerIconButton(
                        icon: Icons.add_outlined,
                        tooltip: 'Importar libros',
                        busy: _importing,
                        onPressed: _importing ? null : _importBooks,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        style: GoogleFonts.montserrat(color: BentoTheme.cream),
        onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Buscar por título o autor…',
          hintStyle: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.4)),
          prefixIcon: Icon(Icons.search, color: BentoTheme.creamAlpha(0.5)),
          filled: true,
          fillColor: BentoTheme.creamAlpha(0.06),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // ─── Filtros y orden ──────────────────────────────────────────────────────

  Widget _buildFilterBar(LibraryView view, List<Book> books) {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (final filter in LibraryFilter.values) ...[
            _filterChip(
              label: filter.label,
              count: _countFor(filter, books),
              selected: view.filter == filter,
              onTap: () => ref.read(libraryViewProvider.notifier).setFilter(filter),
            ),
            const SizedBox(width: 8),
          ],
          _sortChip(view),
        ],
      ),
    );
  }

  int _countFor(LibraryFilter filter, List<Book> books) {
    return switch (filter) {
      LibraryFilter.all => books.length,
      LibraryFilter.reading => books.where((b) => b.isStarted).length,
      LibraryFilter.unread => books.where((b) => b.isUnread).length,
      LibraryFilter.finished => books.where((b) => b.isFinished).length,
    };
  }

  Widget _filterChip({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? BentoTheme.accentPurple.withValues(alpha: 0.18)
              : BentoTheme.creamAlpha(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? BentoTheme.accentPurple.withValues(alpha: 0.5)
                : BentoTheme.creamAlpha(0.1),
          ),
        ),
        child: Text(
          count > 0 ? '$label · $count' : label,
          style: GoogleFonts.montserrat(
            color: selected ? BentoTheme.cream : BentoTheme.creamAlpha(0.6),
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _sortChip(LibraryView view) {
    return PopupMenuButton<LibrarySort>(
      color: BentoTheme.neuSurface,
      onSelected: (sort) => ref.read(libraryViewProvider.notifier).setSort(sort),
      itemBuilder: (context) => [
        for (final sort in LibrarySort.values)
          PopupMenuItem(
            value: sort,
            child: Row(
              children: [
                Icon(
                  view.sort == sort ? Icons.check : Icons.sort,
                  size: 16,
                  color: BentoTheme.creamAlpha(0.7),
                ),
                const SizedBox(width: 10),
                Text(sort.label,
                    style: GoogleFonts.montserrat(
                        color: BentoTheme.cream, fontSize: 13)),
              ],
            ),
          ),
      ],
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: BentoTheme.creamAlpha(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: BentoTheme.creamAlpha(0.1)),
        ),
        child: Row(
          children: [
            Icon(Icons.swap_vert, size: 15, color: BentoTheme.creamAlpha(0.6)),
            const SizedBox(width: 5),
            Text(
              view.sort.label,
              style: GoogleFonts.montserrat(
                color: BentoTheme.creamAlpha(0.7),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Continuar leyendo ────────────────────────────────────────────────────

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}min';
  }

  /// Tarjeta destacada del último libro en curso. Solo aparece cuando de verdad
  /// hay algo a medias: si no, ocupa espacio para no decir nada.
  Widget? _buildContinueCard(List<Book> books) {
    final candidates = books.where((b) => b.isStarted).toList()
      ..sort((a, b) => LibraryView.dateDesc(a.lastOpenedAt, b.lastOpenedAt));
    if (candidates.isEmpty) return null;

    final book = candidates.first;
    final progress = (book.progressPercent ?? 0).clamp(0.0, 1.0);

    // Se observa el mapa (no solo el notifier) para que la tarjeta se refresque
    // en cuanto el lector mide por primera vez las palabras del libro.
    ref.watch(bookMetricsProvider);
    final minutesLeft = ref.read(bookMetricsProvider.notifier).minutesLeft(
          book.id,
          progress,
          ref.watch(readerPrefsProvider.select((p) => p.wordsPerMinute)),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: NeuCard(
        borderRadius: 22,
        onTap: () => _openBook(book),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            BookCover(book: book, width: 58, height: 84, borderRadius: 12),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'CONTINUAR LEYENDO',
                    style: GoogleFonts.montserrat(
                      color: BentoTheme.accentPurple,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.montserrat(
                      color: BentoTheme.cream,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor: BentoTheme.neuSurfaceSunken,
                      valueColor: AlwaysStoppedAnimation(BentoTheme.accentPurple),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      '${(progress * 100).round()}%',
                      if (minutesLeft != null && minutesLeft > 0)
                        '${_formatMinutes(minutesLeft)} restantes',
                    ].join(' · '),
                    style: GoogleFonts.montserrat(
                      color: BentoTheme.creamAlpha(0.55),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Tarjetas de libro ────────────────────────────────────────────────────

  Widget _bookListCard(Book book) {
    final progress = book.progressPercent;
    return NeuCard(
      borderRadius: 20,
      onTap: () => _openBook(book),
      onLongPress: () => _showBookActions(book),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          BookCover(book: book, width: 46, height: 62),
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
                    style: GoogleFonts.montserrat(
                        color: BentoTheme.creamAlpha(0.55), fontSize: 12),
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
            icon: Icon(Icons.more_vert, color: BentoTheme.creamAlpha(0.4)),
            onPressed: () => _showBookActions(book),
          ),
        ],
      ),
    );
  }

  Widget _bookGridCard(Book book) {
    final progress = book.progressPercent;
    return GestureDetector(
      onTap: () => _openBook(book),
      onLongPress: () => _showBookActions(book),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  BookCover(
                    book: book,
                    width: width,
                    height: width * 1.45,
                    borderRadius: 14,
                  ),
                  if (book.isFinished)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: BentoTheme.successGreen,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check,
                            size: 11, color: Colors.white),
                      ),
                    ),
                ],
              ),
              if (progress != null && progress > 0) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0, 1),
                    minHeight: 3,
                    backgroundColor: BentoTheme.neuSurfaceSunken,
                    valueColor: AlwaysStoppedAnimation(BentoTheme.accentPurple),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Flexible(
                child: Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.montserrat(
                    color: BentoTheme.cream,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Estados vacíos ───────────────────────────────────────────────────────

  Widget _emptyLibrary() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_outlined,
                size: 56, color: BentoTheme.creamAlpha(0.3)),
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
    );
  }

  Widget _emptyResults(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.5)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(booksProvider);
    final view = ref.watch(libraryViewProvider);

    final visible = _query.isEmpty
        ? view.apply(books)
        : view.apply(books).where((b) =>
            b.title.toLowerCase().contains(_query) ||
            (b.author?.toLowerCase().contains(_query) ?? false)).toList();

    final continueCard =
        _showSearch || view.filter != LibraryFilter.all ? null : _buildContinueCard(books);

    return BentoBackground(
      backgroundColor: BentoTheme.darkBg,
      child: Column(
        children: [
          _buildHeader(view),
          if (_showSearch) _buildSearchField(),
          if (!_showSearch) const ReadingStatsStrip(),
          ?continueCard,
          if (books.isNotEmpty) ...[
            const SizedBox(height: 4),
            _buildFilterBar(view, books),
          ],
          Expanded(
            child: books.isEmpty
                ? _emptyLibrary()
                : visible.isEmpty
                    ? _emptyResults(_query.isNotEmpty
                        ? 'Sin resultados para "$_query"'
                        : 'Nada en "${view.filter.label}"')
                    : view.layout == LibraryLayout.grid
                        ? _buildGrid(visible)
                        : _buildList(visible),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<Book> books) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      itemCount: books.length,
      separatorBuilder: (context, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _bookListCard(books[index]),
    );
  }

  Widget _buildGrid(List<Book> books) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 14,
        mainAxisSpacing: 18,
        // La tarjeta es portada (1:1.45) más dos líneas de título y la barra
        // de progreso; el margen extra evita que un título largo desborde.
        childAspectRatio: 0.50,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) => _bookGridCard(books[index]),
    );
  }
}
