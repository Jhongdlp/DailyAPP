import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/book_model.dart';
import '../services/cache_service.dart';
import '../services/epub_metadata_service.dart';
import 'book_highlights_provider.dart';
import 'settings_provider.dart';

final _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

const _bookColumns = 'id, user_id, title, author, format, local_filename, '
    'cover_image_filename, total_pages, last_position, progress_percent, '
    'added_at, last_opened_at';

Future<Directory> _booksDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/books');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

Future<Directory> _coversDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/books/covers');
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// Resuelve el nombre de archivo guardado contra el directorio local de
/// libros. La ruta absoluta puede cambiar entre instalaciones, por eso solo
/// se persiste el nombre de archivo y esta función resuelve la ruta en vivo.
Future<File> resolveBookFile(String localFilename) async {
  final dir = await _booksDir();
  return File('${dir.path}/$localFilename');
}

/// Resuelve la ruta local de la portada personalizada de un libro, si existe.
Future<File?> resolveBookCover(String? coverImageFilename) async {
  if (coverImageFilename == null || coverImageFilename.isEmpty) return null;
  final dir = await _coversDir();
  final file = File('${dir.path}/$coverImageFilename');
  return await file.exists() ? file : null;
}

class BooksNotifier extends Notifier<List<Book>> {
  @override
  List<Book> build() {
    _loadBooks();
    return [];
  }

  bool get _hasSupabase {
    final settings = ref.read(settingsProvider);
    return settings.isSupabaseConfigured &&
        Supabase.instance.client.auth.currentUser != null;
  }

  List<Book> _sorted(List<Book> books) {
    final sorted = [...books];
    sorted.sort((a, b) {
      final aOpened = a.lastOpenedAt;
      final bOpened = b.lastOpenedAt;
      if (aOpened != null && bOpened != null) return bOpened.compareTo(aOpened);
      if (aOpened != null) return -1;
      if (bOpened != null) return 1;
      return (b.addedAt ?? DateTime(0)).compareTo(a.addedAt ?? DateTime(0));
    });
    return sorted;
  }

  Future<void> _loadBooks() async {
    try {
      final cached = await CacheService.read('books');
      if (cached != null && cached is List) {
        state = _sorted(cached.map((e) => Book.fromCacheJson(e as Map<String, dynamic>)).toList());
      }
    } catch (_) {}

    try {
      if (!_hasSupabase) {
        if (state.isEmpty) state = [];
        return;
      }

      final client = Supabase.instance.client;
      final response = await client
          .from('books')
          .select(_bookColumns)
          .order('added_at', ascending: false);

      final books = (response as List).map((json) => Book.fromJson(json)).toList();
      state = _sorted(books);
      unawaited(CacheService.save('books', books.map((b) => b.toCacheJson()).toList()));
    } catch (e) {
      if (state.isEmpty) state = [];
    }
  }

  Future<void> refresh() => _loadBooks();

  /// Copia el archivo elegido por el usuario al directorio local de libros
  /// de la app y crea el registro de metadata correspondiente.
  Future<Book?> addBookFromPicker(PlatformFile pickedFile) {
    final path = pickedFile.path;
    if (path == null) return Future.value(null);
    return addBookFromPath(path, displayName: pickedFile.name);
  }

  /// Importa varios archivos de golpe (selección múltiple o "compartir con la
  /// app"). Devuelve los que se pudieron importar; los que fallan se saltan sin
  /// abortar el resto.
  Future<List<Book>> addBooksFromPaths(Iterable<String> paths) async {
    final added = <Book>[];
    for (final path in paths) {
      try {
        final book = await addBookFromPath(path);
        if (book != null) added.add(book);
      } catch (_) {
        // Un archivo ilegible no debe cancelar la importación de los demás
      }
    }
    return added;
  }

  /// Importa un archivo desde una ruta cualquiera del sistema.
  ///
  /// En los EPUB el título, el autor y la portada salen de la metadata del
  /// propio libro; el nombre del archivo solo se usa como respaldo, porque
  /// suele ser basura del tipo `9788401021_final_v2.epub`.
  Future<Book?> addBookFromPath(String path, {String? displayName}) async {
    final source = File(path);
    if (!await source.exists()) return null;

    final name = displayName ?? path.split(Platform.pathSeparator).last;
    final ext = name.split('.').last.toLowerCase();
    final format = ext == 'epub' ? BookFormat.epub : BookFormat.pdf;
    final safeBaseName = name.replaceAll(RegExp(r'[^\w\.\-]'), '_');
    final localFilename = '${DateTime.now().millisecondsSinceEpoch}_$safeBaseName';

    final dir = await _booksDir();
    final destFile = File('${dir.path}/$localFilename');
    await source.copy(destFile.path);

    final fallbackTitle =
        name.replaceAll(RegExp(r'\.(pdf|epub)$', caseSensitive: false), '');

    final id = DateTime.now().millisecondsSinceEpoch.toString();

    var title = fallbackTitle;
    String? author;
    String? coverFilename;

    if (format == BookFormat.epub) {
      final metadata = await readEpubMetadata(destFile);
      if (metadata.title != null) title = metadata.title!;
      author = metadata.author;
      if (metadata.coverBytes != null) {
        coverFilename = await _writeCoverBytes(
          id,
          metadata.coverBytes!,
          metadata.coverExtension ?? 'jpg',
        );
      }
    }

    final draft = Book(
      id: id,
      title: title,
      author: author,
      format: format,
      localFilename: localFilename,
      coverImageFilename: coverFilename,
      addedAt: DateTime.now(),
    );

    Book saved = draft;
    try {
      if (_hasSupabase) {
        final client = Supabase.instance.client;
        final response = await client
            .from('books')
            .insert(draft.toInsertJson(client.auth.currentUser!.id))
            .select(_bookColumns)
            .single();
        saved = Book.fromJson(response);
      }
    } catch (_) {
      // Se conserva el libro local si falla el guardado remoto
    }

    state = _sorted([saved, ...state]);
    unawaited(CacheService.save('books', state.map((b) => b.toCacheJson()).toList()));
    return saved;
  }

  Future<void> updateProgress(
    String id,
    String position, {
    int? totalPages,
    double? progressPercent,
  }) async {
    final index = state.indexWhere((b) => b.id == id);
    if (index == -1) return;

    final updated = state[index].copyWith(
      lastPosition: position,
      totalPages: totalPages,
      progressPercent: progressPercent,
      lastOpenedAt: DateTime.now(),
    );

    state = _sorted([
      for (final b in state)
        if (b.id == id) updated else b
    ]);
    unawaited(CacheService.save('books', state.map((b) => b.toCacheJson()).toList()));

    try {
      if (_hasSupabase && _uuidRegex.hasMatch(id)) {
        await Supabase.instance.client.from('books').update({
          'last_position': position,
          if (totalPages != null) 'total_pages': totalPages,
          if (progressPercent != null) 'progress_percent': progressPercent,
          'last_opened_at': updated.lastOpenedAt!.toUtc().toIso8601String(),
        }).eq('id', id);
      }
    } catch (_) {
      // Ignorar: el progreso local ya quedó guardado
    }
  }

  /// Edita título y/o autor. El autor se pasa vacío para borrarlo.
  Future<void> updateBookDetails(
    String id, {
    String? title,
    String? author,
  }) async {
    final index = state.indexWhere((b) => b.id == id);
    if (index == -1) return;

    final newTitle = title?.trim();
    final newAuthor = author?.trim();
    if (newTitle != null && newTitle.isEmpty) return;

    final previous = state[index];
    final updated = Book(
      id: previous.id,
      title: newTitle ?? previous.title,
      author: newAuthor == null
          ? previous.author
          : (newAuthor.isEmpty ? null : newAuthor),
      format: previous.format,
      localFilename: previous.localFilename,
      coverImageFilename: previous.coverImageFilename,
      totalPages: previous.totalPages,
      lastPosition: previous.lastPosition,
      progressPercent: previous.progressPercent,
      addedAt: previous.addedAt,
      lastOpenedAt: previous.lastOpenedAt,
    );

    state = _sorted([
      for (final b in state)
        if (b.id == id) updated else b
    ]);
    unawaited(CacheService.save('books', state.map((b) => b.toCacheJson()).toList()));

    try {
      if (_hasSupabase && _uuidRegex.hasMatch(id)) {
        await Supabase.instance.client.from('books').update({
          if (newTitle != null) 'title': newTitle,
          if (newAuthor != null) 'author': newAuthor.isEmpty ? null : newAuthor,
        }).eq('id', id);
      }
    } catch (_) {
      // La edición local ya quedó guardada
    }
  }

  /// Vuelve a leer título, autor y portada del EPUB y los reaplica. Útil cuando
  /// un libro se importó antes de que existiera la extracción de metadata.
  Future<bool> refreshEpubMetadata(String id) async {
    final index = state.indexWhere((b) => b.id == id);
    if (index == -1) return false;
    final book = state[index];
    if (book.format != BookFormat.epub) return false;

    final file = await resolveBookFile(book.localFilename);
    if (!await file.exists()) return false;

    final metadata = await readEpubMetadata(file);
    if (metadata.isEmpty) return false;

    if (metadata.coverBytes != null) {
      final coverFilename = await _writeCoverBytes(
        id,
        metadata.coverBytes!,
        metadata.coverExtension ?? 'jpg',
      );
      await _applyCover(id, coverFilename);
    }

    await updateBookDetails(
      id,
      title: metadata.title,
      author: metadata.author,
    );
    return true;
  }

  /// Escribe unos bytes de portada en el directorio de portadas y devuelve el
  /// nombre de archivo con el que quedaron guardados.
  Future<String> _writeCoverBytes(String id, Uint8List bytes, String ext) async {
    final dir = await _coversDir();
    final coverFilename = '${id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await File('${dir.path}/$coverFilename').writeAsBytes(bytes);
    return coverFilename;
  }

  /// Copia la imagen elegida por el usuario al directorio local de portadas
  /// y la asocia al libro, reemplazando la portada anterior si existía.
  Future<void> setCoverImage(String id, File imageFile) async {
    if (state.indexWhere((b) => b.id == id) == -1) return;

    final ext = imageFile.path.split('.').last.toLowerCase();
    final coverFilename = '${id}_${DateTime.now().millisecondsSinceEpoch}.$ext';

    final dir = await _coversDir();
    await imageFile.copy('${dir.path}/$coverFilename');

    await _applyCover(id, coverFilename);
  }

  /// Asocia una portada ya escrita en disco al libro y borra la anterior.
  Future<void> _applyCover(String id, String coverFilename) async {
    final index = state.indexWhere((b) => b.id == id);
    if (index == -1) return;
    final previous = state[index];
    final dir = await _coversDir();

    final updated = previous.copyWith(coverImageFilename: coverFilename);
    state = _sorted([
      for (final b in state)
        if (b.id == id) updated else b
    ]);
    unawaited(CacheService.save('books', state.map((b) => b.toCacheJson()).toList()));

    if (previous.coverImageFilename != null && previous.coverImageFilename!.isNotEmpty) {
      try {
        final oldFile = File('${dir.path}/${previous.coverImageFilename}');
        if (await oldFile.exists()) await oldFile.delete();
      } catch (_) {}
    }

    try {
      if (_hasSupabase && _uuidRegex.hasMatch(id)) {
        await Supabase.instance.client
            .from('books')
            .update({'cover_image_filename': coverFilename}).eq('id', id);
      }
    } catch (_) {
      // La portada local ya quedó guardada
    }
  }

  Future<void> deleteBook(String id) async {
    final book = state.firstWhere((b) => b.id == id, orElse: () => Book(
      id: id,
      title: '',
      format: BookFormat.pdf,
      localFilename: '',
    ));

    state = state.where((b) => b.id != id).toList();
    unawaited(CacheService.save('books', state.map((b) => b.toCacheJson()).toList()));

    // Los resaltados viven en local: sin el libro no tienen a qué anclarse.
    unawaited(ref.read(bookHighlightsProvider.notifier).deleteForBook(id));

    if (book.localFilename.isNotEmpty) {
      try {
        final file = await resolveBookFile(book.localFilename);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }

    if (book.coverImageFilename != null && book.coverImageFilename!.isNotEmpty) {
      try {
        final coverFile = await resolveBookCover(book.coverImageFilename);
        if (coverFile != null) await coverFile.delete();
      } catch (_) {}
    }

    try {
      if (_hasSupabase && _uuidRegex.hasMatch(id)) {
        await Supabase.instance.client.from('books').delete().eq('id', id);
      }
    } catch (_) {
      // Ignorar
    }
  }
}

final booksProvider = NotifierProvider<BooksNotifier, List<Book>>(() {
  return BooksNotifier();
});
