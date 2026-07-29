import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/book_model.dart';
import '../../../core/providers/books_provider.dart';
import '../../../core/theme/bento_theme.dart';

/// Futuros de portada memoizados por nombre de archivo.
///
/// Resolver la portada toca disco (`File.exists`), y en una cuadrícula eso se
/// repetiría en cada frame de scroll. La caché se invalida sola al cambiar la
/// portada porque el nombre de archivo lleva marca de tiempo.
final Map<String, Future<File?>> _coverFutures = {};

Future<File?> _coverFuture(String? filename) {
  if (filename == null || filename.isEmpty) return Future.value(null);
  return _coverFutures[filename] ??= resolveBookCover(filename);
}

/// Portada del libro, con respaldo tipográfico cuando no hay imagen.
class BookCover extends StatelessWidget {
  final Book book;
  final double width;
  final double height;
  final double borderRadius;

  const BookCover({
    super.key,
    required this.book,
    required this.width,
    required this.height,
    this.borderRadius = 10,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: FutureBuilder<File?>(
          future: _coverFuture(book.coverImageFilename),
          builder: (context, snapshot) {
            final file = snapshot.data;
            if (file == null) return _fallback();
            return Image.file(
              file,
              width: width,
              height: height,
              fit: BoxFit.cover,
              // Un EPUB puede traer una portada de 2000px; decodificarla al
              // tamaño de la tarjeta evita cargar el mapa de bits entero.
              cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (context, _, _) => _fallback(),
            );
          },
        ),
      ),
    );
  }

  /// Sin imagen se pinta el título: es más útil para distinguir libros de un
  /// vistazo que un icono genérico repetido.
  Widget _fallback() {
    final accent = book.format == BookFormat.pdf
        ? BentoTheme.accentOrange
        : BentoTheme.accentPurple;
    final compact = width < 60;

    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      padding: EdgeInsets.all(compact ? 4 : 10),
      color: accent.withValues(alpha: 0.16),
      child: compact
          ? Icon(
              book.format == BookFormat.pdf
                  ? Icons.picture_as_pdf_outlined
                  : Icons.menu_book_outlined,
              color: accent,
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  book.format == BookFormat.pdf
                      ? Icons.picture_as_pdf_outlined
                      : Icons.menu_book_outlined,
                  color: accent,
                  size: 22,
                ),
                const SizedBox(height: 8),
                Text(
                  book.title,
                  maxLines: 4,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.montserrat(
                    color: BentoTheme.creamAlpha(0.8),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
    );
  }
}
