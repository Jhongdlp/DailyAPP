import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/news_model.dart';
import '../../../core/theme/bento_theme.dart';

/// Acento por categoría. Es un getter y no un mapa `const` porque los colores
/// del tema cambian en vivo con la paleta y el modo claro/oscuro.
Color newsAccent(NewsCategory category) => switch (category) {
      NewsCategory.ia => BentoTheme.accentBrain,
      NewsCategory.dev => BentoTheme.accentChat,
      NewsCategory.startups => BentoTheme.accentFinance,
      NewsCategory.papers => BentoTheme.accentPurple,
    };

class NewsCard extends StatelessWidget {
  final NewsItem item;
  final VoidCallback? onTap;

  const NewsCard({super.key, required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = newsAccent(item.category);

    return NeuCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // NeuPressed en modo `lite`: en una lista larga cada hueco con
              // blur cuesta dos pasadas offscreen.
              NeuPressed(
                lite: true,
                borderRadius: 8,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  item.category.label.toUpperCase(),
                  style: GoogleFonts.montserrat(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: accent,
                  ),
                ),
              ),
              const Spacer(),
              _RelevanceDots(relevance: item.relevance, accent: accent),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            style: GoogleFonts.montserrat(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: BentoTheme.cream,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.summary,
            style: GoogleFonts.montserrat(
              fontSize: 12.5,
              height: 1.5,
              color: BentoTheme.creamAlpha(0.72),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.public, size: 13, color: BentoTheme.creamAlpha(0.45)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.montserrat(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: BentoTheme.creamAlpha(0.55),
                  ),
                ),
              ),
              if (item.url.isNotEmpty)
                Icon(Icons.arrow_outward,
                    size: 14, color: BentoTheme.creamAlpha(0.45)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Relevancia 0-10 comprimida a cinco puntos: un número crudo invita a
/// comparar noticias entre sí, que no es para lo que sirve la métrica.
class _RelevanceDots extends StatelessWidget {
  final int relevance;
  final Color accent;

  const _RelevanceDots({required this.relevance, required this.accent});

  @override
  Widget build(BuildContext context) {
    final filled = (relevance / 2).ceil().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? accent : BentoTheme.creamAlpha(0.15),
              ),
            ),
          ),
      ],
    );
  }
}
