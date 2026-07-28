import 'dart:async';

// `epubx` (reexportado por epub_view) trae su propio `Image`, que choca con el
// de Flutter; aquí solo interesa el de Material.
import 'package:epub_view/epub_view.dart' hide Image;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/models/book_model.dart';
import '../../core/providers/book_highlights_provider.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/reader_prefs_provider.dart';
import '../../core/providers/reader_theme_provider.dart';
import '../../core/providers/reading_stats_provider.dart';
import 'epub_internals.dart';
import 'widgets/book_bookmarks_sheet.dart';
import 'widgets/book_highlights_sheet.dart';
import 'widgets/book_search_sheet.dart';
import 'widgets/book_toc_sheet.dart';
import 'widgets/reader_settings_sheet.dart';
import 'widgets/selection_actions_sheet.dart';

class EpubReaderScreen extends ConsumerStatefulWidget {
  final Book book;
  const EpubReaderScreen({super.key, required this.book});

  @override
  ConsumerState<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends ConsumerState<EpubReaderScreen>
    with WidgetsBindingObserver {
  EpubController? _controller;

  /// Posición guardada del libro. Es el índice de párrafo como texto: los CFI
  /// que genera epub_view son frágiles y su parser falla en silencio ante casi
  /// cualquier discrepancia de formato, además de recorrer el DOM en cada
  /// scroll. Las posiciones antiguas en CFI se siguen resolviendo al abrir.
  String? _currentPosition;
  Timer? _saveDebounce;

  /// Párrafos y capítulos del libro, capturados la primera vez que
  /// `chapterBuilder` los entrega: el controlador no los expone y los
  /// necesitamos para progreso, búsqueda y resaltados.
  List<Paragraph> _paragraphs = const [];
  List<EpubChapter> _chapters = const [];

  /// Texto plano por párrafo y palabras acumuladas hasta cada uno. Se calculan
  /// una sola vez tras cargar el libro: así buscar y estimar el tiempo restante
  /// no recorren el documento en cada frame.
  List<String>? _plainTexts;
  List<int>? _cumulativeWords;

  /// HTML ya preparado por párrafo, con los resaltados inyectados. Se invalida
  /// cuando cambian los resaltados o la composición del texto.
  final Map<int, String> _htmlCache = {};

  int _currentParagraph = 0;
  String? _currentChapterTitle;

  bool _chromeVisible = true;
  bool _showResumeBanner = false;
  Timer? _resumeBannerTimer;

  DateTime? _sessionStart;
  int? _sessionStartWords;
  double? _systemBrightness;
  String? _pendingSelection;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initController();
    _applyReadingEnvironment();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeBannerTimer?.cancel();
    _saveDebounce?.cancel();
    _saveProgressNow();
    _endSession();
    _controller?.dispose();
    _restoreReadingEnvironment();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Salir de la app no debe perder ni la posición ni los minutos leídos.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveProgressNow();
      _endSession();
    } else if (state == AppLifecycleState.resumed) {
      _startSession();
    }
  }

  // ─── Entorno de lectura ───────────────────────────────────────────────────

  Future<void> _applyReadingEnvironment() async {
    final prefs = ref.read(readerPrefsProvider);
    if (prefs.keepScreenOn) unawaited(WakelockPlus.enable());

    try {
      _systemBrightness = await ScreenBrightness().application;
      if (prefs.brightness != null) {
        await ScreenBrightness().setApplicationScreenBrightness(prefs.brightness!);
      }
    } catch (_) {
      // Plataforma sin control de brillo (escritorio): se ignora
    }
  }

  Future<void> _restoreReadingEnvironment() async {
    unawaited(WakelockPlus.disable());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    try {
      await ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {}
  }

  Future<void> _setBrightness(double? value) async {
    try {
      if (value == null) {
        await ScreenBrightness().resetApplicationScreenBrightness();
      } else {
        await ScreenBrightness().setApplicationScreenBrightness(value);
      }
    } catch (_) {}
  }

  /// Deslizar por el borde izquierdo cambia el brillo solo dentro del lector.
  void _onBrightnessDrag(DragUpdateDetails details) {
    final height = MediaQuery.sizeOf(context).height;
    final current =
        ref.read(readerPrefsProvider).brightness ?? _systemBrightness ?? 0.5;
    final next = (current - details.delta.dy / height).clamp(0.01, 1.0);
    ref.read(readerPrefsProvider.notifier).setBrightness(next);
    _setBrightness(next);
  }

  // ─── Carga y posición ─────────────────────────────────────────────────────

  Future<void> _initController() async {
    final file = await resolveBookFile(widget.book.localFilename);
    if (!mounted) return;

    final saved = widget.book.lastPosition;
    final savedIndex = int.tryParse(saved ?? '');

    setState(() {
      _controller = EpubController(
        document: EpubDocument.openFile(file),
        // Solo se pasa como CFI si no es un índice: el constructor no admite
        // índices, esos se resuelven al terminar de cargar.
        epubCfi: savedIndex == null ? saved : null,
      );
      _currentPosition = saved;
      _currentParagraph = savedIndex ?? 0;
    });
  }

  void _onDocumentLoaded(EpubBook document) {
    _startSession();

    final savedIndex = int.tryParse(widget.book.lastPosition ?? '');
    if (savedIndex != null && savedIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller?.jumpTo(index: savedIndex);
      });
    }

    if ((widget.book.lastPosition ?? '').isNotEmpty) {
      setState(() => _showResumeBanner = true);
      _resumeBannerTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _showResumeBanner = false);
      });
    }
  }

  /// Índice de texto plano y palabras acumuladas. Se construye fuera del primer
  /// frame porque en libros largos recorrer todos los párrafos se nota.
  void _buildTextIndex() {
    if (_plainTexts != null || _paragraphs.isEmpty) return;

    final texts = <String>[];
    final cumulative = <int>[];
    var total = 0;

    for (final paragraph in _paragraphs) {
      final text = paragraph.element.text.trim();
      texts.add(text);
      total += text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
      cumulative.add(total);
    }

    if (!mounted) return;
    setState(() {
      _plainTexts = texts;
      _cumulativeWords = cumulative;
      _sessionStartWords ??= _wordsUpTo(_currentParagraph);
    });
  }

  void _onChapterChanged(EpubChapterViewValue? value) {
    if (value == null) return;

    final paragraph = value.position.index;
    final chapterTitle = value.chapter?.Title?.trim();
    if (paragraph == _currentParagraph && chapterTitle == _currentChapterTitle) {
      return;
    }

    setState(() {
      _currentParagraph = paragraph;
      _currentChapterTitle = chapterTitle;
    });

    _currentPosition = paragraph.toString();
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), _saveProgressNow);
  }

  void _saveProgressNow() {
    final position = _currentPosition;
    if (position == null) return;

    final percent = _progress;
    ref.read(booksProvider.notifier).updateProgress(
          widget.book.id,
          position,
          progressPercent: percent,
        );

    if (percent != null && percent >= 0.98) {
      final result = ref
          .read(readingStatsProvider.notifier)
          .registerBookFinished(widget.book.id);
      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('¡Terminaste "${widget.book.title}"! +80 XP')),
        );
      }
    }
  }

  // ─── Sesión de lectura ────────────────────────────────────────────────────

  void _startSession() {
    _sessionStart ??= DateTime.now();
    _sessionStartWords ??= _wordsUpTo(_currentParagraph);
  }

  void _endSession() {
    final start = _sessionStart;
    if (start == null) return;
    _sessionStart = null;

    final seconds = DateTime.now().difference(start).inSeconds;
    ref.read(readingStatsProvider.notifier).registerSession(
          startedAt: start,
          seconds: seconds,
        );

    // Ajusta la velocidad estimada con el ritmo real de esta sesión, para que
    // el "tiempo restante" converja a cómo lee de verdad esta persona.
    final startWords = _sessionStartWords;
    if (startWords != null && seconds > 120) {
      final words = _wordsUpTo(_currentParagraph) - startWords;
      if (words > 200) {
        ref
            .read(readerPrefsProvider.notifier)
            .registerReadingSpeed(words / (seconds / 60));
      }
    }
    _sessionStartWords = null;
  }

  int _wordsUpTo(int paragraphIndex) {
    final cumulative = _cumulativeWords;
    if (cumulative == null || cumulative.isEmpty) return 0;
    return cumulative[paragraphIndex.clamp(0, cumulative.length - 1)];
  }

  // ─── Progreso ─────────────────────────────────────────────────────────────

  double? get _progress {
    if (_paragraphs.isEmpty) return null;
    return ((_currentParagraph + 1) / _paragraphs.length).clamp(0.0, 1.0);
  }

  /// Minutos que faltan para acabar el libro al ritmo estimado del usuario.
  int? get _minutesLeft {
    final cumulative = _cumulativeWords;
    if (cumulative == null || cumulative.isEmpty) return null;

    final remaining = cumulative.last - _wordsUpTo(_currentParagraph);
    if (remaining <= 0) return 0;

    return (remaining / ref.read(readerPrefsProvider).wordsPerMinute).ceil();
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}min';
  }

  // ─── Navegación ───────────────────────────────────────────────────────────

  void _jumpToParagraph(int index) {
    final controller = _controller;
    if (controller == null || _paragraphs.isEmpty) return;
    controller.scrollTo(
      index: index.clamp(0, _paragraphs.length - 1),
      duration: const Duration(milliseconds: 200),
    );
  }

  /// Acepta tanto índices de párrafo (formato nuevo) como CFI (marcadores
  /// creados antes del cambio de formato).
  void _jumpToSavedPosition(String position) {
    final index = int.tryParse(position);
    if (index != null) {
      _jumpToParagraph(index);
    } else {
      _controller?.gotoEpubCfi(position);
    }
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    SystemChrome.setEnabledSystemUIMode(
      _chromeVisible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  // ─── Búsqueda ─────────────────────────────────────────────────────────────

  List<BookSearchHit> _search(String query) {
    final texts = _plainTexts;
    if (texts == null) return const [];

    final needle = query.toLowerCase();
    final hits = <BookSearchHit>[];

    for (var i = 0; i < texts.length && hits.length < 100; i++) {
      final text = texts[i];
      final at = text.toLowerCase().indexOf(needle);
      if (at == -1) continue;

      // Ventana de contexto alrededor de la coincidencia.
      final start = (at - 60).clamp(0, text.length);
      final end = (at + needle.length + 80).clamp(0, text.length);
      final prefix = start > 0 ? '…' : '';
      final suffix = end < text.length ? '…' : '';

      hits.add(BookSearchHit(
        paragraphIndex: i,
        snippet: '$prefix${text.substring(start, end)}$suffix',
        matchStart: at - start + prefix.length,
        matchLength: needle.length,
        chapterTitle: _chapterTitleForParagraph(i),
      ));
    }

    return hits;
  }

  String? _chapterTitleForParagraph(int paragraphIndex) {
    if (paragraphIndex < 0 || paragraphIndex >= _paragraphs.length) return null;
    final chapterIndex = _paragraphs[paragraphIndex].chapterIndex;
    if (chapterIndex < 0 || chapterIndex >= _chapters.length) return null;
    return _chapters[chapterIndex].Title?.trim();
  }

  // ─── Selección de texto ───────────────────────────────────────────────────

  /// Localiza el párrafo del texto seleccionado buscando en espiral desde la
  /// posición actual, que es donde está prácticamente siempre.
  int? _paragraphForSelection(String selection) {
    final texts = _plainTexts;
    if (texts == null || selection.isEmpty) return null;

    final probe = selection.length > 40 ? selection.substring(0, 40) : selection;
    for (var offset = 0; offset < texts.length; offset++) {
      for (final index in {_currentParagraph + offset, _currentParagraph - offset}) {
        if (index < 0 || index >= texts.length) continue;
        if (texts[index].contains(probe)) return index;
      }
    }
    return null;
  }

  void _openSelectionActions(SelectableRegionState selectableRegionState) {
    final selection = _pendingSelection?.trim();
    selectableRegionState.hideToolbar();
    if (selection == null || selection.isEmpty) return;

    final paragraphIndex = _paragraphForSelection(selection);

    showSelectionActionsSheet(
      context,
      palette: readerPaletteFor(ref.read(readerThemeProvider)),
      bookId: widget.book.id,
      bookTitle: widget.book.title,
      selectedText: selection,
      position: paragraphIndex?.toString() ?? _currentPosition,
      paragraphIndex: paragraphIndex,
      chapterTitle: paragraphIndex == null
          ? _currentChapterTitle
          : _chapterTitleForParagraph(paragraphIndex),
    );
  }

  // ─── Pintado ──────────────────────────────────────────────────────────────

  /// HTML del párrafo con los resaltados marcados.
  ///
  /// El resaltado se guarda como texto plano, así que solo puede reinyectarse
  /// cuando aparece literalmente en el HTML; si el fragmento cruzaba etiquetas
  /// (cursivas, notas al pie) se queda sin marcar en el cuerpo del texto, pero
  /// sigue existiendo en la lista de resaltados.
  String _paragraphHtml(int index, Paragraph paragraph) {
    final cached = _htmlCache[index];
    if (cached != null) return cached;

    var html = paragraph.element.outerHtml;
    final highlights =
        ref.read(bookHighlightsProvider.notifier).forParagraph(widget.book.id, index);

    for (final highlight in highlights) {
      if (highlight.text.isEmpty || !html.contains(highlight.text)) continue;
      final hex = highlight.color.color
          .toARGB32()
          .toRadixString(16)
          .padLeft(8, '0')
          .substring(2);
      html = html.replaceFirst(
        highlight.text,
        '<mark style="background-color:#$hex">${highlight.text}</mark>',
      );
    }

    _htmlCache[index] = html;
    return html;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final readerMode = ref.watch(readerThemeProvider);
    final palette = readerPaletteFor(readerMode);
    final prefs = ref.watch(readerPrefsProvider);

    // Los resaltados cambian el HTML ya preparado.
    ref.listen(bookHighlightsProvider, (_, _) => _htmlCache.clear());

    return Scaffold(
      backgroundColor: palette.background,
      body: controller == null
          ? Center(
              child: CircularProgressIndicator(color: palette.foregroundAlpha(0.5)),
            )
          : Stack(
              children: [
                Positioned.fill(child: _buildReader(controller, palette, prefs)),
                _buildBrightnessStrip(),
                _buildTopBar(palette),
                _buildBottomBar(palette),
                _buildResumeBanner(palette),
              ],
            ),
    );
  }

  Widget _buildReader(
    EpubController controller,
    ReaderPalette palette,
    ReaderPrefs prefs,
  ) {
    final textStyle = prefs.textStyle(palette.textColor);

    final view = EpubView(
      controller: controller,
      onDocumentLoaded: _onDocumentLoaded,
      onChapterChanged: _onChapterChanged,
      builders: EpubViewBuilders<DefaultBuilderOptions>(
        options: DefaultBuilderOptions(textStyle: textStyle),
        loaderBuilder: (context) => Center(
          child: CircularProgressIndicator(color: palette.foregroundAlpha(0.5)),
        ),
        chapterDividerBuilder: (chapter) => _chapterDivider(chapter, palette),
        chapterBuilder: (
          context,
          builders,
          document,
          chapters,
          paragraphs,
          index,
          chapterIndex,
          paragraphIndex,
          onExternalLinkPressed,
        ) {
          if (paragraphs.isEmpty) return const SizedBox.shrink();

          // Primera pasada: nos quedamos con las referencias del documento.
          if (_paragraphs.length != paragraphs.length) {
            _paragraphs = paragraphs;
            _chapters = chapters;
            WidgetsBinding.instance.addPostFrameCallback((_) => _buildTextIndex());
          }

          return Column(
            children: [
              if (chapterIndex >= 0 && paragraphIndex == 0)
                _chapterDivider(chapters[chapterIndex], palette),
              Html(
                data: _paragraphHtml(index, paragraphs[index]),
                onLinkTap: (href, _, _) {
                  if (href != null) onExternalLinkPressed(href);
                },
                style: {
                  'html': Style(
                    padding: HtmlPaddings.symmetric(horizontal: prefs.horizontalMargin),
                    textAlign: prefs.justify ? TextAlign.justify : TextAlign.start,
                  ).merge(Style.fromTextStyle(textStyle)),
                  'mark': Style(color: palette.textColor),
                  'a': Style(color: palette.textColor),
                },
                extensions: [
                  TagExtension(
                    tagsToExtend: const {'img'},
                    builder: (imageContext) => _bookImage(imageContext, document),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleChrome,
      child: SelectionArea(
        onSelectionChanged: (content) => _pendingSelection = content?.plainText,
        contextMenuBuilder: (context, selectableRegionState) =>
            AdaptiveTextSelectionToolbar.buttonItems(
          anchors: selectableRegionState.contextMenuAnchors,
          buttonItems: [
            ContextMenuButtonItem(
              label: 'Acciones',
              onPressed: () => _openSelectionActions(selectableRegionState),
            ),
            ...selectableRegionState.contextMenuButtonItems,
          ],
        ),
        child: view,
      ),
    );
  }

  Widget _bookImage(ExtensionContext imageContext, EpubBook document) {
    final src = imageContext.attributes['src']?.replaceAll('../', '');
    final content = src == null ? null : document.Content?.Images?[src]?.Content;
    if (content == null) return const SizedBox.shrink();
    return Image.memory(Uint8List.fromList(content), fit: BoxFit.contain);
  }

  Widget _chapterDivider(EpubChapter chapter, ReaderPalette palette) {
    final title = chapter.Title?.trim();
    if (title == null || title.isEmpty) return const SizedBox(height: 24);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.montserrat(
              color: palette.foreground,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: palette.foregroundAlpha(0.12)),
        ],
      ),
    );
  }

  // ─── Superposiciones ──────────────────────────────────────────────────────

  Widget _buildBrightnessStrip() {
    return Positioned(
      left: 0,
      top: 80,
      bottom: 80,
      width: 32,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: _onBrightnessDrag,
      ),
    );
  }

  Widget _buildTopBar(ReaderPalette palette) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: _chrome(
        offset: const Offset(0, -1),
        child: Container(
          color: palette.background.withValues(alpha: 0.96),
          padding: EdgeInsets.only(
            top: MediaQuery.viewPaddingOf(context).top + 4,
            bottom: 6,
            left: 2,
            right: 2,
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: palette.foreground),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(
                  widget.book.title,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.montserrat(
                    color: palette.foreground,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Buscar en el libro',
                icon: Icon(Icons.search, color: palette.foreground),
                onPressed: _plainTexts == null
                    ? null
                    : () => showBookSearchSheet(
                          context,
                          palette: palette,
                          search: _search,
                          onJumpToParagraph: _jumpToParagraph,
                        ),
              ),
              IconButton(
                tooltip: 'Índice',
                icon: Icon(Icons.list_alt_outlined, color: palette.foreground),
                onPressed: () => showBookTocSheet(
                  context,
                  palette: palette,
                  chapters: _controller?.tableOfContents() ?? const [],
                  currentParagraphIndex: _currentParagraph,
                  onJumpToParagraph: _jumpToParagraph,
                ),
              ),
              IconButton(
                tooltip: 'Tipografía y tema',
                icon: Icon(Icons.text_fields, color: palette.foreground),
                onPressed: () => showReaderSettingsSheet(
                  context,
                  palette: palette,
                  onBrightnessChanged: _setBrightness,
                ),
              ),
              _moreMenu(palette),
            ],
          ),
        ),
      ),
    );
  }

  Widget _moreMenu(ReaderPalette palette) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: palette.foreground),
      color: palette.surface,
      onSelected: (value) {
        switch (value) {
          case 'bookmarks':
            showBookBookmarksSheet(
              context,
              bookId: widget.book.id,
              currentPosition: _currentParagraph.toString(),
              onJumpTo: _jumpToSavedPosition,
            );
          case 'highlights':
            showBookHighlightsSheet(
              context,
              palette: palette,
              bookId: widget.book.id,
              onJumpToParagraph: _jumpToParagraph,
            );
        }
      },
      itemBuilder: (context) => [
        _menuItem('bookmarks', Icons.bookmark_outline, 'Marcadores', palette),
        _menuItem('highlights', Icons.brush_outlined, 'Resaltados', palette),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    ReaderPalette palette,
  ) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: palette.foregroundAlpha(0.7)),
          const SizedBox(width: 10),
          Text(
            label,
            style: GoogleFonts.montserrat(color: palette.foreground, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ReaderPalette palette) {
    final progress = _progress;
    final minutesLeft = _minutesLeft;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: _chrome(
        offset: const Offset(0, 1),
        child: Container(
          color: palette.background.withValues(alpha: 0.96),
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 6,
            bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_paragraphs.length > 1)
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: palette.foregroundAlpha(0.6),
                    inactiveTrackColor: palette.foregroundAlpha(0.12),
                    thumbColor: palette.foreground,
                    overlayColor: palette.foregroundAlpha(0.1),
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: progress ?? 0,
                    onChanged: (value) =>
                        _jumpToParagraph((value * (_paragraphs.length - 1)).round()),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _currentChapterTitle ?? widget.book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.montserrat(
                        color: palette.foregroundAlpha(0.6),
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    [
                      if (progress != null) '${(progress * 100).round()}%',
                      if (minutesLeft != null && minutesLeft > 0)
                        '${_formatMinutes(minutesLeft)} restantes',
                    ].join(' · '),
                    style: GoogleFonts.montserrat(
                      color: palette.foregroundAlpha(0.6),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResumeBanner(ReaderPalette palette) {
    final chapter = _currentChapterTitle;

    return Positioned(
      top: MediaQuery.viewPaddingOf(context).top + 60,
      left: 20,
      right: 20,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _showResumeBanner ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.bookmark_added_outlined,
                    size: 17, color: palette.foregroundAlpha(0.7)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    chapter == null || chapter.isEmpty
                        ? 'Retomas donde lo dejaste'
                        : 'Retomas en $chapter',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.montserrat(
                      color: palette.foregroundAlpha(0.8),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Barras que se esconden en modo inmersivo.
  Widget _chrome({required Offset offset, required Widget child}) {
    return IgnorePointer(
      ignoring: !_chromeVisible,
      child: AnimatedSlide(
        offset: _chromeVisible ? Offset.zero : offset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _chromeVisible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: child,
        ),
      ),
    );
  }
}
