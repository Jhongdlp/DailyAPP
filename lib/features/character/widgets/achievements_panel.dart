import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';
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
              child: Twemoji(
                emoji: locked ? '🔒' : def.emoji,
                height: size * 0.34,
                width: size * 0.34,
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

/// Resumen "X/Y desbloqueados" con barra de progreso general, ancla visual
/// del panel de logros ahora que hay ~30 entradas repartidas en categorías.
class AchievementsSummary extends ConsumerWidget {
  const AchievementsSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlockedCount =
        ref.watch(rpgProvider.select((s) => s.unlockedAchievements.length));
    final total = achievementCatalog.length;
    final pct = total == 0 ? 0.0 : (unlockedCount / total).clamp(0.0, 1.0);

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: BentoTheme.creamAlpha(0.1),
              valueColor: AlwaysStoppedAnimation(BentoTheme.accentLime),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$unlockedCount/$total',
          style: GoogleFonts.montserrat(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: BentoTheme.creamSecondary,
          ),
        ),
      ],
    );
  }
}

/// Panel de logros agrupado por categoría. Cada tarjeta abre una hoja de
/// detalle con progreso y recompensa en vez de un SnackBar, para que
/// desbloqueados y bloqueados compartan la misma superficie de información.
class AchievementsPanel extends ConsumerWidget {
  const AchievementsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(rpgProvider);

    final byCategory = <AchievementCategory, List<AchievementDef>>{};
    for (final def in achievementCatalog) {
      byCategory.putIfAbsent(def.category, () => []).add(def);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final category in AchievementCategory.values)
          if (byCategory[category] case final defs? when defs.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Text(
                achievementCategoryLabel(category).toUpperCase(),
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: BentoTheme.creamTertiary,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 10,
                mainAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              itemCount: defs.length,
              itemBuilder: (context, index) {
                final def = defs[index];
                final unlocked = stats.unlockedAchievements.contains(def.id);
                final equipped = stats.equippedBadges.contains(def.id);
                final progress = achievementProgress(stats, def);

                return GestureDetector(
                  onTap: () => _showAchievementDetail(context, def),
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
                            color: unlocked
                                ? BentoTheme.cream
                                : BentoTheme.creamTertiary,
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
            ),
            const SizedBox(height: 18),
          ],
      ],
    );
  }
}

void _showAchievementDetail(BuildContext context, AchievementDef def) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _AchievementDetailSheet(def: def),
  );
}

class _AchievementDetailSheet extends ConsumerWidget {
  final AchievementDef def;

  const _AchievementDetailSheet({required this.def});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(rpgProvider);
    final unlocked = stats.unlockedAchievements.contains(def.id);
    final equipped = stats.equippedBadges.contains(def.id);
    final progress = achievementProgress(stats, def).clamp(0, def.target);
    final pct = def.target == 0 ? 1.0 : (progress / def.target).clamp(0.0, 1.0);
    final palette = badgeTierPalettes[def.tier]!;
    final canEquipMore = stats.equippedBadges.length < 3 || equipped;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: NeuCard(
        radius: const BorderRadius.vertical(top: Radius.circular(28)),
        elevation: 22,
        convex: false,
        padding: EdgeInsets.fromLTRB(24, 12, 24, 20 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: NeuPressed(
                borderRadius: 3,
                distance: 2,
                blur: 3,
                child: const SizedBox(width: 40, height: 5),
              ),
            ),
            const SizedBox(height: 18),
            PixelBadge(def: def, size: 84, locked: !unlocked),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: (unlocked ? palette.main : BentoTheme.creamTertiary).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                achievementCategoryLabel(def.category).toUpperCase(),
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: unlocked ? palette.main : BentoTheme.creamTertiary,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              def.title,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: BentoTheme.cream,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              def.description,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: BentoTheme.creamSecondary,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 8,
                      backgroundColor: BentoTheme.creamAlpha(0.1),
                      valueColor: AlwaysStoppedAnimation(unlocked ? palette.main : BentoTheme.accentLime),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$progress/${def.target}',
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: BentoTheme.creamSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RewardChip(emoji: '⭐', label: '+${def.xpReward} XP', color: BentoTheme.accentLime),
                const SizedBox(width: 10),
                _RewardChip(emoji: '💰', label: '+${def.goldReward}', color: palette.main),
                const SizedBox(width: 10),
                _RewardChip(emoji: '', label: badgeTierLabel(def.tier), color: palette.main),
              ],
            ),
            const SizedBox(height: 20),
            if (unlocked)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canEquipMore
                      ? () {
                          ref.read(rpgProvider.notifier).toggleBadge(def.id);
                        }
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ya tienes 3 logros equipados en la carta.')),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: equipped ? BentoTheme.darkCardAlt : BentoTheme.accentLime,
                    foregroundColor: equipped ? BentoTheme.cream : const Color(0xFF0C0C0D),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: equipped ? BorderSide(color: BentoTheme.creamAlpha(0.2)) : BorderSide.none,
                    ),
                  ),
                  child: Text(
                    equipped ? 'Quitar de la carta' : 'Lucir en la carta',
                    style: GoogleFonts.montserrat(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
              )
            else
              Text(
                'Sigue avanzando para desbloquearlo',
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BentoTheme.creamTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RewardChip extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;

  const _RewardChip({required this.emoji, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji.isNotEmpty) ...[
            Twemoji(emoji: emoji, height: 12, width: 12),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}
