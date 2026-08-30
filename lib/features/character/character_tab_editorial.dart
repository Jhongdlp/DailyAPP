import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/rpg_model.dart';
import '../../core/providers/rpg_provider.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/widgets/editorial_kit.dart';
import 'widgets/achievements_panel.dart';
import 'widgets/cosmetic_shop.dart';
import 'widgets/hero_gallery.dart';
import 'widgets/pixel_character.dart';

/// Pestaña de Personaje (RPG / Gamificación) en Estilo Editorial:
/// - Tarjeta Hero del héroe con animación pixel art, nivel, título y barra de XP
/// - Contador de monedas de oro en papel
/// - Selector de secciones: Atributos, Héroes, Bazar, Logros, Recompensas
/// - Creador de recompensas personalizadas con inputs estilizados
class CharacterTabEditorial extends ConsumerStatefulWidget {
  final Function(int)? onNavigateToTab;
  final bool animate;

  const CharacterTabEditorial({
    super.key,
    this.onNavigateToTab,
    this.animate = true,
  });

  @override
  ConsumerState<CharacterTabEditorial> createState() =>
      _CharacterTabEditorialState();
}

class _CharacterTabEditorialState
    extends ConsumerState<CharacterTabEditorial> {
  int _activeSection = 0; // 0: Atributos, 1: Héroes, 2: Bazar, 3: Logros, 4: Recompensas

  String _getCharacterTitle(int level) {
    if (level >= 15) return 'Paladín Dorado';
    if (level >= 10) return 'Caballero de Mithril';
    if (level >= 5) return 'Guerrero de Acero';
    return 'Recluta Novato';
  }

  void _openCreateRewardSheet() {
    final titleCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    var selectedEmoji = '🎮';

    showEditorialSheet(
      context: context,
      title: 'Crear Recompensa',
      builder: (ctx, setSheetState) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                'ELIGE UN ICONO',
                style: EditorialTheme.label(10.5, color: EditorialTheme.grayText),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: ['🎮', '📺', '🍰', '🛍️', '🍺', '😴'].map((emoji) {
                  final isSelected = selectedEmoji == emoji;
                  return EditorialPressable(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setSheetState(() => selectedEmoji = emoji);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? EditorialTheme.grayStrong
                            : EditorialTheme.gray,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? EditorialTheme.ink
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              Text(
                'DESCRIPCIÓN',
                style: EditorialTheme.label(10.5, color: EditorialTheme.grayText),
              ),
              const SizedBox(height: 6),
              EditorialField(
                controller: titleCtrl,
                hint: 'Ej: Jugar 1 hora, ver serie...',
                autofocus: true,
              ),
              const SizedBox(height: 16),
              Text(
                'COSTO EN ORO',
                style: EditorialTheme.label(10.5, color: EditorialTheme.grayText),
              ),
              const SizedBox(height: 6),
              EditorialField(
                controller: costCtrl,
                hint: 'Ej: 50, 100',
                keyboardType: TextInputType.number,
                prefix: const Text('💰', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 24),
              EditorialButton(
                label: 'Guardar Recompensa',
                icon: Icons.check_rounded,
                onTap: () {
                  final title = titleCtrl.text.trim();
                  final cost = int.tryParse(costCtrl.text.trim()) ?? 0;
                  if (title.isNotEmpty && cost > 0) {
                    HapticFeedback.mediumImpact();
                    ref.read(rpgProvider.notifier).addCustomReward(
                          title,
                          cost,
                          selectedEmoji,
                        );
                    Navigator.pop(ctx);
                  }
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final rpg = ref.watch(rpgProvider);
    final level = rpg.level;
    final title = _getCharacterTitle(level);

    return Scaffold(
      backgroundColor: EditorialTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cabecera Editorial
              Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Personaje',
                        style: EditorialTheme.caps(
                          28,
                          color: EditorialTheme.paper,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tu alter ego y progreso RPG diario',
                        style: EditorialTheme.text(
                          12,
                          color: EditorialTheme.muted,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: EditorialTheme.paper,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('💰', style: TextStyle(fontSize: 15)),
                      const SizedBox(width: 5),
                      Text(
                        '${rpg.gold}',
                        style: EditorialTheme.text(
                          13,
                          weight: FontWeight.w800,
                          color: EditorialTheme.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Hero Character Card
            _HeroCharacterCardEditorial(
              rpg: rpg,
              title: title,
              animate: widget.animate,
            ),
            const SizedBox(height: 20),

            // Selector de Secciones
            _SectionSelectorEditorial(
              activeIndex: _activeSection,
              onSelect: (index) {
                HapticFeedback.selectionClick();
                setState(() => _activeSection = index);
              },
            ),
            const SizedBox(height: 20),

            // Contenido dinámico según la sección elegida
            if (_activeSection == 0) ...[
              _StatsSectionEditorial(rpg: rpg),
            ] else if (_activeSection == 1) ...[
              const EditorialSectionLabel('CATÁLOGO DE HÉROES'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: EditorialTheme.paper,
                  borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
                ),
                child: const HeroGallery(),
              ),
            ] else if (_activeSection == 2) ...[
              const EditorialSectionLabel('BAZAR DE ACCESORIOS'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: EditorialTheme.paper,
                  borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
                ),
                child: const CosmeticShop(),
              ),
            ] else if (_activeSection == 3) ...[
              const EditorialSectionLabel('MEDALLAS Y LOGROS'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: EditorialTheme.paper,
                  borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
                ),
                child: const AchievementsPanel(),
              ),
            ] else if (_activeSection == 4) ...[
              EditorialSectionLabel(
                'RECOMPENSAS PERSONALIZADAS',
                trailing: EditorialCircleButton(
                  icon: Icons.add_rounded,
                  tooltip: 'Nueva recompensa',
                  onTap: _openCreateRewardSheet,
                  size: 34,
                ),
              ),
              const SizedBox(height: 10),
              _RewardsSectionEditorial(
                rpg: rpg,
                onAddTap: _openCreateRewardSheet,
              ),
            ],
          ],
        ),
      ),
    ),
  );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO CARD DEL PERSONAJE
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCharacterCardEditorial extends StatelessWidget {
  final RpgStats rpg;
  final String title;
  final bool animate;

  const _HeroCharacterCardEditorial({
    required this.rpg,
    required this.title,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final level = rpg.level;
    final xp = rpg.xp;
    final nextLevelXp = level * 100;
    final progress = nextLevelXp > 0 ? (xp / nextLevelXp).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: EditorialTheme.gray,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  'NIVEL $level',
                  style: EditorialTheme.label(
                    11,
                    color: EditorialTheme.ink,
                  ),
                ),
              ),
              Text(
                title.toUpperCase(),
                style: EditorialTheme.caps(
                  13,
                  color: EditorialTheme.accent(BentoTheme.accentOrange, onDark: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              height: 150,
              child: PixelCharacter(
                level: level,
                size: 150,
                animate: animate,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Barra de Experiencia
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Experiencia',
                style: EditorialTheme.text(12, weight: FontWeight.w600, color: EditorialTheme.ink),
              ),
              Text(
                '$xp / $nextLevelXp XP',
                style: EditorialTheme.text(12, weight: FontWeight.w700, color: EditorialTheme.grayText),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: Container(
              height: 8,
              color: EditorialTheme.grayStrong,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress,
                child: Container(
                  color: EditorialTheme.accent(BentoTheme.accentLime, onDark: false),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SELECTOR DE SECCIÓN (CHIPS)
// ─────────────────────────────────────────────────────────────────────────────

class _SectionSelectorEditorial extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onSelect;

  const _SectionSelectorEditorial({
    required this.activeIndex,
    required this.onSelect,
  });

  static const _labels = ['Atributos', 'Héroes', 'Bazar', 'Logros', 'Premios'];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            EditorialPressable(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: activeIndex == i
                      ? EditorialTheme.paper
                      : EditorialTheme.surface,
                  borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
                  border: Border.all(
                    color: activeIndex == i
                        ? EditorialTheme.paper
                        : EditorialTheme.surfaceHigh,
                    width: 1,
                  ),
                ),
                child: Text(
                  _labels[i],
                  style: EditorialTheme.text(
                    12,
                    weight: activeIndex == i ? FontWeight.w700 : FontWeight.w500,
                    color: activeIndex == i
                        ? EditorialTheme.ink
                        : EditorialTheme.muted,
                  ),
                ),
              ),
            ),
            if (i < _labels.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECCIÓN ATRIBUTOS
// ─────────────────────────────────────────────────────────────────────────────

class _StatsSectionEditorial extends StatelessWidget {
  final RpgStats rpg;
  const _StatsSectionEditorial({required this.rpg});

  @override
  Widget build(BuildContext context) {
    final counters = rpg.counters;
    final habits = counters['habits_completed'] ?? 0;
    final focus = (counters['focus_minutes'] ?? 0) ~/ 15;
    final reading = (counters['reading_minutes'] ?? 0) ~/ 20;
    final tasks = counters['tasks_completed'] ?? 0;

    final str = 10 + habits;
    final intel = 10 + focus + reading;
    final vit = 10 + (rpg.level * 2);
    final agi = 10 + tasks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EditorialSectionLabel('ATRIBUTOS DEL HÉROE'),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.4,
          children: [
            _AttributeTileEditorial(
              title: 'Fuerza',
              subtitle: 'Hábitos completados',
              value: '$str',
              icon: Icons.fitness_center_rounded,
              color: EditorialTheme.accent(BentoTheme.accentOrange, onDark: false),
            ),
            _AttributeTileEditorial(
              title: 'Sabiduría',
              subtitle: 'Lectura y foco',
              value: '$intel',
              icon: Icons.auto_stories_rounded,
              color: EditorialTheme.accent(BentoTheme.accentPurple, onDark: false),
            ),
            _AttributeTileEditorial(
              title: 'Vitalidad',
              subtitle: 'Nivel y descanso',
              value: '$vit',
              icon: Icons.favorite_rounded,
              color: const Color(0xFFEF4444),
            ),
            _AttributeTileEditorial(
              title: 'Agilidad',
              subtitle: 'Tareas terminadas',
              value: '$agi',
              icon: Icons.bolt_rounded,
              color: EditorialTheme.accent(BentoTheme.accentLime, onDark: false),
            ),
          ],
        ),
      ],
    );
  }
}

class _AttributeTileEditorial extends StatelessWidget {
  final String title;
  final String subtitle;
  final String value;
  final IconData icon;
  final Color color;

  const _AttributeTileEditorial({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: EditorialTheme.text(13, weight: FontWeight.w700, color: EditorialTheme.ink),
              ),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: EditorialTheme.caps(22, color: EditorialTheme.ink),
              ),
              const SizedBox(width: 4),
              Text(
                'PTS',
                style: EditorialTheme.label(9.5, color: EditorialTheme.grayText),
              ),
            ],
          ),
          Text(
            subtitle,
            style: EditorialTheme.text(10.5, color: EditorialTheme.grayText),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECCIÓN RECOMPENSAS PERSONALIZADAS
// ─────────────────────────────────────────────────────────────────────────────

class _RewardsSectionEditorial extends ConsumerWidget {
  final RpgStats rpg;
  final VoidCallback onAddTap;

  const _RewardsSectionEditorial({
    required this.rpg,
    required this.onAddTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customRewards = rpg.customRewards;

    if (customRewards.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: EditorialTheme.paper,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
        ),
        child: Column(
          children: [
            const Text('🎁', style: TextStyle(fontSize: 34)),
            const SizedBox(height: 10),
            Text(
              'Sin recompensas aún',
              style: EditorialTheme.caps(16, color: EditorialTheme.ink),
            ),
            const SizedBox(height: 6),
            Text(
              'Crea premios reales que puedas canjear con el oro que ganas completando tus hábitos.',
              textAlign: TextAlign.center,
              style: EditorialTheme.text(12.5, color: EditorialTheme.grayText),
            ),
            const SizedBox(height: 16),
            EditorialButton(
              label: 'Crear primera recompensa',
              icon: Icons.add_rounded,
              onTap: onAddTap,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < customRewards.length; i++) ...[
          _RewardCardEditorial(
            reward: customRewards[i],
            canAfford: rpg.gold >= customRewards[i].cost,
            goldMissing: customRewards[i].cost - rpg.gold,
          ),
          if (i < customRewards.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _RewardCardEditorial extends ConsumerWidget {
  const _RewardCardEditorial({
    required this.reward,
    required this.canAfford,
    required this.goldMissing,
  });

  final RpgReward reward;
  final bool canAfford;
  final int goldMissing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
      ),
      child: Row(
        children: [
          Text(reward.icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reward.title,
                  style: EditorialTheme.text(
                    14,
                    weight: FontWeight.w700,
                    color: EditorialTheme.ink,
                  ),
                ),
                Text(
                  'Costo: ${reward.cost} 💰',
                  style: EditorialTheme.text(
                    12,
                    weight: FontWeight.w600,
                    color: EditorialTheme.grayText,
                  ),
                ),
              ],
            ),
          ),
          EditorialPressable(
            onTap: () {
              if (canAfford) {
                HapticFeedback.mediumImpact();
                final success = ref.read(rpgProvider.notifier).purchaseReward(reward.id);
                if (success) {
                  showEditorialSnack(context, '¡Disfruta tu recompensa: ${reward.title}!');
                }
              } else {
                showEditorialSnack(
                  context,
                  'Te falta oro ($goldMissing 💰 más)',
                  tone: const Color(0xFFEF4444),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: canAfford ? EditorialTheme.ink : EditorialTheme.gray,
                borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
              ),
              child: Text(
                'Canjear',
                style: EditorialTheme.text(
                  12.5,
                  weight: FontWeight.w600,
                  color: canAfford ? EditorialTheme.paper : EditorialTheme.grayText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
