import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';

import '../../core/models/book_model.dart';
import '../../core/providers/book_metrics_provider.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/library_view_provider.dart';
import '../../core/providers/reader_prefs_provider.dart';
import '../../core/providers/reading_stats_provider.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/widgets/editorial_kit.dart';
import 'pdf_reader_screen.dart';
import 'epub_reader_screen.dart';
import 'widgets/book_cover.dart';

class ReadingTabEditorial extends ConsumerStatefulWidget {
  const ReadingTabEditorial({super.key});

  @override
  ConsumerState<ReadingTabEditorial> createState() => _ReadingTabEditorialState();
}

class _ReadingTabEditorialState extends ConsumerState<ReadingTabEditorial> {
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
        showEditorialSnack(context, 'Se importaron ${added.length} de ${paths.length} archivos');
      }
    } catch (e) {
      if (mounted) {
        showEditorialSnack(context, 'No se pudo importar: $e');
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
    final confirmed = await confirmEditorial(
      context,
      title: 'Eliminar libro',
      body: '¿Eliminar "${book.title}" de tu biblioteca? Esto borra el archivo de este dispositivo.',
      confirmLabel: 'Eliminar',
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
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => Dialog(
        backgroundColor: EditorialTheme.paper,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Editar libro',
                style: EditorialTheme.caps(21, color: EditorialTheme.ink, letterSpacing: -0.5),
              ),
              const SizedBox(height: 16),
              const EditorialSectionLabel('Título'),
              const SizedBox(height: 8),
              EditorialField(
                controller: titleController,
                hint: 'Título',
                autofocus: true,
              ),
              const SizedBox(height: 16),
              const EditorialSectionLabel('Autor'),
              const SizedBox(height: 8),
              EditorialField(
                controller: authorController,
                hint: 'Autor',
              ),
              const SizedBox(height: 24),
              EditorialButton(
                label: 'Guardar',
                onTap: () => Navigator.of(ctx).pop(true),
              ),
              const SizedBox(height: 8),
              EditorialButton(
                label: 'Cancelar',
                ghost: true,
                onTap: () => Navigator.of(ctx).pop(false),
              ),
            ],
          ),
        ),
      ),
    );

    final title = titleController.text.trim();
    final author = authorController.text.trim();
    titleController.dispose();
    authorController.dispose();

    if (saved != true) return;
    await ref.read(booksProvider.notifier).updateBookDetails(
          book.id,
          title: title,
          author: author,
        );
  }

  Future<void> _changeCover(Book book) async {
    try {
      final picked =
          await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;
      await ref.read(booksProvider.notifier).setCoverImage(book.id, File(picked.path));
    } catch (e) {
      if (mounted) {
        showEditorialSnack(context, 'No se pudo cambiar la portada: $e');
      }
    }
  }

  Future<void> _refreshMetadata(Book book) async {
    final ok = await ref.read(booksProvider.notifier).refreshEpubMetadata(book.id);
    if (mounted) {
      showEditorialSnack(context, ok
          ? 'Metadata actualizada desde el EPUB'
          : 'El EPUB no trae metadata utilizable');
    }
  }

  void _showBookActions(Book book) {
    showEditorialSheet<void>(
      context: context,
      title: book.title,
      builder: (sheetContext, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: EditorialRow(
              icon: Icons.edit_outlined,
              label: 'Editar título y autor',
              onTap: () {
                Navigator.pop(sheetContext);
                _editBook(book);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: EditorialRow(
              icon: Icons.image_outlined,
              label: 'Cambiar portada',
              onTap: () {
                Navigator.pop(sheetContext);
                _changeCover(book);
              },
            ),
          ),
          if (book.format == BookFormat.epub)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: EditorialRow(
                icon: Icons.refresh,
                label: 'Releer metadata del EPUB',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _refreshMetadata(book);
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: EditorialRow(
              icon: Icons.delete_outline,
              label: 'Eliminar',
              active: true,
              accent: const Color(0xFFB3261E),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDelete(book);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(LibraryView view, int totalBooks) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EditorialTheme.margin,
        10,
        EditorialTheme.margin,
        18,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'BIBLIOTECA',
                  style: EditorialTheme.caps(
                    34,
                    color: EditorialTheme.paper,
                    letterSpacing: -1.0,
                    height: 0.94,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  totalBooks == 1 ? '1 LIBRO GUARDADO' : '$totalBooks LIBROS GUARDADOS',
                  style: EditorialTheme.label(10.5, color: EditorialTheme.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          EditorialCircleButton(
            icon: _showSearch ? Icons.close : Icons.search,
            tooltip: 'Buscar libro',
            onTap: _toggleSearch,
          ),
          const SizedBox(width: 8),
          EditorialCircleButton(
            icon: view.layout == LibraryLayout.grid
                ? LibraryLayout.list.icon
                : LibraryLayout.grid.icon,
            tooltip: view.layout == LibraryLayout.grid
                ? 'Ver en lista'
                : 'Ver en cuadrícula',
            onTap: () => ref.read(libraryViewProvider.notifier).toggleLayout(),
          ),
          const SizedBox(width: 8),
          EditorialCircleButton(
            icon: Icons.add_outlined,
            tooltip: 'Importar libros',
            busy: _importing,
            onTap: _importing ? null : _importBooks,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: EditorialField(
        controller: _searchController,
        hint: 'Buscar por título o autor…',
        autofocus: true,
        onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
        prefix: Icon(Icons.search, color: EditorialTheme.grayText, size: 20),
      ),
    );
  }

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
    return EditorialChoice(
      label: count > 0 ? '$label · $count' : label,
      selected: selected,
      accent: BentoTheme.accentPurple,
      onTap: onTap,
    );
  }

  Widget _sortChip(LibraryView view) {
    return EditorialChoice(
      label: view.sort.label,
      icon: Icons.swap_vert,
      selected: false,
      onTap: () => _showSortSheet(context, view),
    );
  }

  Future<void> _showSortSheet(BuildContext context, LibraryView view) async {
    await showEditorialSheet<void>(
      context: context,
      title: 'Ordenar por',
      builder: (sheetContext, _) {
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          children: LibrarySort.values
              .map((sort) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: EditorialRow(
                      icon: Icons.sort,
                      label: sort.label,
                      active: view.sort == sort,
                      onTap: () {
                        ref.read(libraryViewProvider.notifier).setSort(sort);
                        Navigator.pop(sheetContext);
                      },
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget? _buildContinueCard(List<Book> books) {
    final candidates = books.where((b) => b.isStarted).toList()
      ..sort((a, b) => LibraryView.dateDesc(a.lastOpenedAt, b.lastOpenedAt));
    if (candidates.isEmpty) return null;

    final book = candidates.first;
    final progress = (book.progressPercent ?? 0).clamp(0.0, 1.0);

    ref.watch(bookMetricsProvider);
    final minutesLeft = ref.read(bookMetricsProvider.notifier).minutesLeft(
          book.id,
          progress,
          ref.watch(readerPrefsProvider.select((p) => p.wordsPerMinute)),
        );

    final formatColor = book.format == BookFormat.pdf
        ? BentoTheme.accentOrange
        : BentoTheme.accentPurple;
    final formatAccent = EditorialTheme.accent(formatColor, onDark: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: EditorialPressable(
        onTap: () => _openBook(book),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: EditorialTheme.paper,
            borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
          ),
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
                      style: EditorialTheme.label(10, color: formatAccent),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: EditorialTheme.text(
                        15,
                        weight: FontWeight.w700,
                        color: EditorialTheme.ink,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: EditorialTheme.gray,
                        valueColor: AlwaysStoppedAnimation(formatAccent),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        '${(progress * 100).round()}%',
                        if (minutesLeft != null && minutesLeft > 0)
                          '${_formatMinutes(minutesLeft)} restantes',
                      ].join(' · '),
                      style: EditorialTheme.text(
                        11.5,
                        weight: FontWeight.w600,
                        color: EditorialTheme.grayText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}min';
  }

  Widget _bookListCard(Book book) {
    final progress = book.progressPercent;
    final formatColor = book.format == BookFormat.pdf
        ? BentoTheme.accentOrange
        : BentoTheme.accentPurple;
    final formatAccent = EditorialTheme.accent(formatColor, onDark: false);

    return EditorialPressable(
      onTap: () => _openBook(book),
      onLongPress: () => _showBookActions(book),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: EditorialTheme.paper,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
        ),
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
                    style: EditorialTheme.text(
                      15,
                      weight: FontWeight.w700,
                      color: EditorialTheme.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (book.author != null && book.author!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      book.author!,
                      style: EditorialTheme.text(
                        12,
                        color: EditorialTheme.grayText,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (progress != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0, 1),
                        minHeight: 5,
                        backgroundColor: EditorialTheme.gray,
                        valueColor: AlwaysStoppedAnimation(formatAccent),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            EditorialPressable(
              onTap: () => _showBookActions(book),
              child: const Icon(Icons.more_vert, color: EditorialTheme.grayText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bookGridCard(Book book) {
    final progress = book.progressPercent;
    final formatColor = book.format == BookFormat.pdf
        ? BentoTheme.accentOrange
        : BentoTheme.accentPurple;
    final formatAccent = EditorialTheme.accent(formatColor, onDark: false);

    return EditorialPressable(
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
                          color: EditorialTheme.accent(BentoTheme.successGreen, onDark: false),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, size: 11, color: EditorialTheme.paper),
                      ),
                    ),
                ],
              ),
              if (progress != null && progress > 0) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0, 1),
                    minHeight: 3,
                    backgroundColor: EditorialTheme.gray,
                    valueColor: AlwaysStoppedAnimation(formatAccent),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Flexible(
                child: Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: EditorialTheme.text(
                    12,
                    weight: FontWeight.w600,
                    color: EditorialTheme.paper,
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

  Widget _emptyLibrary() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_outlined, size: 56, color: EditorialTheme.muted),
            const SizedBox(height: 16),
            Text(
              'Tu biblioteca está vacía',
              style: EditorialTheme.text(
                17,
                weight: FontWeight.w700,
                color: EditorialTheme.paper,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Importa un PDF o EPUB para empezar a leer.',
              textAlign: TextAlign.center,
              style: EditorialTheme.text(14, color: EditorialTheme.muted),
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
          style: EditorialTheme.text(14, color: EditorialTheme.muted),
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

    return ColoredBox(
      color: EditorialTheme.canvas,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              _buildHeader(view, books.length),
              if (_showSearch) _buildSearchField(),
              if (!_showSearch) _ReadingStatsStripEditorial(),
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
        ),
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
        childAspectRatio: 0.50,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) => _bookGridCard(books[index]),
    );
  }
}

class _ReadingStatsStripEditorial extends ConsumerWidget {
  const _ReadingStatsStripEditorial();

  static const _days = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(readingStatsProvider);
    if (stats.totalSeconds == 0) return const SizedBox.shrink();

    final days = stats.lastDays(_days);
    final peak = days.fold<int>(0, (max, d) => d.seconds > max ? d.seconds : max);
    final purpleAccent = EditorialTheme.accent(BentoTheme.accentPurple, onDark: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: EditorialTheme.paper,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _metric(context, '🔥', '${stats.streak}', 'días seguidos'),
                _metric(context, '⏱️', _minutes(stats.todaySeconds), 'hoy'),
                _metric(context, '📚', _hours(stats.totalSeconds), 'en total'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final day in days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Tooltip(
                        message: '${day.day.day}/${day.day.month}: ${_minutes(day.seconds)}',
                        child: Container(
                          height: 22,
                          decoration: BoxDecoration(
                            color: day.seconds == 0
                                ? EditorialTheme.gray
                                : purpleAccent.withValues(
                                    alpha: 0.25 + 0.75 * (peak == 0 ? 0 : day.seconds / peak),
                                  ),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String emoji, String value, String label) {
    return Expanded(
      child: Row(
        children: [
          Twemoji(emoji: emoji, height: 15, width: 15),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: EditorialTheme.text(
                  15,
                  weight: FontWeight.w800,
                  color: EditorialTheme.ink,
                  height: 1.1,
                ),
              ),
              Text(
                label,
                style: EditorialTheme.text(
                  10,
                  color: EditorialTheme.grayText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _minutes(int seconds) => '${seconds ~/ 60} min';

  String _hours(int seconds) {
    final hours = seconds / 3600;
    return hours < 1 ? '${seconds ~/ 60} min' : '${hours.toStringAsFixed(1)} h';
  }
}
