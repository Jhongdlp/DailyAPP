import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/providers/rpg_provider.dart';
import '../../../core/models/cosmetic_catalog.dart';
import '../../../core/models/achievement_catalog.dart';
import '../../../core/widgets/rpg_celebration.dart';

/// Bazar: cosméticos comprables con oro que se equipan sobre el héroe.
class CosmeticShop extends ConsumerWidget {
  const CosmeticShop({super.key});

  void _onTapItem(BuildContext context, WidgetRef ref, CosmeticDef item) {
    final stats = ref.read(rpgProvider);
    final notifier = ref.read(rpgProvider.notifier);

    if (stats.purchasedCosmetics.contains(item.id)) {
      notifier.toggleCosmetic(item.id, item.slot);
      return;
    }

    if (stats.gold < item.price) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Te faltan ${item.price - stats.gold} 💰 para ${item.name}.'),
          backgroundColor: BentoTheme.errorRed,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BentoTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          item.name,
          style: GoogleFonts.montserrat(
            fontWeight: FontWeight.bold,
            color: BentoTheme.cream,
          ),
        ),
        content: Text(
          '${item.description}\n\n¿Comprar por ${item.price} 💰?',
          style: TextStyle(color: BentoTheme.creamSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar',
                style: TextStyle(color: BentoTheme.creamSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: BentoTheme.accentLime,
              foregroundColor: const Color(0xFF0C0C0D),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              final unlocked =
                  notifier.buyCosmetic(item.id, item.price, item.slot);
              if (unlocked == null) return;
              RpgCelebration.show(context, xp: 0, gold: -item.price, levelUp: false);
              _showUnlockedToasts(context, unlocked);
            },
            child: const Text('Comprar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(rpgProvider);

    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        itemCount: cosmeticCatalog.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = cosmeticCatalog[index];
          final owned = stats.purchasedCosmetics.contains(item.id);
          final equipped = stats.equippedCosmetics[item.slot] == item.id;
          final affordable = stats.gold >= item.price;

          return GestureDetector(
            onTap: () => _onTapItem(context, ref, item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 124,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: equipped
                    ? BentoTheme.accentLime.withValues(alpha: 0.10)
                    : BentoTheme.darkCardAlt,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: equipped
                      ? BentoTheme.accentLime
                      : BentoTheme.creamAlpha(0.10),
                  width: equipped ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  // Chip de slot
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      cosmeticSlotLabel(item.slot).toUpperCase(),
                      style: GoogleFonts.montserrat(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: BentoTheme.creamTertiary,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: CustomPaint(
                        size: const Size(64, 64),
                        painter: _CosmeticPreviewPainter(item: item),
                      ),
                    ),
                  ),
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.montserrat(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: BentoTheme.cream,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: owned
                          ? BentoTheme.accentLime.withValues(alpha: 0.15)
                          : BentoTheme.creamAlpha(0.08),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      owned
                          ? (equipped ? 'Equipado ✓' : 'Equipar')
                          : '💰 ${item.price}',
                      style: GoogleFonts.montserrat(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: owned
                            ? BentoTheme.accentLime
                            : affordable
                                ? BentoTheme.cream
                                : BentoTheme.creamTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Muestra snackbars por logros recién desbloqueados
void _showUnlockedToasts(BuildContext context, List<AchievementDef> unlocked) {
  for (final a in unlocked) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${a.emoji} ¡Logro desbloqueado: ${a.title}!'),
        backgroundColor: BentoTheme.successGreen,
      ),
    );
  }
}

/// Dibuja el sprite del cosmético recortado y centrado (auras: patrón de chispas)
class _CosmeticPreviewPainter extends CustomPainter {
  final CosmeticDef item;

  _CosmeticPreviewPainter({required this.item});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    if (item.slot == slotAura && item.auraColor != null) {
      // patrón decorativo de chispas
      final ps = size.width / 8;
      const cells = [
        Offset(1, 2), Offset(5, 1), Offset(3, 4), Offset(6, 5), Offset(2, 6),
      ];
      for (int i = 0; i < cells.length; i++) {
        paint.color = i.isEven
            ? item.auraColor!
            : item.auraColor!.withValues(alpha: 0.5);
        canvas.drawRect(
          Rect.fromLTWH(cells[i].dx * ps, cells[i].dy * ps, ps, ps),
          paint,
        );
      }
      return;
    }

    // bounding box de píxeles no vacíos
    int minX = 999, maxX = -1, minY = 999, maxY = -1;
    for (int y = 0; y < item.sprite.length; y++) {
      final line = item.sprite[y];
      for (int x = 0; x < line.length; x++) {
        if (line[x] == '.') continue;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    if (maxX < 0) return;

    final w = maxX - minX + 1;
    final h = maxY - minY + 1;
    final scale = size.width / (w > h ? w : h);
    final ox = (size.width - w * scale) / 2;
    final oy = (size.height - h * scale) / 2;

    for (int y = minY; y <= maxY; y++) {
      final line = item.sprite[y];
      for (int x = minX; x <= maxX && x < line.length; x++) {
        final char = line[x];
        if (char == '.') continue;
        final color = item.palette[char];
        if (color == null) continue;
        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(
            ox + (x - minX) * scale,
            oy + (y - minY) * scale,
            scale + 0.3,
            scale + 0.3,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CosmeticPreviewPainter oldDelegate) =>
      oldDelegate.item.id != item.id;
}
