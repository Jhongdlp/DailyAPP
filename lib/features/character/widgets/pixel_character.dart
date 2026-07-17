import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/providers/rpg_provider.dart';
import '../../../core/models/cosmetic_catalog.dart';
import 'hero_sprites.dart';

/// Render animado del héroe pixel art.
///
/// Si [heroId] es null usa el héroe seleccionado en el provider RPG.
/// [locked] pinta el sprite como silueta (para héroes no desbloqueados).
class PixelCharacter extends ConsumerStatefulWidget {
  final int level;
  final int hp;
  final double size;
  final String? heroId;
  final bool animate;
  final bool locked;

  const PixelCharacter({
    super.key,
    this.level = 1,
    this.hp = 100,
    this.size = 200,
    this.heroId,
    this.animate = true,
    this.locked = false,
  });

  @override
  ConsumerState<PixelCharacter> createState() => _PixelCharacterState();
}

class _PixelCharacterState extends ConsumerState<PixelCharacter> with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.animate && !widget.locked) {
      _animationController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant PixelCharacter oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldAnimate = widget.animate && !widget.locked;
    if (shouldAnimate && !_animationController.isAnimating) {
      _animationController.repeat(reverse: true);
    } else if (!shouldAnimate && _animationController.isAnimating) {
      _animationController.stop();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String selectedId = widget.heroId ??
        ref.watch(rpgProvider.select((s) => s.selectedHero));
    final hero = heroById(selectedId);

    // Los cosméticos solo se muestran en el render principal (heroId null)
    List<CosmeticDef> cosmetics = const [];
    if (widget.heroId == null) {
      final equipped =
          ref.watch(rpgProvider.select((s) => s.equippedCosmetics));
      cosmetics = [
        for (final id in equipped.values)
          if (cosmeticById(id) != null) cosmeticById(id)!,
      ];
    }

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _HeroSpritePainter(
            hero: hero,
            level: widget.level,
            hp: widget.hp,
            locked: widget.locked,
            cosmetics: cosmetics,
            animationValue: _animationController.value,
            isDark: BentoTheme.isDark,
          ),
        );
      },
    );
  }
}

class _HeroSpritePainter extends CustomPainter {
  final HeroDef hero;
  final int level;
  final int hp;
  final bool locked;
  final List<CosmeticDef> cosmetics;
  final double animationValue;
  final bool isDark;

  _HeroSpritePainter({
    required this.hero,
    required this.level,
    required this.hp,
    required this.locked,
    this.cosmetics = const [],
    required this.animationValue,
    required this.isDark,
  });

  static const Color _hurtEyes = Color(0xFFD90429);

  @override
  void paint(Canvas canvas, Size size) {
    final double ps = size.width / kHeroGridWidth;
    final Paint paint = Paint()..style = PaintingStyle.fill;

    // Centrar verticalmente el grid 22x20 dentro del canvas cuadrado
    final double yOffset = (size.height - kHeroGridHeight * ps) / 2;

    final bool isHurt = hp <= 30;
    // Respiración: el sprite baja 1 px; la sombra queda fija en el suelo
    final int bob = (!locked && animationValue >= 0.5 && !isHurt) ? 1 : 0;
    // Parpadeo breve al final de cada ciclo
    final bool blink = !locked && animationValue > 0.88;

    // Sombra elíptica bajo los pies
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.35)
        : const Color(0xFF2E2440).withValues(alpha: 0.18);
    paint.color = shadowColor;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, yOffset + 19.2 * ps),
        width: 11 * ps,
        height: 2.6 * ps,
      ),
      paint,
    );

    final Color silhouette = isDark
        ? const Color(0xFF4A4060)
        : const Color(0xFFB9B2CC);

    // Cosméticos con sprite: se dibujan DETRÁS del héroe.
    // Halo y mascota flotan en contrafase para sentirse vivos.
    if (!locked) {
      for (final c in cosmetics) {
        if (c.sprite.isEmpty) continue;
        final int cBob = (c.slot == slotPet || c.slot == slotHalo) ? 1 - bob : bob;
        for (int y = 0; y < c.sprite.length; y++) {
          final line = c.sprite[y];
          for (int x = 0; x < line.length && x < kHeroGridWidth; x++) {
            final char = line[x];
            if (char == '.') continue;
            final color = c.palette[char];
            if (color == null) continue;
            paint.color = color;
            canvas.drawRect(
              Rect.fromLTWH(
                x * ps,
                yOffset + (y + cBob) * ps,
                ps + 0.35,
                ps + 0.35,
              ),
              paint,
            );
          }
        }
      }
    }

    for (int y = 0; y < hero.sprite.length; y++) {
      final line = hero.sprite[y];
      for (int x = 0; x < line.length && x < kHeroGridWidth; x++) {
        final char = line[x];
        if (char == '.') continue;

        Color? color;
        if (locked) {
          color = silhouette;
        } else if (char == 'e') {
          if (blink) {
            color = hero.palette['s'];
          } else {
            color = isHurt ? _hurtEyes : hero.palette['e'];
          }
        } else {
          color = hero.palette[char];
        }
        if (color == null) continue;

        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(
            x * ps,
            yOffset + (y + bob) * ps,
            ps + 0.35,
            ps + 0.35,
          ),
          paint,
        );
      }
    }

    // Auras equipadas: chispas animadas alrededor del héroe (en primer plano)
    if (!locked) {
      for (final c in cosmetics) {
        if (c.slot != slotAura || c.auraColor == null) continue;
        final bool phase = animationValue < 0.5;
        final sparks = phase
            ? const [Offset(2, 7), Offset(19, 10), Offset(4, 15), Offset(17, 2)]
            : const [Offset(1, 11), Offset(20, 5), Offset(3, 3), Offset(18, 15)];
        for (int i = 0; i < sparks.length; i++) {
          paint.color = i.isEven
              ? c.auraColor!
              : c.auraColor!.withValues(alpha: 0.55);
          canvas.drawRect(
            Rect.fromLTWH(sparks[i].dx * ps, yOffset + sparks[i].dy * ps,
                ps * 0.85, ps * 0.85),
            paint,
          );
        }
      }
    }

    // Chispas doradas para héroes de nivel alto
    if (!locked && level >= 10) {
      final bool phase = animationValue < 0.5;
      paint.color = const Color(0xFFFFE08A);
      final spark1 = phase ? const Offset(3, 5) : const Offset(19, 3);
      final spark2 = phase ? const Offset(18, 12) : const Offset(2, 10);
      for (final s in [spark1, spark2]) {
        canvas.drawRect(
          Rect.fromLTWH(s.dx * ps, yOffset + s.dy * ps, ps * 0.8, ps * 0.8),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeroSpritePainter oldDelegate) {
    return oldDelegate.hero.id != hero.id ||
        oldDelegate.level != level ||
        oldDelegate.hp != hp ||
        oldDelegate.locked != locked ||
        oldDelegate.cosmetics.length != cosmetics.length ||
        !_sameCosmetics(oldDelegate.cosmetics) ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.isDark != isDark;
  }

  bool _sameCosmetics(List<CosmeticDef> other) {
    for (int i = 0; i < cosmetics.length && i < other.length; i++) {
      if (cosmetics[i].id != other[i].id) return false;
    }
    return true;
  }
}
