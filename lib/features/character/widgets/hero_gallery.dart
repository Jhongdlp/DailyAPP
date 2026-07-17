import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/providers/rpg_provider.dart';
import 'hero_sprites.dart';
import 'pixel_character.dart';

/// Carrusel horizontal para elegir héroe. Los héroes se desbloquean por nivel.
class HeroGallery extends ConsumerWidget {
  const HeroGallery({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rpgStats = ref.watch(rpgProvider);

    return SizedBox(
      height: 172,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        itemCount: heroCatalog.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final hero = heroCatalog[index];
          final bool unlocked = rpgStats.level >= hero.unlockLevel;
          final bool selected = rpgStats.selectedHero == hero.id;

          return GestureDetector(
            onTap: () {
              if (unlocked) {
                ref.read(rpgProvider.notifier).selectHero(hero.id);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '${hero.name} se desbloquea en el nivel ${hero.unlockLevel}'),
                    backgroundColor: BentoTheme.darkCardAlt,
                  ),
                );
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 118,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected
                    ? hero.accent.withValues(alpha: 0.12)
                    : BentoTheme.darkCardAlt,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected
                      ? hero.accent
                      : BentoTheme.creamAlpha(0.10),
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PixelCharacter(
                          heroId: hero.id,
                          level: rpgStats.level,
                          hp: 100,
                          size: 80,
                          locked: !unlocked,
                          animate: selected,
                        ),
                        if (!unlocked)
                          Icon(Icons.lock_rounded,
                              size: 18,
                              color: BentoTheme.creamAlpha(0.55)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    unlocked ? hero.name : '???',
                    style: GoogleFonts.montserrat(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: BentoTheme.cream,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    unlocked ? hero.className : 'Nivel ${hero.unlockLevel}',
                    style: GoogleFonts.montserrat(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: unlocked
                          ? hero.accent
                          : BentoTheme.creamTertiary,
                      letterSpacing: 0.4,
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
