import 'dart:async';

// `epubx` (reexportado por epub_view) trae su propio `Image`, que choca con el
// de Flutter; aquí solo interesa el de Material.
import 'package:epub_view/epub_view.dart' hide Image;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/models/book_model.dart';
import '../../core/providers/book_highlights_provider.dart';
import '../../core/providers/book_metrics_provider.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/reader_prefs_provider.dart';
import '../../core/providers/reader_theme_provider.dart';
import '../../core/providers/reading_stats_provider.dart';
import 'epub_internals.dart';
import 'reader_tts_controller.dart';
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
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
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

  /// Dónde va la lectura. Va por notificador y no por `setState` a propósito:
  /// el listener de posición de `EpubView` dispara en cada frame de scroll, y
  /// reconstruir la pantalla entera desde ahí obliga a `flutter_html` a
  /// re-inflar los párrafos visibles (cada `Html` se cuelga de un `GlobalKey`
  /// nuevo en cada build, así que su subárbol se rehace y se vuelve a medir).
  /// Ese remedido a mitad de scroll era el tirón.
  final ValueNotifier<_ReaderPosition> _position =
      ValueNotifier(const _ReaderPosition());

  /// Índice de texto plano listo: habilita la búsqueda.
  final ValueNotifier<bool> _indexReady = ValueNotifier(false);

  int get _currentParagraph => _position.value.paragraph;
  String? get _currentChapterTitle => _position.value.chapterTitle;

  /// Vista del libro memoizada por (tema, composición). Mientras esa pareja no
  /// cambie se devuelve la misma instancia de widget, de modo que repintar el
  /// chrome o arrastrar el brillo no toca el árbol del EPUB.
  Widget? _cachedReader;
  Object? _cachedReaderKey;

  bool _chromeVisible = true;
  bool _showResumeBanner = false;
  Timer? _resumeBannerTimer;

  DateTime? _sessionStart;
  int? _sessionStartWords;
  double? _systemBrightness;
  String? _pendingSelection;

  /// Ancla para localizar el `Scrollable` interno de la lista de `epub_view`.
  final GlobalKey _readerKey = GlobalKey();

  /// El `Scrollable` interno de la lista de `epub_view`, una vez localizado.
  ///
  /// El paquete no expone ni su `ScrollController` ni la física, así que la
  /// única vía para mover el libro por píxeles (pasar página, auto-scroll) es
  /// buscarlo en el árbol. Se vuelve a buscar cuando el que teníamos queda
  /// desmontado, porque `ScrollablePositionedList` alterna entre dos listas
  /// internas al animar saltos.
  ScrollableState? _listScrollable;

  /// Píxeles que el auto-scroll dejó a medias entre frames. Sin acumularlos, a
  /// velocidades bajas cada frame redondearía a cero y no se movería nada.
  double _autoScrollRemainder = 0;
  Duration _autoScrollLastTick = Duration.zero;
  Ticker? _autoScrollTicker;
  final ValueNotifier<bool> _autoScrolling = ValueNotifier(false);

  ReaderTtsController? _tts;

  /// Párrafo que se está leyendo en voz alta, para resaltarlo en el texto.
  final ValueNotifier<int?> _spokenParagraph = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initController();
    _applyReadingEnvironment();

    _tts = ReaderTtsController(
      paragraphs: () => _plainTexts ?? const [],
      onParagraph: (index) {
        _spokenParagraph.value = index;
        _jumpToParagraph(index);
      },
    )..addListener(_onTtsChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeBannerTimer?.cancel();
    _saveDebounce?.cancel();
    _autoScrollTicker?.dispose();
    _saveProgressNow();
    _endSession();
    _tts?.removeListener(_onTtsChanged);
    _tts?.dispose();
    _controller?.dispose();
    _position.dispose();
    _indexReady.dispose();
    _autoScrolling.dispose();
    _spokenParagraph.dispose();
    _restoreReadingEnvironment();
    super.dispose();
  }

  void _onTtsChanged() {
    if (!mounted) return;
    final tts = _tts;
    if (tts != null && !tts.isSpeaking) _spokenParagraph.value = null;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Salir de la app no debe perder ni la posición ni los minutos leídos.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveProgressNow();
      _endSession();
      // Desplazarse solo con la pantalla apagada perdería el sitio.
      _stopAutoScroll();
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

    _currentPosition = saved;
    _position.value = _ReaderPosition(paragraph: savedIndex ?? 0);

    setState(() {
      _controller = EpubController(
        document: EpubDocument.openFile(file),
        // Solo se pasa como CFI si no es un índice: el constructor no admite
        // índices, esos se resuelven al terminar de cargar.
        epubCfi: savedIndex == null ? saved : null,
      );
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
    _plainTexts = texts;
    _cumulativeWords = cumulative;
    // La biblioteca necesita el total para estimar el tiempo restante sin
    // volver a abrir el EPUB.
    ref.read(bookMetricsProvider.notifier).setWords(widget.book.id, total);
    _sessionStartWords ??= _wordsUpTo(_currentParagraph);
    _position.value = _position.value.copyWith(total: _paragraphs.length);
    _indexReady.value = true;
  }

  void _onChapterChanged(EpubChapterViewValue? value) {
    if (value == null) return;

    final next = _ReaderPosition(
      paragraph: value.position.index,
      total: _paragraphs.length,
      chapterTitle: value.chapter?.Title?.trim(),
    );
    if (next == _position.value) return;
    _position.value = next;

    _currentPosition = next.paragraph.toString();
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

  double? get _progress => _position.value.progress;

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

  // ─── Desplazamiento por píxeles ───────────────────────────────────────────

  /// Posición de scroll viva de la lista interna, o `null` si aún no se ha
  /// montado (o si la que teníamos quedó desmontada tras un salto animado).
  ScrollPosition? get _scrollPosition {
    var scrollable = _listScrollable;
    if (scrollable == null || !scrollable.mounted) {
      scrollable = _listScrollable = _findListScrollable();
    }
    if (scrollable == null) return null;
    final position = scrollable.position;
    return position.hasPixels ? position : null;
  }

  /// Localiza el `Scrollable` de la lista recorriendo el árbol bajo el lector.
  ///
  /// No sirve `Scrollable.maybeOf` desde el `chapterBuilder`:
  /// `ScrollablePositionedList` construye cada elemento con el contexto de su
  /// propio `State`, que está **por encima** del `Scrollable`, así que desde ahí
  /// siempre sale `null`. El primero que aparece en el recorrido es la lista
  /// primaria; la secundaria solo existe mientras se anima un salto.
  ScrollableState? _findListScrollable() {
    final root = _readerKey.currentContext;
    if (root == null) return null;

    ScrollableState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is ScrollableState) {
        found = element.state as ScrollableState;
        return;
      }
      element.visitChildren(visit);
    }

    (root as Element).visitChildren(visit);
    return found;
  }

  /// Pasa una pantalla de texto. Se deja un solapamiento para no cortar la
  /// línea que estaba justo en el borde: sin él se pierde una línea por página.
  void _turnPage(int direction) {
    final position = _scrollPosition;
    if (position == null) return;

    const overlap = 48.0;
    final step = (position.viewportDimension - overlap).clamp(1.0, double.infinity);
    final target = position.pixels + direction * step;

    position.animateTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  // ─── Auto-scroll ──────────────────────────────────────────────────────────

  /// Píxeles por segundo equivalentes al ritmo de lectura del usuario.
  ///
  /// Se estima en líneas: a [ReaderPrefs.wordsPerMinute] palabras por minuto y
  /// unas 11 palabras por línea salen las líneas por minuto, y cada línea mide
  /// `fontSize * lineHeight`. Es aproximado por definición, para eso está el
  /// multiplicador que el usuario ajusta a ojo.
  double get _autoScrollPixelsPerSecond {
    final prefs = ref.read(readerPrefsProvider);
    const wordsPerLine = 11.0;
    final linesPerMinute = prefs.wordsPerMinute / wordsPerLine;
    final lineHeightPx = prefs.fontSize * prefs.lineHeight;
    return (linesPerMinute * lineHeightPx / 60) * prefs.autoScrollSpeed;
  }

  void _toggleAutoScroll() {
    if (_autoScrolling.value) {
      _stopAutoScroll();
    } else {
      _startAutoScroll();
    }
  }

  void _startAutoScroll() {
    if (_autoScrolling.value) return;
    // Voz y auto-scroll compiten por mover la página; solo uno a la vez.
    _tts?.stop();

    _autoScrollRemainder = 0;
    _autoScrollLastTick = Duration.zero;
    _autoScrolling.value = true;

    _autoScrollTicker ??= createTicker(_onAutoScrollTick);
    _autoScrollTicker!.start();
  }

  void _stopAutoScroll() {
    if (!_autoScrolling.value) return;
    _autoScrollTicker?.stop();
    _autoScrolling.value = false;
  }

  void _onAutoScrollTick(Duration elapsed) {
    final position = _scrollPosition;
    if (position == null) return;

    // El primer tick solo sirve para fijar el origen del tiempo.
    if (_autoScrollLastTick == Duration.zero) {
      _autoScrollLastTick = elapsed;
      return;
    }

    final deltaSeconds =
        (elapsed - _autoScrollLastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _autoScrollLastTick = elapsed;

    _autoScrollRemainder += _autoScrollPixelsPerSecond * deltaSeconds;
    final step = _autoScrollRemainder.floorToDouble();
    if (step < 1) return;
    _autoScrollRemainder -= step;

    final target = position.pixels + step;
    if (target >= position.maxScrollExtent) {
      position.jumpTo(position.maxScrollExtent);
      _stopAutoScroll();
      return;
    }
    position.jumpTo(target);
  }

  // ─── Lectura en voz alta ──────────────────────────────────────────────────

  Future<void> _toggleTts() async {
    final tts = _tts;
    if (tts == null) return;

    if (tts.isSpeaking) {
      await tts.stop();
      return;
    }

    if (_plainTexts == null) {
      _snack('El libro todavía se está indexando');
      return;
    }

    _stopAutoScroll();
    final prefs = ref.read(readerPrefsProvider);
    await tts.start(
      fromParagraph: _currentParagraph,
      rate: prefs.ttsRate,
      language: prefs.ttsLanguage,
    );

    final error = tts.error;
    if (error != null) _snack(error);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    // Solo lo que recompone el texto: el brillo cambia `ReaderPrefs` en cada
    // frame del gesto y no debe reconstruir el libro.
    final composition = ref.watch(readerPrefsProvider.select((p) => p.composition));
    final paginated = ref.watch(readerPrefsProvider.select((p) => p.paginated));

    // Los resaltados cambian el HTML ya preparado.
    ref.listen(bookHighlightsProvider, (_, _) {
      _htmlCache.clear();
      _invalidateReader();
      if (mounted) setState(() {});
    });

    return Scaffold(
      backgroundColor: palette.background,
      body: controller == null
          ? Center(
              child: CircularProgressIndicator(color: palette.foregroundAlpha(0.5)),
            )
          : Stack(
              children: [
                Positioned.fill(
                  child: _gestureLayer(
                    paginated: paginated,
                    child: _scrollLock(
                      paginated: paginated,
                      child: _readerView(controller, readerMode, composition),
                    ),
                  ),
                ),
                // Las zonas de paso de página van por encima del texto: la
                // `SelectionArea` del lector se queda con los toques y los
                // arrastres horizontales, así que desde un ancestro nunca
                // llegan.
                if (paginated) ..._pageTapZones(),
                _buildBrightnessStrip(),
                _buildTopBar(palette),
                _buildBottomBar(palette),
                _buildResumeBanner(palette),
                _buildPlaybackBar(palette),
              ],
            ),
    );
  }

  /// Gestos del área de lectura. Vive fuera de la vista memoizada para que
  /// activar el paginado no obligue a `flutter_html` a recomponer el libro.
  Widget _gestureLayer({required bool paginated, required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) {
        // Cualquier toque interrumpe el auto-scroll: es el gesto natural para
        // "para, que quiero mirar esto".
        if (_autoScrolling.value) {
          _stopAutoScroll();
          return;
        }
        if (!paginated) {
          _toggleChrome();
          return;
        }

        final width = MediaQuery.sizeOf(context).width;
        final x = details.localPosition.dx;
        if (x < width * 0.3) {
          _turnPage(-1);
        } else if (x > width * 0.7) {
          _turnPage(1);
        } else {
          _toggleChrome();
        }
      },
      // Deslizar de lado pasa página; el deslizamiento vertical se lo queda la
      // lista, que sigue siendo la que desplaza el texto.
      onHorizontalDragEnd: paginated
          ? (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity.abs() < 150) return;
              _turnPage(velocity < 0 ? 1 : -1);
            }
          : null,
      child: child,
    );
  }

  /// En paginado el texto deja de desplazarse libremente: la única forma de
  /// avanzar es pasar página. `EpubView` no expone la física de su lista, así
  /// que se le impone desde la `ScrollConfiguration` que hereda.
  ///
  /// Va por fuera de la vista memoizada a propósito: cambiar la configuración
  /// solo repinta el `Scrollable`, no vuelve a inflar los párrafos.
  ///
  /// La `ScrollConfiguration` está **siempre** en el árbol y solo cambia la
  /// física: si apareciera y desapareciera con el paginado, `EpubView` quedaría
  /// en otra posición del árbol y Flutter lo remontaría. Al montarse el nuevo
  /// `State` se engancha al `EpubController` y, acto seguido, el `dispose` del
  /// viejo lo desengancha; la carga en curso se queda entonces sin `State` al
  /// que volver y el lector se queda cargando para siempre.
  Widget _scrollLock({required bool paginated, required Widget child}) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        physics: paginated ? const NeverScrollableScrollPhysics() : null,
        scrollbars: !paginated,
      ),
      child: child,
    );
  }

  /// Franjas laterales invisibles para pasar página con toque o deslizamiento.
  /// El centro se deja libre para seleccionar texto y para los enlaces.
  List<Widget> _pageTapZones() {
    final width = MediaQuery.sizeOf(context).width;
    final zoneWidth = width * 0.28;

    Widget zone({required bool left}) => Positioned(
          left: left ? 0 : null,
          right: left ? null : 0,
          top: 0,
          bottom: 0,
          width: zoneWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_autoScrolling.value) {
                _stopAutoScroll();
                return;
              }
              _turnPage(left ? -1 : 1);
            },
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity.abs() < 150) return;
              _turnPage(velocity < 0 ? 1 : -1);
            },
          ),
        );

    return [zone(left: true), zone(left: false)];
  }

  /// Devuelve la vista del libro memoizada: si el tema y la composición siguen
  /// siendo los mismos, se reutiliza la instancia anterior y Flutter salta el
  /// subárbol entero en vez de re-inflar los párrafos en pantalla.
  Widget _readerView(
    EpubController controller,
    ReaderThemeMode mode,
    ReaderComposition composition,
  ) {
    final key = (mode, composition);
    final cached = _cachedReader;
    if (cached != null && key == _cachedReaderKey) return cached;

    _cachedReaderKey = key;
    return _cachedReader = _buildReader(
      controller,
      readerPaletteFor(mode),
      ref.read(readerPrefsProvider),
    );
  }

  void _invalidateReader() {
    _cachedReader = null;
    _cachedReaderKey = null;
  }

  Widget _buildReader(
    EpubController controller,
    ReaderPalette palette,
    ReaderPrefs prefs,
  ) {
    final textStyle = prefs.textStyle(palette.textColor);

    final view = EpubView(
      key: _readerKey,
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
              // El resaltado de la voz se cuelga de un notificador y recibe el
              // párrafo ya construido como `child`: al avanzar la lectura solo
              // se repinta el fondo, no se vuelve a inflar el HTML.
              ValueListenableBuilder<int?>(
                valueListenable: _spokenParagraph,
                builder: (context, spoken, child) => ColoredBox(
                  color: spoken == index
                      ? palette.foregroundAlpha(0.09)
                      : Colors.transparent,
                  child: child,
                ),
                child: Html(
                  data: _paragraphHtml(index, paragraphs[index]),
                  onLinkTap: (href, _, _) {
                    if (href != null) onExternalLinkPressed(href);
                  },
                  style: {
                    'html': Style(
                      padding:
                          HtmlPaddings.symmetric(horizontal: prefs.horizontalMargin),
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
              ),
            ],
          );
        },
      ),
    );

    return SelectionArea(
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
              ValueListenableBuilder<bool>(
                valueListenable: _indexReady,
                builder: (context, ready, _) => IconButton(
                  tooltip: 'Buscar en el libro',
                  icon: Icon(Icons.search, color: palette.foreground),
                  onPressed: ready
                      ? () => showBookSearchSheet(
                            context,
                            palette: palette,
                            search: _search,
                            onJumpToParagraph: _jumpToParagraph,
                          )
                      : null,
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
              bookTitle: widget.book.title,
              onJumpToParagraph: _jumpToParagraph,
            );
          case 'tts':
            _toggleTts();
          case 'autoscroll':
            _toggleAutoScroll();
        }
      },
      itemBuilder: (context) => [
        _menuItem('bookmarks', Icons.bookmark_outline, 'Marcadores', palette),
        _menuItem('highlights', Icons.brush_outlined, 'Resaltados', palette),
        if (ReaderTtsController.isSupported)
          _menuItem(
            'tts',
            _tts?.isSpeaking == true ? Icons.stop_circle_outlined : Icons.headphones_outlined,
            _tts?.isSpeaking == true ? 'Detener la voz' : 'Leer en voz alta',
            palette,
          ),
        _menuItem(
          'autoscroll',
          _autoScrolling.value ? Icons.pause_circle_outline : Icons.slideshow_outlined,
          _autoScrolling.value ? 'Detener auto-scroll' : 'Auto-scroll',
          palette,
        ),
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
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: _chrome(
        offset: const Offset(0, 1),
        child: ValueListenableBuilder<_ReaderPosition>(
          valueListenable: _position,
          builder: (context, position, _) => _bottomBarContent(palette, position),
        ),
      ),
    );
  }

  /// Lo único que se repinta al desplazarse: la barra de progreso.
  Widget _bottomBarContent(ReaderPalette palette, _ReaderPosition position) {
    final progress = position.progress;
    final minutesLeft = _minutesLeft;

    return Container(
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
          if (position.total > 1)
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
                    _jumpToParagraph((value * (position.total - 1)).round()),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  position.chapterTitle ?? widget.book.title,
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
    );
  }

  /// Controles de la reproducción en curso (voz o auto-scroll).
  ///
  /// Se muestra por encima de la barra inferior y sobrevive al modo inmersivo:
  /// si el texto avanza solo, tiene que haber siempre una forma de pararlo.
  Widget _buildPlaybackBar(ReaderPalette palette) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: MediaQuery.viewPaddingOf(context).bottom + (_chromeVisible ? 76 : 16),
      child: ValueListenableBuilder<bool>(
        valueListenable: _autoScrolling,
        builder: (context, autoScrolling, _) {
          final speaking = _tts?.isSpeaking ?? false;
          if (!autoScrolling && !speaking) return const SizedBox.shrink();

          final prefs = ref.read(readerPrefsProvider);
          final notifier = ref.read(readerPrefsProvider.notifier);

          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    speaking ? Icons.graphic_eq : Icons.slideshow_outlined,
                    size: 17,
                    color: palette.foregroundAlpha(0.7),
                  ),
                  const SizedBox(width: 8),
                  _playbackButton(
                    palette,
                    Icons.remove,
                    'Más lento',
                    () => speaking
                        ? _changeTtsRate(prefs.ttsRate - 0.1)
                        : notifier.setAutoScrollSpeed(prefs.autoScrollSpeed - 0.2),
                  ),
                  Text(
                    speaking
                        ? '${(prefs.ttsRate * 100).round()}%'
                        : '${prefs.autoScrollSpeed.toStringAsFixed(1)}×',
                    style: GoogleFonts.montserrat(
                      color: palette.foregroundAlpha(0.75),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  _playbackButton(
                    palette,
                    Icons.add,
                    'Más rápido',
                    () => speaking
                        ? _changeTtsRate(prefs.ttsRate + 0.1)
                        : notifier.setAutoScrollSpeed(prefs.autoScrollSpeed + 0.2),
                  ),
                  const SizedBox(width: 2),
                  _playbackButton(
                    palette,
                    Icons.stop,
                    'Detener',
                    () => speaking ? _tts?.stop() : _stopAutoScroll(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _playbackButton(
    ReaderPalette palette,
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
  ) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: palette.foregroundAlpha(0.75)),
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
      onPressed: () {
        onPressed();
        setState(() {});
      },
    );
  }

  void _changeTtsRate(double rate) {
    final clamped = rate.clamp(
      ReaderPrefsNotifier.ttsRateRange.min,
      ReaderPrefsNotifier.ttsRateRange.max,
    );
    ref.read(readerPrefsProvider.notifier).setTtsRate(clamped);
    _tts?.setRate(clamped);
  }

  Widget _buildResumeBanner(ReaderPalette palette) {
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
                  child: ValueListenableBuilder<_ReaderPosition>(
                    valueListenable: _position,
                    builder: (context, position, _) {
                      final chapter = position.chapterTitle;
                      return Text(
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
                      );
                    },
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

/// Instantánea de por dónde va la lectura.
///
/// Se compara por valor para que el notificador no dispare en cada frame de
/// scroll, solo cuando de verdad cambia el párrafo o el capítulo visible.
class _ReaderPosition {
  final int paragraph;

  /// Párrafos del libro. Es 0 hasta que `chapterBuilder` entrega la lista.
  final int total;

  final String? chapterTitle;

  const _ReaderPosition({
    this.paragraph = 0,
    this.total = 0,
    this.chapterTitle,
  });

  double? get progress =>
      total == 0 ? null : ((paragraph + 1) / total).clamp(0.0, 1.0);

  _ReaderPosition copyWith({int? paragraph, int? total, String? chapterTitle}) =>
      _ReaderPosition(
        paragraph: paragraph ?? this.paragraph,
        total: total ?? this.total,
        chapterTitle: chapterTitle ?? this.chapterTitle,
      );

  @override
  bool operator ==(Object other) =>
      other is _ReaderPosition &&
      other.paragraph == paragraph &&
      other.total == total &&
      other.chapterTitle == chapterTitle;

  @override
  int get hashCode => Object.hash(paragraph, total, chapterTitle);
}
