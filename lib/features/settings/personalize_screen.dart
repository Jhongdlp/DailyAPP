import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/app_destination.dart';
import '../../core/providers/appearance_provider.dart';
import '../../core/providers/dock_provider.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/theme/design_language.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/theme/oklch.dart';
import '../../core/widgets/editorial_kit.dart';

/// Pantalla de personalización de SistemDaily:
/// - Modo visual (Editorial vs Relieve / Neumorfismo)
/// - Claridad de tema (Claro / Oscuro / Sistema)
/// - Paletas de color calibradas y creador personalizado OkLCh
/// - Tinte de superficie / material
/// - Configuración y asignación de slots del Dock
class PersonalizeScreen extends ConsumerWidget {
  const PersonalizeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    BentoTheme.applyAppearance(appearance.resolved, appearance.material);
    BentoTheme.darkMode.value =
        appearance.isDarkFor(MediaQuery.platformBrightnessOf(context));

    final isEditorial = appearance.design.isEditorial;

    if (isEditorial) {
      return const _PersonalizeEditorialView();
    }

    return const _PersonalizeNeuView();
  }
}

// =============================================================================
// VISTA EDITORIAL (SISTEMA MODERNO DE TRES TONOS)
// =============================================================================

class _PersonalizeEditorialView extends ConsumerWidget {
  const _PersonalizeEditorialView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);

    return Scaffold(
      backgroundColor: EditorialTheme.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _HeaderEditorial(design: appearance.design),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                children: [
                  const _LiveMockupEditorial(),
                  const SizedBox(height: 28),
                  const _SectionHeaderEditorial(
                    title: 'Diseño',
                    subtitle: 'Cómo se componen y sienten las pantallas',
                    badge: 'ESTILO',
                  ),
                  const SizedBox(height: 12),
                  _DesignSelectorEditorial(design: appearance.design),
                  const SizedBox(height: 28),
                  const _SectionHeaderEditorial(
                    title: 'Tema',
                    subtitle: 'Claridad y modo de iluminación general',
                    badge: 'MODO',
                  ),
                  const SizedBox(height: 12),
                  _ModeSelectorEditorial(mode: appearance.mode),
                  const SizedBox(height: 28),
                  const _SectionHeaderEditorial(
                    title: 'Paleta',
                    subtitle: 'Colores de acento para hábitos, agenda y pestañas',
                    badge: 'COLOR',
                  ),
                  const SizedBox(height: 12),
                  _PaletteSectionEditorial(spec: appearance.palette),
                  const SizedBox(height: 28),
                  const _SectionHeaderEditorial(
                    title: 'Material',
                    subtitle: 'Tinte sutil y temperatura sobre la superficie',
                    badge: 'SUPERFICIE',
                  ),
                  const SizedBox(height: 12),
                  _MaterialSectionEditorial(material: appearance.material),
                  const SizedBox(height: 28),
                  const _SectionHeaderEditorial(
                    title: 'Dock',
                    subtitle: 'Accesos rápidos y distribución de navegación',
                    badge: 'BARRA',
                  ),
                  const SizedBox(height: 12),
                  const _DockSectionEditorial(),
                  const SizedBox(height: 32),
                  const _ResetSectionEditorial(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderEditorial extends StatelessWidget {
  final DesignLanguage design;
  const _HeaderEditorial({required this.design});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 20, 16),
      child: Row(
        children: [
          EditorialCircleButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Volver',
            onTap: () => Navigator.of(context).pop(),
            size: 42,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Personalizar',
                  style: EditorialTheme.caps(
                    22,
                    color: EditorialTheme.paper,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Apariencia y Sistema',
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: EditorialTheme.surface,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: EditorialTheme.surfaceHigh,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: EditorialTheme.accent(BentoTheme.accentHabits, onDark: true),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  design.label.toUpperCase(),
                  style: EditorialTheme.label(
                    10,
                    color: EditorialTheme.paper,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeaderEditorial extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? badge;

  const _SectionHeaderEditorial({
    required this.title,
    required this.subtitle,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: EditorialTheme.label(12, color: EditorialTheme.paperAlpha(0.70)),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: EditorialTheme.text(12, color: EditorialTheme.muted),
              ),
            ],
          ),
        ),
        if (badge != null)
          Text(
            badge!,
            style: EditorialTheme.label(9, color: EditorialTheme.muted.withValues(alpha: 0.6)),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO INTERACTIVE PREVIEW CARD
// ─────────────────────────────────────────────────────────────────────────────

class _LiveMockupEditorial extends ConsumerWidget {
  const _LiveMockupEditorial();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(dockProvider).slots;
    final habitColor = EditorialTheme.accent(BentoTheme.accentHabits, onDark: false);

    return Container(
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header de la mini-app
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: EditorialTheme.gray,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.blur_on_rounded,
                      size: 16,
                      color: habitColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'VISTA PREVIA EN VIVO',
                    style: EditorialTheme.caps(
                      13,
                      color: EditorialTheme.ink,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: EditorialTheme.gray,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Activo',
                      style: EditorialTheme.text(10, weight: FontWeight.w600, color: EditorialTheme.ink),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Mini tarjeta de hábito simulada
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: EditorialTheme.gray,
              borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: habitColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.check_circle_outline_rounded,
                        size: 18,
                        color: habitColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hábitos y Productividad',
                            style: EditorialTheme.text(
                              13,
                              weight: FontWeight.w700,
                              color: EditorialTheme.ink,
                            ),
                          ),
                          Text(
                            '3 de 4 completados hoy',
                            style: EditorialTheme.text(
                              11,
                              color: EditorialTheme.grayText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: habitColor,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '75%',
                        style: EditorialTheme.label(10, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Barra de progreso
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    height: 5,
                    width: double.infinity,
                    color: EditorialTheme.grayStrong,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: 0.75,
                      child: Container(color: habitColor),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Tira de paleta de colores activa
          Row(
            children: [
              Text(
                'Acentos:',
                style: EditorialTheme.text(
                  11,
                  weight: FontWeight.w600,
                  color: EditorialTheme.grayText,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final color in BentoTheme.accents.all)
                        Container(
                          width: 18,
                          height: 18,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: EditorialTheme.accent(color, onDark: false),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: EditorialTheme.grayStrong,
                              width: 1.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Mini Barra Dock
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: EditorialTheme.canvas,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var i = 0; i < slots.length; i++)
                  _MiniDockSlot(
                    icon: slots[i].icon,
                    color: EditorialTheme.accent(slots[i].accent, onDark: true),
                    selected: i == 0,
                  ),
                const _MiniDockSlot(
                  icon: Icons.menu_rounded,
                  color: EditorialTheme.muted,
                  selected: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniDockSlot extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool selected;

  const _MiniDockSlot({
    required this.icon,
    required this.color,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? EditorialTheme.surfaceHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        icon,
        size: 17,
        color: selected ? color : EditorialTheme.muted,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SELECTOR DE DISEÑO / ESTILO VISUAL (EDITORIAL VS RELIEVE)
// ─────────────────────────────────────────────────────────────────────────────

class _DesignSelectorEditorial extends ConsumerWidget {
  final DesignLanguage design;
  const _DesignSelectorEditorial({required this.design});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appearanceProvider.notifier);

    return Column(
      children: [
        Row(
          children: [
            for (final option in DesignLanguage.values)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: option == DesignLanguage.values.first ? 6 : 0,
                    left: option == DesignLanguage.values.last ? 6 : 0,
                  ),
                  child: _DesignOptionCardEditorial(
                    option: option,
                    selected: design == option,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      notifier.setDesign(option);
                    },
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: EditorialTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EditorialTheme.surfaceHigh, width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: EditorialTheme.accent(BentoTheme.accentBrain, onDark: true),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'El estilo transforma completamente Hábitos, Agenda, Alarma, Finanzas, Biblioteca y Notas. '
                  'El resto de pantallas mantienen compatibilidad total.',
                  style: EditorialTheme.text(
                    11,
                    color: EditorialTheme.muted,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DesignOptionCardEditorial extends StatelessWidget {
  final DesignLanguage option;
  final bool selected;
  final VoidCallback onTap;

  const _DesignOptionCardEditorial({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEdit = option.isEditorial;

    return EditorialPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? EditorialTheme.paper : EditorialTheme.surface,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
          border: Border.all(
            color: selected
                ? EditorialTheme.paper
                : EditorialTheme.surfaceHigh,
            width: selected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Visual preview thumbnail
            Container(
              height: 64,
              width: double.infinity,
              decoration: BoxDecoration(
                color: isEdit ? EditorialTheme.canvas : const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(8),
              child: isEdit
                  ? const _EditorialThumb()
                  : const _NeuThumb(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    option.label,
                    style: EditorialTheme.text(
                      14,
                      weight: FontWeight.w700,
                      color: selected ? EditorialTheme.ink : EditorialTheme.paper,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: EditorialTheme.accent(BentoTheme.accentHabits, onDark: selected),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              option.blurb,
              style: EditorialTheme.text(
                11,
                color: selected ? EditorialTheme.grayText : EditorialTheme.muted,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorialThumb extends StatelessWidget {
  const _EditorialThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: EditorialTheme.grayStrong,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 4,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: EditorialTheme.ink,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 3,
                  width: 24,
                  decoration: BoxDecoration(
                    color: EditorialTheme.grayText,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NeuThumb extends StatelessWidget {
  const _NeuThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0xFF383838),
            offset: Offset(-2, -2),
            blurRadius: 4,
          ),
          BoxShadow(
            color: Color(0xFF141414),
            offset: Offset(2, 2),
            blurRadius: 4,
          ),
        ],
      ),
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFF242424),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0xFF121212),
                  offset: Offset(-1, -1),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  height: 4,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 3,
                  width: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFF888888),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SELECTOR DE MODO / CLARIDAD (CLARO, OSCURO, SISTEMA)
// ─────────────────────────────────────────────────────────────────────────────

class _ModeSelectorEditorial extends ConsumerWidget {
  final ThemeMode mode;
  const _ModeSelectorEditorial({required this.mode});

  static const _options = [
    (ThemeMode.light, 'Claro', Icons.light_mode_rounded),
    (ThemeMode.dark, 'Oscuro', Icons.dark_mode_rounded),
    (ThemeMode.system, 'Sistema', Icons.settings_brightness_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        for (final (value, label, icon) in _options)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _ModeChipEditorial(
                label: label,
                icon: icon,
                selected: mode == value,
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(appearanceProvider.notifier).setMode(value);
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _ModeChipEditorial extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChipEditorial({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeAccent = EditorialTheme.accent(BentoTheme.accentAlarm, onDark: selected);

    return EditorialPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? EditorialTheme.paper : EditorialTheme.surface,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
          border: Border.all(
            color: selected ? EditorialTheme.paper : EditorialTheme.surfaceHigh,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? activeAccent : EditorialTheme.muted,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: EditorialTheme.text(
                12,
                weight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? EditorialTheme.ink : EditorialTheme.paper,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECCIÓN DE PALETAS DE COLOR
// ─────────────────────────────────────────────────────────────────────────────

class _PaletteSectionEditorial extends ConsumerWidget {
  final PaletteSpec spec;
  const _PaletteSectionEditorial({required this.spec});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appearanceProvider.notifier);

    return Column(
      children: [
        for (final preset in AppPalettes.presets) ...[
          _PalettePresetCardEditorial(
            name: preset.name,
            blurb: preset.blurb,
            colors: preset.resolve().forMode(BentoTheme.isDark).tabs,
            selected: spec.presetId == preset.id,
            onTap: () {
              HapticFeedback.selectionClick();
              notifier.setPreset(preset.id);
            },
          ),
          const SizedBox(height: 8),
        ],

        // Opción: Paleta personalizada
        _PalettePresetCardEditorial(
          name: 'La tuya',
          blurb: 'Elige un color semilla y generamos la armonía',
          colors: spec.isCustom
              ? BentoTheme.accents.tabs
              : AppPalettes.derive(spec.seedHue, spec.scheme, null)
                  .forMode(BentoTheme.isDark)
                  .tabs,
          selected: spec.isCustom,
          onTap: () {
            HapticFeedback.selectionClick();
            notifier.setCustomPalette();
          },
        ),

        if (spec.isCustom) ...[
          const SizedBox(height: 14),
          _CustomPaletteControlsEditorial(spec: spec),
        ],
      ],
    );
  }
}

class _PalettePresetCardEditorial extends StatelessWidget {
  final String name;
  final String blurb;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  const _PalettePresetCardEditorial({
    required this.name,
    required this.blurb,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return EditorialPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? EditorialTheme.paper : EditorialTheme.surface,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
          border: Border.all(
            color: selected ? EditorialTheme.paper : EditorialTheme.surfaceHigh,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Pill con los 5 tonos
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? EditorialTheme.grayStrong : Colors.black26,
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Row(
                  children: [
                    for (final c in colors)
                      Container(
                        width: 14,
                        height: 28,
                        color: EditorialTheme.accent(c, onDark: selected),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: EditorialTheme.text(
                      14,
                      weight: FontWeight.w700,
                      color: selected ? EditorialTheme.ink : EditorialTheme.paper,
                    ),
                  ),
                  Text(
                    blurb,
                    style: EditorialTheme.text(
                      11,
                      color: selected ? EditorialTheme.grayText : EditorialTheme.muted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (selected)
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: EditorialTheme.accent(BentoTheme.accentBrain, onDark: selected),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  size: 14,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CustomPaletteControlsEditorial extends ConsumerWidget {
  final PaletteSpec spec;
  const _CustomPaletteControlsEditorial({required this.spec});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appearanceProvider.notifier);
    final currentColor = Oklch(
      BentoTheme.isDark ? 0.72 : 0.58,
      Oklch.cuspChroma(BentoTheme.isDark ? 0.72 : 0.58, spec.seedHue),
      spec.seedHue,
    ).toColor();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: currentColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: EditorialTheme.grayStrong, width: 2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Tu color',
                style: EditorialTheme.text(
                  14,
                  weight: FontWeight.w700,
                  color: EditorialTheme.ink,
                ),
              ),
              const Spacer(),
              Text(
                '${spec.seedHue.toInt()}°',
                style: EditorialTheme.label(
                  11,
                  color: EditorialTheme.grayText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _HueSliderEditorial(
            hue: spec.seedHue,
            onChanged: (h) => notifier.setCustomPalette(seedHue: h, persist: false),
            onEnd: notifier.commit,
          ),
          const SizedBox(height: 20),
          Text(
            'Distribución armónica',
            style: EditorialTheme.text(
              13,
              weight: FontWeight.w700,
              color: EditorialTheme.ink,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final scheme in PaletteScheme.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _SchemeChoiceChipEditorial(
                      label: scheme.label,
                      selected: spec.scheme == scheme,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        notifier.setCustomPalette(scheme: scheme);
                      },
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: EditorialTheme.gray,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _schemeNote(spec.scheme),
              style: EditorialTheme.text(
                11,
                color: EditorialTheme.grayText,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _schemeNote(PaletteScheme scheme) => switch (scheme) {
        PaletteScheme.analogous =>
          'Análoga: tonos vecinos para una experiencia visual uniforme y suave.',
        PaletteScheme.triad =>
          'Tríada: tres anclas a 120° para un contraste estructurado y balanceado.',
        PaletteScheme.spread =>
          'Rueda: separación completa para que cada pestaña tenga identidad propia.',
      };
}

class _SchemeChoiceChipEditorial extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SchemeChoiceChipEditorial({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return EditorialPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? EditorialTheme.ink : EditorialTheme.gray,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
        ),
        child: Text(
          label,
          style: EditorialTheme.text(
            12,
            weight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? EditorialTheme.paper : EditorialTheme.ink,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SLIDERS Y GRADIENTES
// ─────────────────────────────────────────────────────────────────────────────

class _HueSliderEditorial extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  const _HueSliderEditorial({
    required this.hue,
    required this.onChanged,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    final l = BentoTheme.isDark ? 0.72 : 0.58;
    final track = [
      for (var h = 0; h <= 360; h += 20)
        Oklch(l, Oklch.cuspChroma(l, h.toDouble()), h.toDouble()).toColor(),
    ];

    return _GradientSliderEditorial(
      value: hue,
      min: 0,
      max: 360,
      track: track,
      onChanged: onChanged,
      onEnd: onEnd,
    );
  }
}

class _GradientSliderEditorial extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final List<Color> track;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  const _GradientSliderEditorial({
    required this.value,
    required this.min,
    required this.max,
    required this.track,
    required this.onChanged,
    required this.onEnd,
  });

  static const double _height = 18;
  static const double _thumb = 24;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final usable = width - _thumb;
        final t = ((value - min) / (max - min)).clamp(0.0, 1.0);

        void report(double dx) {
          final ratio = ((dx - _thumb / 2) / usable).clamp(0.0, 1.0);
          onChanged(min + ratio * (max - min));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            report(d.localPosition.dx);
            onEnd();
          },
          onHorizontalDragUpdate: (d) => report(d.localPosition.dx),
          onHorizontalDragEnd: (_) => onEnd(),
          child: SizedBox(
            height: _height + 12,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: _height,
                  margin: const EdgeInsets.symmetric(horizontal: _thumb / 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_height / 2),
                    gradient: LinearGradient(colors: track),
                    border: Border.all(
                      color: EditorialTheme.grayStrong,
                      width: 1,
                    ),
                  ),
                ),
                Positioned(
                  left: t * usable,
                  child: Container(
                    width: _thumb,
                    height: _thumb,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: EditorialTheme.paper,
                      border: Border.all(color: EditorialTheme.ink, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 5,
                          offset: Offset(0, 2),
                        )
                      ],
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// SECCIÓN DE MATERIAL Y TINTE DE SUPERFICIE
// ─────────────────────────────────────────────────────────────────────────────

class _MaterialSectionEditorial extends ConsumerWidget {
  final MaterialSpec? material;
  const _MaterialSectionEditorial({required this.material});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appearanceProvider.notifier);
    final spec = material ?? const MaterialSpec();
    final tinted = material != null && material!.chroma > 0.0005;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tinte de fondo',
                  style: EditorialTheme.text(
                    14,
                    weight: FontWeight.w700,
                    color: EditorialTheme.ink,
                  ),
                ),
              ),
              if (tinted)
                EditorialPressable(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    notifier.setMaterial(null);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: EditorialTheme.gray,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Restaurar Neutro',
                      style: EditorialTheme.text(
                        11,
                        weight: FontWeight.w700,
                        color: EditorialTheme.accent(BentoTheme.accentChat, onDark: false),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _HueSliderEditorial(
            hue: spec.hue,
            onChanged: (h) => notifier.setMaterial(
              MaterialSpec(hue: h, chroma: spec.chroma),
              persist: false,
            ),
            onEnd: notifier.commit,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Intensidad del tinte',
                style: EditorialTheme.text(
                  13,
                  weight: FontWeight.w700,
                  color: EditorialTheme.ink,
                ),
              ),
              Text(
                '${(spec.chroma / MaterialSpec.maxChroma * 100).toInt()}%',
                style: EditorialTheme.label(11, color: EditorialTheme.grayText),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _GradientSliderEditorial(
            value: spec.chroma,
            min: 0,
            max: MaterialSpec.maxChroma,
            track: _materialTrack(spec.hue),
            onChanged: (c) => notifier.setMaterial(
              MaterialSpec(hue: spec.hue, chroma: c),
              persist: false,
            ),
            onEnd: notifier.commit,
          ),
          const SizedBox(height: 10),
          Text(
            'El contraste y la claridad de la superficie se preservan matemáticamente.',
            style: EditorialTheme.text(
              11,
              color: EditorialTheme.grayText,
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _materialTrack(double hue) {
    final l = BentoTheme.isDark ? 0.267 : 0.911;
    return [
      for (var i = 0; i <= 8; i++)
        Oklch(l, MaterialSpec.maxChroma * i / 8, hue).toColor(),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECCIÓN DE DOCK
// ─────────────────────────────────────────────────────────────────────────────

class _DockSectionEditorial extends ConsumerWidget {
  const _DockSectionEditorial();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dock = ref.watch(dockProvider);
    final notifier = ref.read(dockProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cantidad de accesos',
                style: EditorialTheme.text(
                  14,
                  weight: FontWeight.w700,
                  color: EditorialTheme.ink,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: EditorialTheme.gray,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${dock.slots.length}/${dock.size} asignados',
                  style: EditorialTheme.text(
                    11,
                    weight: FontWeight.w700,
                    color: dock.isFull
                        ? EditorialTheme.accent(BentoTheme.accentBrain, onDark: false)
                        : EditorialTheme.grayText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var n = DockConfig.minSize; n <= DockConfig.maxSize; n++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _DockSizeChipEditorial(
                      label: '$n',
                      selected: dock.size == n,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        notifier.setSize(n);
                      },
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Pestañas visibles en el dock',
            style: EditorialTheme.text(
              13,
              weight: FontWeight.w700,
              color: EditorialTheme.ink,
            ),
          ),
          const SizedBox(height: 10),
          for (final destination in AppDestination.values) ...[
            _DockTileEditorial(
              destination: destination,
              position: dock.slots.indexOf(destination),
              enabled: dock.slots.contains(destination) || !dock.isFull,
              onTap: () {
                HapticFeedback.lightImpact();
                notifier.toggle(destination);
              },
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _DockSizeChipEditorial extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DockSizeChipEditorial({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return EditorialPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? EditorialTheme.ink : EditorialTheme.gray,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
        ),
        child: Text(
          label,
          style: EditorialTheme.text(
            13,
            weight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? EditorialTheme.paper : EditorialTheme.ink,
          ),
        ),
      ),
    );
  }
}

class _DockTileEditorial extends StatelessWidget {
  final AppDestination destination;
  final int position;
  final bool enabled;
  final VoidCallback onTap;

  const _DockTileEditorial({
    required this.destination,
    required this.position,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = position >= 0;
    final accent = EditorialTheme.accent(destination.accent, onDark: false);

    return EditorialPressable(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? EditorialTheme.gray : EditorialTheme.gray.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? EditorialTheme.grayStrong : Colors.transparent,
            width: 1,
          ),
        ),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.45,
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  destination.icon,
                  size: 18,
                  color: selected ? accent : EditorialTheme.grayText,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  destination.label,
                  style: EditorialTheme.text(
                    13,
                    weight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: EditorialTheme.ink,
                  ),
                ),
              ),
              if (selected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: EditorialTheme.ink,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '#${position + 1}',
                    style: EditorialTheme.label(
                      10,
                      color: EditorialTheme.paper,
                    ),
                  ),
                )
              else
                Icon(
                  Icons.add_circle_outline_rounded,
                  size: 18,
                  color: enabled ? EditorialTheme.grayText : EditorialTheme.grayStrong,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResetSectionEditorial extends ConsumerWidget {
  const _ResetSectionEditorial();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: EditorialButton(
        label: 'Restablecer colores',
        icon: Icons.restart_alt_rounded,
        ghost: true,
        onTap: () {
          HapticFeedback.mediumImpact();
          ref.read(appearanceProvider.notifier).resetAll();
        },
      ),
    );
  }
}

// =============================================================================
// VISTA RELIEVE / NEUMÓRFICA (ESTILO BASE BENTO)
// =============================================================================

class _PersonalizeNeuView extends ConsumerWidget {
  const _PersonalizeNeuView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);

    return BentoBackground(
      child: SafeArea(
        child: Column(
          children: [
            _HeaderNeu(design: appearance.design),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                children: [
                  const _PreviewCardNeu(),
                  const SizedBox(height: 28),
                  const _SectionTitleNeu('Diseño', 'Cómo se componen las pantallas'),
                  const SizedBox(height: 12),
                  _DesignSectionNeu(design: appearance.design),
                  const SizedBox(height: 28),
                  const _SectionTitleNeu('Tema', 'Qué claridad usa la app'),
                  const SizedBox(height: 12),
                  _ModeSelectorNeu(mode: appearance.mode),
                  const SizedBox(height: 28),
                  const _SectionTitleNeu('Paleta', 'Los colores de cada pestaña'),
                  const SizedBox(height: 12),
                  _PaletteSectionNeu(spec: appearance.palette),
                  const SizedBox(height: 28),
                  const _SectionTitleNeu('Material', 'El tinte de la superficie'),
                  const SizedBox(height: 12),
                  _MaterialSectionNeu(material: appearance.material),
                  const SizedBox(height: 28),
                  const _SectionTitleNeu('Dock', 'Qué pestañas tienes a un toque'),
                  const SizedBox(height: 12),
                  const _DockSectionNeu(),
                  const SizedBox(height: 28),
                  const _ResetButtonNeu(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderNeu extends StatelessWidget {
  final DesignLanguage design;
  const _HeaderNeu({required this.design});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 20, 16),
      child: Row(
        children: [
          NeuCard(
            borderRadius: 14,
            distance: 4,
            blur: 8,
            padding: const EdgeInsets.all(10),
            onTap: () => Navigator.of(context).pop(),
            child: Icon(Icons.arrow_back, color: BentoTheme.cream, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Personalizar',
              style: GoogleFonts.outfit(
                color: BentoTheme.neuText,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: BentoTheme.neuSurfaceSunken,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              design.label.toUpperCase(),
              style: GoogleFonts.outfit(
                color: BentoTheme.creamSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitleNeu extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionTitleNeu(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: GoogleFonts.outfit(
            color: BentoTheme.creamSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: GoogleFonts.outfit(color: BentoTheme.creamTertiary, fontSize: 13),
        ),
      ],
    );
  }
}

class _PreviewCardNeu extends ConsumerWidget {
  const _PreviewCardNeu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(dockProvider).slots;

    return NeuCard(
      borderRadius: 24,
      distance: 6,
      blur: 12,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < slots.length; i++)
                Expanded(
                  child: _PreviewTabNeu(
                    icon: slots[i].icon,
                    color: slots[i].accent,
                    selected: i == 0,
                  ),
                ),
              Expanded(
                child: _PreviewTabNeu(
                  icon: Icons.menu_rounded,
                  color: BentoTheme.creamAlpha(0.42),
                  selected: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final color in BentoTheme.accents.all)
                Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewTabNeu extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool selected;
  const _PreviewTabNeu({required this.icon, required this.color, required this.selected});

  @override
  Widget build(BuildContext context) {
    final iconWidget = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Icon(
        icon,
        color: selected ? color : BentoTheme.creamAlpha(0.42),
        size: 21,
      ),
    );
    if (!selected) return iconWidget;
    return NeuPressed(
      borderRadius: 14,
      distance: 3,
      blur: 6,
      color: Color.alphaBlend(color.withValues(alpha: 0.10), BentoTheme.neuSurfaceSunken),
      child: iconWidget,
    );
  }
}

class _DesignSectionNeu extends ConsumerWidget {
  final DesignLanguage design;
  const _DesignSectionNeu({required this.design});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appearanceProvider.notifier);

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final option in DesignLanguage.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _DesignOptionNeu(
                    option: option,
                    selected: design == option,
                    onTap: () => notifier.setDesign(option),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Afecta a Hábitos, Notas, Alarma, Finanzas, Biblioteca y Agenda, que '
          'son las pestañas con las dos versiones hechas. Las demás se siguen '
          'pintando en relieve.',
          style: GoogleFonts.outfit(
            color: BentoTheme.creamTertiary,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _DesignOptionNeu extends StatelessWidget {
  final DesignLanguage option;
  final bool selected;
  final VoidCallback onTap;

  const _DesignOptionNeu({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = BentoTheme.accentHabits;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 76,
            width: double.infinity,
            child: option.isEditorial
                ? const _EditorialThumb()
                : const _NeuThumb(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  option.label,
                  style: GoogleFonts.outfit(
                    color: selected ? BentoTheme.neuText : BentoTheme.creamAlpha(0.6),
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check_circle, size: 18, color: accent),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            option.blurb,
            style: GoogleFonts.outfit(
              color: BentoTheme.creamTertiary,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: selected
          ? NeuPressed(
              borderRadius: 20,
              color: Color.alphaBlend(
                accent.withValues(alpha: 0.10),
                BentoTheme.neuSurfaceSunken,
              ),
              child: content,
            )
          : NeuCard(
              borderRadius: 20,
              distance: 4,
              blur: 8,
              padding: EdgeInsets.zero,
              child: content,
            ),
    );
  }
}

class _ModeSelectorNeu extends ConsumerWidget {
  final ThemeMode mode;
  const _ModeSelectorNeu({required this.mode});

  static const _options = [
    (ThemeMode.light, 'Claro', Icons.light_mode_outlined),
    (ThemeMode.dark, 'Oscuro', Icons.dark_mode_outlined),
    (ThemeMode.system, 'Sistema', Icons.smartphone_outlined),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        for (final (value, label, icon) in _options)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _ChoiceChipNeu(
                label: label,
                icon: icon,
                selected: mode == value,
                accent: BentoTheme.accentAlarm,
                onTap: () => ref.read(appearanceProvider.notifier).setMode(value),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChoiceChipNeu extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ChoiceChipNeu({
    required this.label,
    this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? BentoTheme.neuText : BentoTheme.creamAlpha(0.55);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: selected ? accent : color),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: GoogleFonts.outfit(
              color: color,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: selected
          ? NeuPressed(
              borderRadius: 14,
              color: Color.alphaBlend(accent.withValues(alpha: 0.12), BentoTheme.neuSurfaceSunken),
              child: content,
            )
          : NeuCard(
              borderRadius: 14,
              distance: 3,
              blur: 6,
              padding: EdgeInsets.zero,
              child: content,
            ),
    );
  }
}

class _PaletteSectionNeu extends ConsumerWidget {
  final PaletteSpec spec;
  const _PaletteSectionNeu({required this.spec});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appearanceProvider.notifier);

    return Column(
      children: [
        for (final preset in AppPalettes.presets) ...[
          _PaletteRowNeu(
            name: preset.name,
            blurb: preset.blurb,
            colors: preset.resolve().forMode(BentoTheme.isDark).tabs,
            selected: spec.presetId == preset.id,
            onTap: () => notifier.setPreset(preset.id),
          ),
          const SizedBox(height: 10),
        ],
        _PaletteRowNeu(
          name: 'La tuya',
          blurb: 'Elige un color y genero el resto',
          colors: spec.isCustom
              ? BentoTheme.accents.tabs
              : AppPalettes.derive(spec.seedHue, spec.scheme, null)
                  .forMode(BentoTheme.isDark)
                  .tabs,
          selected: spec.isCustom,
          onTap: () => notifier.setCustomPalette(),
        ),
        if (spec.isCustom) ...[
          const SizedBox(height: 16),
          _SeedControlsNeu(spec: spec),
        ],
      ],
    );
  }
}

class _PaletteRowNeu extends StatelessWidget {
  final String name;
  final String blurb;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteRowNeu({
    required this.name,
    required this.blurb,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                for (final c in colors) Container(width: 16, height: 28, color: c),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.outfit(
                    color: BentoTheme.neuText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  blurb,
                  style: GoogleFonts.outfit(color: BentoTheme.creamTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
          if (selected)
            Icon(Icons.check_circle, size: 20, color: BentoTheme.accentBrain),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: selected
          ? NeuPressed(
              borderRadius: 18,
              color: Color.alphaBlend(
                BentoTheme.accentBrain.withValues(alpha: 0.10),
                BentoTheme.neuSurfaceSunken,
              ),
              child: content,
            )
          : NeuCard(
              borderRadius: 18,
              distance: 3,
              blur: 6,
              padding: EdgeInsets.zero,
              child: content,
            ),
    );
  }
}

class _SeedControlsNeu extends ConsumerWidget {
  final PaletteSpec spec;
  const _SeedControlsNeu({required this.spec});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appearanceProvider.notifier);

    return NeuCard(
      borderRadius: 20,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tu color',
            style: GoogleFonts.outfit(
              color: BentoTheme.neuText,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _HueSliderNeu(
            hue: spec.seedHue,
            onChanged: (h) => notifier.setCustomPalette(seedHue: h, persist: false),
            onEnd: notifier.commit,
          ),
          const SizedBox(height: 18),
          Text(
            'Cómo reparto el resto',
            style: GoogleFonts.outfit(
              color: BentoTheme.neuText,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final scheme in PaletteScheme.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _ChoiceChipNeu(
                      label: scheme.label,
                      selected: spec.scheme == scheme,
                      accent: BentoTheme.accentHabits,
                      onTap: () => notifier.setCustomPalette(scheme: scheme),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HueSliderNeu extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  const _HueSliderNeu({required this.hue, required this.onChanged, required this.onEnd});

  @override
  Widget build(BuildContext context) {
    final l = BentoTheme.isDark ? 0.72 : 0.58;
    final track = [
      for (var h = 0; h <= 360; h += 20)
        Oklch(l, Oklch.cuspChroma(l, h.toDouble()), h.toDouble()).toColor(),
    ];

    return _GradientSliderNeu(
      value: hue,
      min: 0,
      max: 360,
      track: track,
      onChanged: onChanged,
      onEnd: onEnd,
    );
  }
}

class _GradientSliderNeu extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final List<Color> track;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  const _GradientSliderNeu({
    required this.value,
    required this.min,
    required this.max,
    required this.track,
    required this.onChanged,
    required this.onEnd,
  });

  static const double _height = 20;
  static const double _thumb = 22;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final usable = width - _thumb;
        final t = ((value - min) / (max - min)).clamp(0.0, 1.0);

        void report(double dx) {
          final ratio = ((dx - _thumb / 2) / usable).clamp(0.0, 1.0);
          onChanged(min + ratio * (max - min));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            report(d.localPosition.dx);
            onEnd();
          },
          onHorizontalDragUpdate: (d) => report(d.localPosition.dx),
          onHorizontalDragEnd: (_) => onEnd(),
          child: SizedBox(
            height: _height + 8,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                NeuPressed(
                  borderRadius: _height / 2,
                  distance: 2,
                  blur: 4,
                  child: Container(
                    height: _height,
                    margin: const EdgeInsets.symmetric(horizontal: _thumb / 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_height / 2),
                      gradient: LinearGradient(colors: track),
                    ),
                  ),
                ),
                Positioned(
                  left: t * usable,
                  child: NeuCard(
                    borderRadius: _thumb / 2,
                    distance: 3,
                    blur: 6,
                    padding: EdgeInsets.zero,
                    child: SizedBox(width: _thumb, height: _thumb),
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

class _MaterialSectionNeu extends ConsumerWidget {
  final MaterialSpec? material;
  const _MaterialSectionNeu({required this.material});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appearanceProvider.notifier);
    final spec = material ?? const MaterialSpec();
    final tinted = material != null && material!.chroma > 0.0005;

    return NeuCard(
      borderRadius: 20,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tinte',
                  style: GoogleFonts.outfit(
                    color: BentoTheme.neuText,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (tinted)
                GestureDetector(
                  onTap: () => notifier.setMaterial(null),
                  child: Text(
                    'Neutro',
                    style: GoogleFonts.outfit(
                      color: BentoTheme.accentChat,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _HueSliderNeu(
            hue: spec.hue,
            onChanged: (h) => notifier.setMaterial(
              MaterialSpec(hue: h, chroma: spec.chroma),
              persist: false,
            ),
            onEnd: notifier.commit,
          ),
          const SizedBox(height: 18),
          Text(
            'Intensidad',
            style: GoogleFonts.outfit(
              color: BentoTheme.neuText,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _GradientSliderNeu(
            value: spec.chroma,
            min: 0,
            max: MaterialSpec.maxChroma,
            track: _materialTrack(spec.hue),
            onChanged: (c) => notifier.setMaterial(
              MaterialSpec(hue: spec.hue, chroma: c),
              persist: false,
            ),
            onEnd: notifier.commit,
          ),
        ],
      ),
    );
  }

  List<Color> _materialTrack(double hue) {
    final l = BentoTheme.isDark ? 0.267 : 0.911;
    return [
      for (var i = 0; i <= 8; i++)
        Oklch(l, MaterialSpec.maxChroma * i / 8, hue).toColor(),
    ];
  }
}

class _DockSectionNeu extends ConsumerWidget {
  const _DockSectionNeu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dock = ref.watch(dockProvider);
    final notifier = ref.read(dockProvider.notifier);

    return NeuCard(
      borderRadius: 20,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cuántas pestañas',
            style: GoogleFonts.outfit(
              color: BentoTheme.neuText,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var n = DockConfig.minSize; n <= DockConfig.maxSize; n++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _ChoiceChipNeu(
                      label: '$n',
                      selected: dock.size == n,
                      accent: BentoTheme.accentBrain,
                      onTap: () => notifier.setSize(n),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Cuáles',
                  style: GoogleFonts.outfit(
                    color: BentoTheme.neuText,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${dock.slots.length}/${dock.size}',
                style: GoogleFonts.outfit(
                  color: dock.isFull ? BentoTheme.accentBrain : BentoTheme.creamTertiary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final destination in AppDestination.values) ...[
            _DockRowNeu(
              destination: destination,
              position: dock.slots.indexOf(destination),
              enabled: dock.slots.contains(destination) || !dock.isFull,
              onTap: () => notifier.toggle(destination),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _DockRowNeu extends StatelessWidget {
  final AppDestination destination;
  final int position;
  final bool enabled;
  final VoidCallback onTap;

  const _DockRowNeu({
    required this.destination,
    required this.position,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = position >= 0;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(
            destination.icon,
            size: 20,
            color: selected
                ? BentoTheme.neuText
                : (enabled ? BentoTheme.creamAlpha(0.6) : BentoTheme.creamAlpha(0.25)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              destination.label,
              style: GoogleFonts.outfit(
                color: selected
                    ? BentoTheme.neuText
                    : (enabled ? BentoTheme.creamAlpha(0.85) : BentoTheme.creamAlpha(0.35)),
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (selected)
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: BentoTheme.creamAlpha(0.15),
                shape: BoxShape.circle,
              ),
              child: Text(
                '${position + 1}',
                style: GoogleFonts.outfit(
                  color: BentoTheme.neuText,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: selected
          ? NeuPressed(
              borderRadius: 14,
              color: BentoTheme.neuSurfaceSunken,
              child: content,
            )
          : NeuCard(
              borderRadius: 14,
              distance: 2,
              blur: 4,
              padding: EdgeInsets.zero,
              child: Opacity(
                opacity: enabled ? 1 : 0.45,
                child: content,
              ),
            ),
    );
  }
}

class _ResetButtonNeu extends ConsumerWidget {
  const _ResetButtonNeu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NeuCard(
      borderRadius: 16,
      distance: 3,
      blur: 6,
      padding: const EdgeInsets.symmetric(vertical: 14),
      onTap: () => ref.read(appearanceProvider.notifier).resetAll(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.restart_alt, size: 18, color: BentoTheme.creamSecondary),
          const SizedBox(width: 8),
          Text(
            'Restablecer colores',
            style: GoogleFonts.outfit(
              color: BentoTheme.creamSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
