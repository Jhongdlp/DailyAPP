import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../core/providers/books_provider.dart';

/// Recoge los EPUB/PDF que llegan desde otras apps ("Abrir con", "Compartir
/// con") y los importa a la biblioteca.
///
/// Hay dos vías y las dos hacen falta: [getInitialMedia] cubre el arranque en
/// frío (la app estaba cerrada cuando compartieron el archivo) y el stream
/// cubre la app ya abierta.
class SharedBooksHandler {
  final WidgetRef ref;
  final void Function(int imported) onImported;
  StreamSubscription<List<SharedMediaFile>>? _subscription;

  SharedBooksHandler({required this.ref, required this.onImported});

  static bool get _supported => Platform.isAndroid || Platform.isIOS;

  void start() {
    if (!_supported) return;
    try {
      _subscription =
          ReceiveSharingIntent.instance.getMediaStream().listen(_handle);

      ReceiveSharingIntent.instance.getInitialMedia().then((files) {
        _handle(files);
        // Sin esto el mismo archivo se reimportaría en cada arranque.
        ReceiveSharingIntent.instance.reset();
      });
    } catch (_) {
      // Plataforma sin el plugin: compartir simplemente no está disponible
    }
  }

  Future<void> _handle(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;

    final paths = [
      for (final file in files)
        if (_isBook(file.path)) file.path,
    ];
    if (paths.isEmpty) return;

    final added = await ref.read(booksProvider.notifier).addBooksFromPaths(paths);
    if (added.isNotEmpty) onImported(added.length);
  }

  bool _isBook(String path) {
    final lower = path.toLowerCase().split('?').first;
    return lower.endsWith('.epub') || lower.endsWith('.pdf');
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
