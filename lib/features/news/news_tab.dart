import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/news_model.dart';
import '../../core/providers/news_provider.dart';
import '../../core/theme/bento_theme.dart';
import 'news_pdf_service.dart';
import 'widgets/news_card.dart';

class NewsTab extends ConsumerStatefulWidget {
  const NewsTab({super.key});

  @override
  ConsumerState<NewsTab> createState() => _NewsTabState();
}

class _NewsTabState extends ConsumerState<NewsTab> {
  /// `null` = todas las categorías.
  NewsCategory? _filter;
  bool _exporting = false;

  static const _months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  String _headerDate(DateTime date) {
    final today = DateTime.now();
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final label = '${date.day} de ${_months[date.month - 1]}';
    return isToday ? 'Hoy · $label' : label;
  }

  Future<void> _openSource(NewsItem item) async {
    if (item.url.isEmpty) return;
    final uri = Uri.tryParse(item.url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _toast('No se pudo abrir el enlace');
    }
  }

  Future<void> _exportPdf(NewsDigest digest) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final path = await NewsPdfService.export(digest);
      await OpenFilex.open(path);
    } catch (e) {
      _toast('No se pudo generar el PDF: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newsProvider);
    final digest = state.digest;

    return BentoBackground(
      backgroundColor: BentoTheme.darkBg,
      child: Column(
        children: [
          _header(digest),
          if (digest != null && digest.activeCategories.length > 1)
            _filterBar(digest),
          Expanded(child: _body(state, digest)),
        ],
      ),
    );
  }

  Widget _body(NewsState state, NewsDigest? digest) {
    if (digest == null) {
      if (state.isLoading) {
        return Center(
          child: CircularProgressIndicator(color: BentoTheme.accentBrain),
        );
      }
      return _empty(state.error ?? 'Todavía no hay ningún digest publicado.');
    }

    final items =
        _filter == null ? digest.items : digest.byCategory(_filter!);

    if (items.isEmpty) {
      return _empty('Nada en "${_filter!.label}" hoy.');
    }

    return RefreshIndicator(
      color: BentoTheme.accentBrain,
      backgroundColor: BentoTheme.neuSurface,
      onRefresh: () => ref.read(newsProvider.notifier).refresh(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        // El editorial es el primer elemento de la lista, no una cabecera
        // fija: debe desplazarse con las noticias.
        itemCount: items.length + (_showEditorial(digest) ? 1 : 0),
        separatorBuilder: (context, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (_showEditorial(digest)) {
            if (index == 0) return _editorial(digest.editorial);
            return NewsCard(
              item: items[index - 1],
              onTap: () => _openSource(items[index - 1]),
            );
          }
          return NewsCard(
            item: items[index],
            onTap: () => _openSource(items[index]),
          );
        },
      ),
    );
  }

  /// El editorial resume el día completo, así que se oculta al filtrar por
  /// categoría: allí describiría noticias que no están en pantalla.
  bool _showEditorial(NewsDigest digest) =>
      _filter == null && digest.editorial.trim().isNotEmpty;

  Widget _header(NewsDigest? digest) {
    return SizedBox(
      height: 92,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Noticias',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w800,
                    fontSize: 38,
                    height: 0.92,
                    letterSpacing: -1.2,
                    color: BentoTheme.cream,
                  ),
                ),
                if (digest != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _headerDate(digest.date),
                    style: GoogleFonts.montserrat(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: BentoTheme.creamAlpha(0.5),
                    ),
                  ),
                ],
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  _iconButton(
                    icon: Icons.refresh,
                    tooltip: 'Buscar digest nuevo',
                    onPressed: () =>
                        ref.read(newsProvider.notifier).refresh(),
                  ),
                  const SizedBox(width: 8),
                  _iconButton(
                    icon: Icons.picture_as_pdf_outlined,
                    tooltip: 'Exportar como periódico',
                    busy: _exporting,
                    onPressed: digest == null || _exporting
                        ? null
                        : () => _exportPdf(digest),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterBar(NewsDigest digest) {
    final categories = digest.activeCategories;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _chip('Todo', null, BentoTheme.cream, digest.items.length),
          for (final category in categories) ...[
            const SizedBox(width: 8),
            _chip(category.label, category, newsAccent(category),
                digest.byCategory(category).length),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, NewsCategory? category, Color accent, int count) {
    final selected = _filter == category;
    return Center(
      child: GestureDetector(
        onTap: () => setState(() => _filter = category),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.16)
                : BentoTheme.creamAlpha(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent.withValues(alpha: 0.55)
                  : BentoTheme.creamAlpha(0.12),
            ),
          ),
          child: Text(
            '$label · $count',
            style: GoogleFonts.montserrat(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: selected ? accent : BentoTheme.creamAlpha(0.6),
            ),
          ),
        ),
      ),
    );
  }

  Widget _editorial(String text) {
    return NeuPressed(
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome,
                  size: 13, color: BentoTheme.accentBrain),
              const SizedBox(width: 6),
              Text(
                'LO IMPORTANTE DE HOY',
                style: GoogleFonts.montserrat(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: BentoTheme.accentBrain,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: GoogleFonts.montserrat(
              fontSize: 13,
              height: 1.55,
              color: BentoTheme.creamAlpha(0.78),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.newspaper_outlined,
                size: 44, color: BentoTheme.creamAlpha(0.25)),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                height: 1.5,
                color: BentoTheme.creamAlpha(0.5),
              ),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: () => ref.read(newsProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reintentar'),
              style: TextButton.styleFrom(
                foregroundColor: BentoTheme.accentBrain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconButton({
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
}
