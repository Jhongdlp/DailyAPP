import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/models/news_model.dart';

/// Exporta un [NewsDigest] como periódico maquetado en PDF.
///
/// Usa las fuentes Times integradas del paquete `pdf` en vez de Google Fonts:
/// no requieren red ni assets, y su codificación WinAnsi cubre las tildes y la
/// eñe de los resúmenes en español.
class NewsPdfService {
  static const _months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  static const _weekdays = [
    'lunes', 'martes', 'miércoles', 'jueves',
    'viernes', 'sábado', 'domingo',
  ];

  /// Se formatea a mano en vez de con `intl`: `DateFormat` con locale `es`
  /// exige inicializar los símbolos de fecha, y esto es una sola cadena.
  static String _longDate(DateTime date) {
    final weekday = _weekdays[date.weekday - 1];
    final month = _months[date.month - 1];
    return '$weekday ${date.day} de $month de ${date.year}';
  }

  static String _shortDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Genera el PDF y lo guarda en el directorio de documentos.
  /// Devuelve la ruta del archivo, lista para `open_filex`.
  static Future<String> export(NewsDigest digest) async {
    final serif = pw.Font.times();
    final serifBold = pw.Font.timesBold();
    final serifItalic = pw.Font.timesItalic();

    final doc = pw.Document(
      title: 'Sistem Daily — ${_shortDate(digest.date)}',
      author: 'Sistem Daily',
    );

    final items = digest.items;
    final lead = items.isNotEmpty ? items.first : null;
    final rest = items.length > 1 ? items.sublist(1) : <NewsItem>[];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(38, 40, 38, 44),
        theme: pw.ThemeData.withFont(base: serif, bold: serifBold, italic: serifItalic),
        footer: (context) => pw.Container(
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(width: 0.5)),
          ),
          padding: const pw.EdgeInsets.only(top: 6),
          margin: const pw.EdgeInsets.only(top: 12),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('SISTEM DAILY',
                  style: pw.TextStyle(fontSize: 7, letterSpacing: 1.4, color: PdfColors.grey700)),
              pw.Text('${context.pageNumber} / ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
            ],
          ),
        ),
        build: (context) => [
          _masthead(digest),
          if (digest.editorial.trim().isNotEmpty) _editorial(digest.editorial),
          if (lead != null) _leadStory(lead),
          for (final category in _categoriesOf(rest)) ...[
            _sectionHeader(category.label),
            ..._twoColumnRows(_ofCategory(rest, category)),
          ],
        ],
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/sistem_daily_${_shortDate(digest.date)}.pdf');
    await file.writeAsBytes(await doc.save());
    return file.path;
  }

  static List<NewsCategory> _categoriesOf(List<NewsItem> items) => [
        for (final category in NewsCategory.values)
          if (items.any((item) => item.category == category)) category,
      ];

  static List<NewsItem> _ofCategory(List<NewsItem> items, NewsCategory category) =>
      [for (final item in items) if (item.category == category) item];

  static pw.Widget _masthead(NewsDigest digest) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(height: 3, color: PdfColors.black),
        pw.SizedBox(height: 8),
        pw.Center(
          child: pw.Text(
            'SISTEM DAILY',
            style: pw.TextStyle(fontSize: 40, fontWeight: pw.FontWeight.bold, letterSpacing: 3),
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Container(height: 0.8, color: PdfColors.black),
        pw.SizedBox(height: 5),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Inteligencia artificial y tecnología',
                style: pw.TextStyle(fontSize: 8.5, fontStyle: pw.FontStyle.italic)),
            pw.Text(_longDate(digest.date), style: const pw.TextStyle(fontSize: 8.5)),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Container(height: 0.8, color: PdfColors.black),
        pw.SizedBox(height: 16),
      ],
    );
  }

  static pw.Widget _editorial(String text) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 18),
      padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(width: 0.5, color: PdfColors.grey600),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('LO IMPORTANTE DE HOY',
              style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, letterSpacing: 1.6)),
          pw.SizedBox(height: 5),
          pw.Text(text,
              textAlign: pw.TextAlign.justify,
              style: pw.TextStyle(fontSize: 9.5, fontStyle: pw.FontStyle.italic, lineSpacing: 1.6)),
        ],
      ),
    );
  }

  static pw.Widget _leadStory(NewsItem item) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(item.category.label.toUpperCase(),
              style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, letterSpacing: 1.6)),
          pw.SizedBox(height: 6),
          pw.Text(item.title,
              style: pw.TextStyle(fontSize: 21, fontWeight: pw.FontWeight.bold, lineSpacing: 1.5)),
          pw.SizedBox(height: 8),
          pw.Text(item.summary,
              textAlign: pw.TextAlign.justify,
              style: const pw.TextStyle(fontSize: 10, lineSpacing: 2)),
          pw.SizedBox(height: 6),
          _sourceLine(item),
          pw.SizedBox(height: 12),
          pw.Container(height: 1.5, color: PdfColors.black),
        ],
      ),
    );
  }

  /// Reparte las notas en filas de dos columnas. `MultiPage` pagina por
  /// widget de nivel superior, así que cada fila es la unidad que salta de
  /// página — no se parte una nota por la mitad.
  static List<pw.Widget> _twoColumnRows(List<NewsItem> items) {
    final rows = <pw.Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      final left = items[i];
      final right = i + 1 < items.length ? items[i + 1] : null;
      rows.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 14),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _story(left)),
              pw.SizedBox(width: 18),
              // La columna vacía de una fila impar se conserva para que la
              // última nota no se estire a todo el ancho y rompa la retícula.
              pw.Expanded(child: right == null ? pw.SizedBox() : _story(right)),
            ],
          ),
        ),
      );
    }
    return rows;
  }

  static pw.Widget _story(NewsItem item) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(item.title,
            style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, lineSpacing: 1.4)),
        pw.SizedBox(height: 5),
        pw.Text(item.summary,
            textAlign: pw.TextAlign.justify,
            style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.8)),
        pw.SizedBox(height: 5),
        _sourceLine(item),
      ],
    );
  }

  static pw.Widget _sourceLine(NewsItem item) {
    final url = item.url.trim();
    final label = item.source.trim().isEmpty ? 'Fuente' : item.source.trim();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('— $label',
            style: pw.TextStyle(
                fontSize: 8, fontStyle: pw.FontStyle.italic, color: PdfColors.grey800)),
        if (url.isNotEmpty)
          pw.UrlLink(
            destination: url,
            child: pw.Text(url,
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
                style: const pw.TextStyle(fontSize: 6.5, color: PdfColors.blue800)),
          ),
      ],
    );
  }

  static pw.Widget _sectionHeader(String label) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(height: 0.8, color: PdfColors.black),
          pw.SizedBox(height: 4),
          pw.Text(label.toUpperCase(),
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, letterSpacing: 2)),
          pw.SizedBox(height: 4),
          pw.Container(height: 0.8, color: PdfColors.black),
        ],
      ),
    );
  }
}
