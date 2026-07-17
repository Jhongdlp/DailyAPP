import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/providers/rpg_provider.dart';
import '../../../core/models/achievement_catalog.dart';

/// Escudo pixel art 16x16 para los badges de logros
const List<String> _badgeSprite = [
  "..oooooooooooo..",
  ".ommxmmmmmmmmmo.",
  ".omxmmmmmmmmmmo.",
  ".ommmmmmmmmmmmo.",
  ".ommmmmmmmmmmmo.",
  ".oMmmmmmmmmmmMo.",
  ".oMmmmmmmmmmmMo.",
  ".oMmmmmmmmmmmMo.",
  "..oMmmmmmmmmMo..",
  "..oMmmmmmmmmMo..",
  "...oMmmmmmmMo...",
  "....oMmmmmMo....",
  ".....oMmmMo.....",
  "......oMMo......",
  ".......oo.......",
  "................",
];

/// Medalla pixel art con el emoji del logro encima.
class PixelBadge extends StatelessWidget {
  final AchievementDef def;
  final double size;
  final bool locked;

  const PixelBadge({
    super.key,
    required this.def,
    this.size = 48,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _BadgePainter(tier: def.tier, locked: locked),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: size * 0.12),
            child: Opacity(
              opacity: locked ? 0.35 : 1.0,
              child: Text(
                locked ? '🔒' : def.emoji,
                style: TextStyle(fontSize: size * 0.34),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgePainter extends CustomPainter {
  final BadgeTier tier;
  final bool locked;

  _BadgePainter({required this.tier, required this.locked});

  @override
  void paint(Canvas canvas, Size size) {
    final ps = size.width / 16;
    final paint = Paint()..style = PaintingStyle.fill;

    final BadgeTierPalette pal = locked
        ? const BadgeTierPalette(
            Color(0xFF5A5468), Color(0xFF403C4E), Color(0xFF6E687E))
        : badgeTierPalettes[tier]!;

    for (int y = 0; y < _badgeSprite.length; y++) {
      final line = _badgeSprite[y];
      for (int x = 0; x < line.length; x++) {
        final char = line[x];
        if (char == '.') continue;
        switch (char) {
          case 'o':
            paint.color = const Color(0xFF2E2440);
            break;
          case 'm':
            paint.color = pal.main;
            break;
          case 'M':
            paint.color = pal.shadow;
            break;
          case 'x':
            paint.color = pal.highlight;
            break;
          default:
            continue;
        }
        canvas.drawRect(
          Rect.fromLTWH(x * ps, y * ps, ps + 0.3, ps + 0.3),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BadgePainter oldDelegate) =>
      oldDelegate.tier != tier || oldDelegate.locked != locked;
}

/// Fila de mini-badges equipados (para la carta del héroe)
class EquippedBadgesRow extends ConsumerWidget {
  const EquippedBadgesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges =
        ref.watch(rpgProvider.select((s) => s.equippedBadges));
    if (badges.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          for (final id in badges)
            if (achievementById(id) != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: PixelBadge(def: achievementById(id)!, size: 30),
              ),
        ],
      ),
    );
  }
}

/// Grid de logros: badges desbloqueados a color, bloqueados en gris con
/// progreso. Tocar uno desbloqueado lo pone/quita de la carta (máx 3).
class AchievementsPanel extends ConsumerWidget {
  const AchievementsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(rpgProvider);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: achievementCatalog.length,
      itemBuilder: (context, index) {
        final def = achievementCatalog[index];
        final unlocked = stats.unlockedAchievements.contains(def.id);
        final equipped = stats.equippedBadges.contains(def.id);
        final progress = achievementProgress(stats, def);

        return GestureDetector(
          onTap: () {
            if (unlocked) {
              ref.read(rpgProvider.notifier).toggleBadge(def.id);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      '${def.emoji} ${def.title}: ${def.description} ($progress/${def.target})'),
                  backgroundColor: BentoTheme.darkCardAlt,
                ),
              );
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: equipped
                  ? BentoTheme.accentLime.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: equipped
                    ? BentoTheme.accentLime
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                PixelBadge(def: def, size: 46, locked: !unlocked),
                const SizedBox(height: 4),
                Text(
                  def.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color:
                        unlocked ? BentoTheme.cream : BentoTheme.creamTertiary,
                  ),
                ),
                Text(
                  unlocked
                      ? badgeTierLabel(def.tier)
                      : '$progress/${def.target}',
                  style: GoogleFonts.montserrat(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: unlocked
                        ? badgeTierPalettes[def.tier]!.main
                        : BentoTheme.creamTertiary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
