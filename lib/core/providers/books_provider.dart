import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/book_model.dart';
import '../services/cache_service.dart';
import 'settings_provider.dart';

final _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

const _bookColumns = 'id, user_id, title, author, format, local_filename, '
    'total_pages, last_position, progress_percent, added_at, last_opened_at';

Future<Directory> _booksDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory('${docs.path}/books');
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
  Future<Book?> addBookFromPicker(PlatformFile pickedFile) async {
    final path = pickedFile.path;
    if (path == null) return null;

    final ext = pickedFile.extension?.toLowerCase();
    final format = ext == 'epub' ? BookFormat.epub : BookFormat.pdf;
    final safeBaseName = pickedFile.name.replaceAll(RegExp(r'[^\w\.\-]'), '_');
    final localFilename = '${DateTime.now().millisecondsSinceEpoch}_$safeBaseName';

    final dir = await _booksDir();
    final destFile = File('${dir.path}/$localFilename');
    await File(path).copy(destFile.path);

    final rawTitle = pickedFile.name.replaceAll(RegExp(r'\.(pdf|epub)$', caseSensitive: false), '');

    final draft = Book(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: rawTitle,
      format: format,
      localFilename: localFilename,
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

  Future<void> deleteBook(String id) async {
    final book = state.firstWhere((b) => b.id == id, orElse: () => Book(
      id: id,
      title: '',
      format: BookFormat.pdf,
      localFilename: '',
    ));

    state = state.where((b) => b.id != id).toList();
    unawaited(CacheService.save('books', state.map((b) => b.toCacheJson()).toList()));

    if (book.localFilename.isNotEmpty) {
      try {
        final file = await resolveBookFile(book.localFilename);
        if (await file.exists()) await file.delete();
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
