import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:epubx/epubx.dart';

/// Metadatos que se pueden sacar de un EPUB sin abrirlo entero.
class EpubMetadata {
  final String? title;
  final String? author;

  /// Bytes de la portada tal cual vienen dentro del EPUB. No se decodifican a
  /// mapa de bits a propósito: se escriben directos a disco y es Flutter quien
  /// los decodifica al pintarlos.
  final Uint8List? coverBytes;

  /// Extensión que corresponde a [coverBytes] (`jpg`, `png`…), deducida del
  /// nombre del recurso dentro del EPUB.
  final String? coverExtension;

  const EpubMetadata({
    this.title,
    this.author,
    this.coverBytes,
    this.coverExtension,
  });

  bool get isEmpty =>
      (title == null || title!.isEmpty) &&
      (author == null || author!.isEmpty) &&
      coverBytes == null;
}

const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp'};

String _extensionOf(String href) {
  final clean = href.split('?').first.split('#').first;
  final dot = clean.lastIndexOf('.');
  if (dot == -1 || dot == clean.length - 1) return 'jpg';
  final ext = clean.substring(dot + 1).toLowerCase();
  return _imageExtensions.contains(ext) ? ext : 'jpg';
}

/// Lee título, autor y portada de un EPUB.
///
/// Nunca lanza: un EPUB con metadata rota o un zip corrupto se traduce en
/// campos vacíos, porque importar el libro debe funcionar igual aunque no se
/// pueda leer nada de esto.
Future<EpubMetadata> readEpubMetadata(File file) async {
  try {
    final bytes = await file.readAsBytes();
    final bookRef = await EpubReader.openBook(bytes);

    final title = bookRef.Title?.trim();
    final author = (bookRef.Author?.trim().isNotEmpty ?? false)
        ? bookRef.Author!.trim()
        : bookRef.AuthorList
            ?.whereType<String>()
            .map((a) => a.trim())
            .firstWhereOrNull((a) => a.isNotEmpty);

    final cover = await _readCover(bookRef);

    return EpubMetadata(
      title: title == null || title.isEmpty ? null : title,
      author: author == null || author.isEmpty ? null : author,
      coverBytes: cover?.$1,
      coverExtension: cover?.$2,
    );
  } catch (_) {
    return const EpubMetadata();
  }
}

/// Busca la portada por las tres vías habituales, en orden de fiabilidad:
/// el `<meta name="cover">` del OPF, la propiedad `cover-image` de EPUB 3 y,
/// como último recurso, una imagen cuyo nombre contenga "cover".
///
/// Se hace a mano en vez de usar `bookRef.readCover()` porque ese decodifica
/// la imagen con el paquete `image` (lento y con mucha memoria para nada:
/// solo queremos volcar los bytes a un archivo).
Future<(Uint8List, String)?> _readCover(EpubBookRef bookRef) async {
  final images = bookRef.Content?.Images;
  if (images == null || images.isEmpty) return null;

  final package = bookRef.Schema?.Package;
  final manifestItems = package?.Manifest?.Items ?? const [];

  String? href;

  final coverMeta = package?.Metadata?.MetaItems?.firstWhereOrNull(
    (meta) => meta.Name?.toLowerCase() == 'cover',
  );
  final coverId = coverMeta?.Content?.toLowerCase();
  if (coverId != null && coverId.isNotEmpty) {
    href = manifestItems
        .firstWhereOrNull((item) => item.Id?.toLowerCase() == coverId)
        ?.Href;
  }

  href ??= manifestItems
      .firstWhereOrNull(
        (item) => item.Properties?.toLowerCase().contains('cover-image') ?? false,
      )
      ?.Href;

  href ??= images.keys.firstWhereOrNull(
    (key) => key.toLowerCase().contains('cover'),
  );

  if (href == null) return null;

  // El href del manifiesto puede venir con la ruta relativa al OPF, mientras
  // que las claves de `Images` están normalizadas: si no casa tal cual, se
  // busca por el nombre de archivo.
  var contentRef = images[href];
  if (contentRef == null) {
    final fileName = href.split('/').last.toLowerCase();
    final key = images.keys.firstWhereOrNull(
      (k) => k.toLowerCase().endsWith(fileName),
    );
    if (key == null) return null;
    contentRef = images[key];
  }
  if (contentRef == null) return null;

  final content = await contentRef.readContentAsBytes();
  if (content.isEmpty) return null;

  return (Uint8List.fromList(content), _extensionOf(href));
}
