import 'package:flutter/material.dart';
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

/// Pantalla de personalización: modo, paleta de acentos y tinte del material.
///
/// Todo se aplica en vivo. Los cambios los pinta esta misma pantalla porque
/// sincroniza BentoTheme en su propio build: main.dart también lo hace, pero
/// ambos escuchan el mismo provider y Riverpod no garantiza en qué orden
/// construyen — sin esto, un frame de cada cambio saldría con la paleta vieja.
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
      return ColoredBox(
        color: EditorialTheme.canvas,
        child: SafeArea(
          child: Column(
            children: [
              _HeaderEditorial(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  children: [
                    _PreviewCardEditorial(),
                    const SizedBox(height: 28),
                    _SectionTitleEditorial('Diseño', 'Cómo se componen las pantallas'),
                    const SizedBox(height: 12),
                    _DesignSectionEditorial(design: appearance.design),
                    const SizedBox(height: 28),
                    _SectionTitleEditorial('Tema', 'Qué claridad usa la app'),
                    const SizedBox(height: 12),
                    _ModeSelectorEditorial(mode: appearance.mode),
                    const SizedBox(height: 28),
                    _SectionTitleEditorial('Paleta', 'Los colores de cada pestaña'),
                    const SizedBox(height: 12),
                    _PaletteSectionEditorial(spec: appearance.palette),
                    const SizedBox(height: 28),
                    _SectionTitleEditorial('Material', 'El tinte de la superficie'),
                    const SizedBox(height: 12),
                    _MaterialSectionEditorial(material: appearance.material),
                    const SizedBox(height: 28),
                    _SectionTitleEditorial('Dock', 'Qué pestañas tienes a un toque'),
                    const SizedBox(height: 12),
                    _DockSectionEditorial(),
                    const SizedBox(height: 28),
                    _ResetButtonEditorial(),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return BentoBackground(
      child: Column(
        children: [
          _Header(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                _PreviewCard(),
                const SizedBox(height: 28),
                _SectionTitle('Diseño', 'Cómo se componen las pantallas'),
                const SizedBox(height: 12),
                _DesignSection(design: appearance.design),
                const SizedBox(height: 28),
                _SectionTitle('Tema', 'Qué claridad usa la app'),
                const SizedBox(height: 12),
                _ModeSelector(mode: appearance.mode),
                const SizedBox(height: 28),
                _SectionTitle('Paleta', 'Los colores de cada pestaña'),
                const SizedBox(height: 12),
                _PaletteSection(spec: appearance.palette),
                const SizedBox(height: 28),
                _SectionTitle('Material', 'El tinte de la superficie'),
                const SizedBox(height: 12),
                _MaterialSection(material: appearance.material),
                const SizedBox(height: 28),
                _SectionTitle('Dock', 'Qué pestañas tienes a un toque'),
                const SizedBox(height: 12),
                _DockSection(),
                const SizedBox(height: 28),
                _ResetButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SECCIÓN NEUMÓRFICA (ESTILO BASE/RELIEVE)
// =============================================================================

class _Header extends StatelessWidget {
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
          Text(
            'Personalizar',
            style: GoogleFonts.outfit(
              color: BentoTheme.neuText,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionTitle(this.title, this.subtitle);

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

class _PreviewCard extends ConsumerWidget {
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
                  child: _PreviewTab(
                    icon: slots[i].icon,
                    color: slots[i].accent,
                    selected: i == 0,
                  ),
                ),
              Expanded(
                child: _PreviewTab(
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

class _PreviewTab extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool selected;
  const _PreviewTab({required this.icon, required this.color, required this.selected});

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

class _DesignSection extends ConsumerWidget {
  final DesignLanguage design;
  const _DesignSection({required this.design});

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
                  child: _DesignOption(
                    option: option,
                    selected: design == option,
                    onTap: () => notifier.setDesign(option),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const _Note(
          'Afecta a Hábitos, Notas, Alarma, Finanzas, Biblioteca y Agenda, que '
          'son las pestañas con las dos versiones hechas. Las demás se siguen '
          'pintando en relieve.',
        ),
      ],
    );
  }
}

class _DesignOption extends StatelessWidget {
  final DesignLanguage option;
  final bool selected;
  final VoidCallback onTap;

  const _DesignOption({
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

class _NeuThumb extends StatelessWidget {
  const _NeuThumb();

  @override
  Widget build(BuildContext context) {
    return NeuPressed(
      borderRadius: 12,
      distance: 2,
      blur: 5,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: NeuCard(
          borderRadius: 10,
          distance: 3,
          blur: 6,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              NeuPressed(
                borderRadius: 20,
                distance: 2,
                blur: 4,
                child: const SizedBox(width: 18, height: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Bar(width: double.infinity, color: BentoTheme.creamAlpha(0.55)),
                    const SizedBox(height: 5),
                    _Bar(width: 34, color: BentoTheme.creamAlpha(0.25)),
                  ],
                ),
              ),
            ],
          ),
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
        color: EditorialTheme.canvas,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(10),
      child: Container(
        decoration: BoxDecoration(
          color: EditorialTheme.paper,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: EditorialTheme.gray,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _Bar(width: double.infinity, color: EditorialTheme.ink),
                  const SizedBox(height: 5),
                  const _Bar(width: 34, color: EditorialTheme.grayStrong),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double width;
  final Color color;
  const _Bar({required this.width, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 4,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _ModeSelector extends ConsumerWidget {
  final ThemeMode mode;
  const _ModeSelector({required this.mode});

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
              child: _Segment(
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

class _Segment extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: selected ? accent : BentoTheme.creamAlpha(0.5)),
            const SizedBox(height: 6),
          ],
          Text(
            label,
            style: GoogleFonts.outfit(
              color: selected ? BentoTheme.neuText : BentoTheme.creamAlpha(0.5),
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
              borderRadius: 16,
              color: Color.alphaBlend(
                accent.withValues(alpha: 0.10),
                BentoTheme.neuSurfaceSunken,
              ),
              child: content,
            )
          : NeuCard(
              borderRadius: 16,
              distance: 4,
              blur: 8,
              padding: EdgeInsets.zero,
              child: content,
            ),
    );
  }
}

class _PaletteSection extends ConsumerWidget {
  final PaletteSpec spec;
  const _PaletteSection({required this.spec});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appearanceProvider.notifier);

    return Column(
      children: [
        for (final preset in AppPalettes.presets) ...[
          _PaletteRow(
            name: preset.name,
            blurb: preset.blurb,
            colors: preset.resolve().forMode(BentoTheme.isDark).tabs,
            selected: spec.presetId == preset.id,
            onTap: () => notifier.setPreset(preset.id),
          ),
          const SizedBox(height: 10),
        ],
        _PaletteRow(
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
          _SeedControls(spec: spec),
        ],
      ],
    );
  }
}

class _PaletteRow extends StatelessWidget {
  final String name;
  final String blurb;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteRow({
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
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
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
          ? NeuPressed(borderRadius: 18, child: content)
          : NeuCard(
              borderRadius: 18,
              distance: 4,
              blur: 8,
              padding: EdgeInsets.zero,
              child: content,
            ),
    );
  }
}

class _SeedControls extends ConsumerWidget {
  final PaletteSpec spec;
  const _SeedControls({required this.spec});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appearanceProvider.notifier);

    return NeuCard(
      borderRadius: 20,
      distance: 5,
      blur: 10,
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
          _HueSlider(
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
                    child: _Segment(
                      label: scheme.label,
                      selected: spec.scheme == scheme,
                      accent: BentoTheme.accentHabits,
                      onTap: () => notifier.setCustomPalette(scheme: scheme),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _Note(_schemeNote(spec.scheme)),
        ],
      ),
    );
  }

  String _schemeNote(PaletteScheme scheme) => switch (scheme) {
        PaletteScheme.analogous =>
          'Todo en una familia de color. Bonita, pero las pestañas se parecen más entre sí.',
        PaletteScheme.triad => 'Tres colores anclados a 120°: contraste con estructura.',
        PaletteScheme.spread => 'La rueda entera. Cada pestaña se distingue al máximo.',
      };
}

class _DockSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dock = ref.watch(dockProvider);
    final notifier = ref.read(dockProvider.notifier);

    return NeuCard(
      borderRadius: 20,
      distance: 5,
      blur: 10,
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
                    child: _Segment(
                      label: '$n',
                      selected: dock.size == n,
                      accent: BentoTheme.accentBrain,
                      onTap: () => notifier.setSize(n),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const _Note(
            'El botón de menú va aparte y siempre está. Lo que no entre en el '
            'dock lo sigues abriendo desde ahí.',
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
            _DockRow(
              destination: destination,
              position: dock.slots.indexOf(destination),
              enabled: dock.slots.contains(destination) || !dock.isFull,
              onTap: () => notifier.toggle(destination),
            ),
            const SizedBox(height: 8),
          ],
          if (dock.isFull)
            const _Note('Para cambiar una, quítala primero y elige otra.'),
        ],
      ),
    );
  }
}

class _DockRow extends StatelessWidget {
  final AppDestination destination;
  final int position;
  final bool enabled;
  final VoidCallback onTap;

  const _DockRow({
    required this.destination,
    required this.position,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = position >= 0;
    final accent = destination.accent;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(
            destination.icon,
            size: 20,
            color: selected ? accent : BentoTheme.creamAlpha(enabled ? 0.45 : 0.22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              destination.label,
              style: GoogleFonts.outfit(
                color: selected
                    ? BentoTheme.neuText
                    : BentoTheme.creamAlpha(enabled ? 0.6 : 0.3),
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
                color: accent.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Text(
                '${position + 1}',
                style: GoogleFonts.outfit(
                  color: accent,
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
              borderRadius: 16,
              color: Color.alphaBlend(
                accent.withValues(alpha: 0.10),
                BentoTheme.neuSurfaceSunken,
              ),
              child: content,
            )
          : Opacity(
              opacity: enabled ? 1 : 0.5,
              child: NeuCard(
                borderRadius: 16,
                distance: 4,
                blur: 8,
                padding: EdgeInsets.zero,
                child: content,
              ),
            ),
    );
  }
}

class _MaterialSection extends ConsumerWidget {
  final MaterialSpec? material;
  const _MaterialSection({required this.material});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appearanceProvider.notifier);
    final spec = material ?? const MaterialSpec();
    final tinted = material != null && material!.chroma > 0.0005;

    return NeuCard(
      borderRadius: 20,
      distance: 5,
      blur: 10,
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
          _HueSlider(
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
          _GradientSlider(
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
          const SizedBox(height: 12),
          const _Note(
            'La claridad del material no se toca: el relieve depende de ella. '
            'Puedes teñirlo, no romperlo.',
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

class _HueSlider extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  const _HueSlider({required this.hue, required this.onChanged, required this.onEnd});

  @override
  Widget build(BuildContext context) {
    final l = BentoTheme.isDark ? 0.72 : 0.58;
    final track = [
      for (var h = 0; h <= 360; h += 20)
        Oklch(l, Oklch.cuspChroma(l, h.toDouble()), h.toDouble()).toColor(),
    ];

    return _GradientSlider(
      value: hue,
      min: 0,
      max: 360,
      track: track,
      onChanged: onChanged,
      onEnd: onEnd,
    );
  }
}

class _GradientSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final List<Color> track;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  const _GradientSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.track,
    required this.onChanged,
    required this.onEnd,
  });

  static const double _height = 26;
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
                    margin: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(_height / 2),
                      gradient: LinearGradient(colors: track),
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
                      color: BentoTheme.neuSurface,
                      boxShadow: BentoTheme.neuFloating(elevation: 8),
                      border: Border.all(color: BentoTheme.neuShadowLight, width: 2),
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

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.outfit(
        color: BentoTheme.creamTertiary,
        fontSize: 12,
        height: 1.4,
      ),
    );
  }
}

class _ResetButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NeuCard(
      borderRadius: 18,
      distance: 4,
      blur: 8,
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

// =============================================================================
// SECCIÓN EDITORIAL (ESTILO NUEVO)
// =============================================================================

class _HeaderEditorial extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 20, 16),
      child: Row(
        children: [
          EditorialCircleButton(
            icon: Icons.arrow_back,
            tooltip: 'Volver',
            onTap: () => Navigator.of(context).pop(),
            size: 42,
          ),
          const SizedBox(width: 14),
          Text(
            'Personalizar',
            style: EditorialTheme.caps(
              24,
              color: EditorialTheme.paper,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitleEditorial extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionTitleEditorial(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: EditorialTheme.label(12, color: EditorialTheme.muted),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: EditorialTheme.text(13, color: EditorialTheme.grayText),
        ),
      ],
    );
  }
}

class _PreviewCardEditorial extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(dockProvider).slots;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < slots.length; i++)
                Expanded(
                  child: _PreviewTabEditorial(
                    icon: slots[i].icon,
                    color: slots[i].accent,
                    selected: i == 0,
                  ),
                ),
              Expanded(
                child: _PreviewTabEditorial(
                  icon: Icons.menu_rounded,
                  color: EditorialTheme.grayText,
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
                  decoration: BoxDecoration(
                    color: EditorialTheme.accent(color, onDark: false),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewTabEditorial extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool selected;
  const _PreviewTabEditorial({required this.icon, required this.color, required this.selected});

  @override
  Widget build(BuildContext context) {
    final accentColor = EditorialTheme.accent(color, onDark: false);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: selected ? EditorialTheme.gray : Colors.transparent,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
      ),
      child: Icon(
        icon,
        color: selected ? accentColor : EditorialTheme.grayText,
        size: 21,
      ),
    );
  }
}

class _DesignSectionEditorial extends ConsumerWidget {
  final DesignLanguage design;
  const _DesignSectionEditorial({required this.design});

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
                  child: _DesignOptionEditorial(
                    option: option,
                    selected: design == option,
                    onTap: () => notifier.setDesign(option),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const _NoteEditorial(
          'Afecta a Hábitos, Notas, Alarma, Finanzas, Biblioteca y Agenda, que '
          'son las pestañas con las dos versiones hechas. Las demás se siguen '
          'pintando en relieve.',
        ),
      ],
    );
  }
}

class _DesignOptionEditorial extends StatelessWidget {
  final DesignLanguage option;
  final bool selected;
  final VoidCallback onTap;

  const _DesignOptionEditorial({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                  style: EditorialTheme.text(
                    15,
                    weight: FontWeight.w700,
                    color: selected ? EditorialTheme.ink : EditorialTheme.paper,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle,
                  size: 18,
                  color: EditorialTheme.accent(BentoTheme.accentHabits, onDark: selected),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            option.blurb,
            style: EditorialTheme.text(
              12,
              color: selected ? EditorialTheme.grayText : EditorialTheme.muted,
              height: 1.3,
            ),
          ),
        ],
      ),
    );

    return EditorialPressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? EditorialTheme.paper : EditorialTheme.surface,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
        ),
        child: content,
      ),
    );
  }
}

class _ModeSelectorEditorial extends ConsumerWidget {
  final ThemeMode mode;
  const _ModeSelectorEditorial({required this.mode});

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
              child: EditorialChoice(
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

class _PaletteSectionEditorial extends ConsumerWidget {
  final PaletteSpec spec;
  const _PaletteSectionEditorial({required this.spec});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appearanceProvider.notifier);

    return Column(
      children: [
        for (final preset in AppPalettes.presets) ...[
          _PaletteRowEditorial(
            name: preset.name,
            blurb: preset.blurb,
            colors: preset.resolve().forMode(BentoTheme.isDark).tabs,
            selected: spec.presetId == preset.id,
            onTap: () => notifier.setPreset(preset.id),
          ),
          const SizedBox(height: 10),
        ],
        _PaletteRowEditorial(
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
          _SeedControlsEditorial(spec: spec),
        ],
      ],
    );
  }
}

class _PaletteRowEditorial extends StatelessWidget {
  final String name;
  final String blurb;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteRowEditorial({
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
                for (final c in colors)
                  Container(
                    width: 16,
                    height: 28,
                    color: EditorialTheme.accent(c, onDark: selected),
                  ),
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
                  style: EditorialTheme.text(
                    15,
                    weight: FontWeight.w700,
                    color: selected ? EditorialTheme.ink : EditorialTheme.paper,
                  ),
                ),
                Text(
                  blurb,
                  style: EditorialTheme.text(
                    12,
                    color: selected ? EditorialTheme.grayText : EditorialTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            Icon(
              Icons.check_circle,
              size: 20,
              color: EditorialTheme.accent(BentoTheme.accentBrain, onDark: selected),
            ),
        ],
      ),
    );

    return EditorialPressable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? EditorialTheme.paper : EditorialTheme.surface,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
        ),
        child: content,
      ),
    );
  }
}

class _SeedControlsEditorial extends ConsumerWidget {
  final PaletteSpec spec;
  const _SeedControlsEditorial({required this.spec});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appearanceProvider.notifier);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tu color',
            style: EditorialTheme.text(
              14,
              weight: FontWeight.w700,
              color: EditorialTheme.ink,
            ),
          ),
          const SizedBox(height: 10),
          _HueSliderEditorial(
            hue: spec.seedHue,
            onChanged: (h) => notifier.setCustomPalette(seedHue: h, persist: false),
            onEnd: notifier.commit,
          ),
          const SizedBox(height: 18),
          Text(
            'Cómo reparto el resto',
            style: EditorialTheme.text(
              14,
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
                    child: EditorialChoice(
                      label: scheme.label,
                      selected: spec.scheme == scheme,
                      accent: BentoTheme.accentHabits,
                      onTap: () => notifier.setCustomPalette(scheme: scheme),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _NoteEditorial(_schemeNote(spec.scheme)),
        ],
      ),
    );
  }

  String _schemeNote(PaletteScheme scheme) => switch (scheme) {
        PaletteScheme.analogous =>
          'Todo en una familia de color. Bonita, pero las pestañas se parecen más entre sí.',
        PaletteScheme.triad => 'Tres colores anclados a 120°: contraste con estructura.',
        PaletteScheme.spread => 'La rueda entera. Cada pestaña se distingue al máximo.',
      };
}

class _HueSliderEditorial extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  const _HueSliderEditorial({required this.hue, required this.onChanged, required this.onEnd});

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
                Container(
                  height: _height,
                  margin: const EdgeInsets.symmetric(horizontal: _thumb / 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_height / 2),
                    gradient: LinearGradient(colors: track),
                  ),
                ),
                Positioned(
                  left: t * usable,
                  child: Container(
                    width: _thumb,
                    height: _thumb,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: EditorialTheme.paper,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
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

class _MaterialSectionEditorial extends ConsumerWidget {
  final MaterialSpec? material;
  const _MaterialSectionEditorial({required this.material});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appearanceProvider.notifier);
    final spec = material ?? const MaterialSpec();
    final tinted = material != null && material!.chroma > 0.0005;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
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
                  'Tinte',
                  style: EditorialTheme.text(
                    14,
                    weight: FontWeight.w700,
                    color: EditorialTheme.ink,
                  ),
                ),
              ),
              if (tinted)
                EditorialPressable(
                  onTap: () => notifier.setMaterial(null),
                  child: Text(
                    'Neutro',
                    style: EditorialTheme.text(
                      13,
                      weight: FontWeight.w600,
                      color: EditorialTheme.accent(BentoTheme.accentChat, onDark: false),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _HueSliderEditorial(
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
            style: EditorialTheme.text(
              14,
              weight: FontWeight.w700,
              color: EditorialTheme.ink,
            ),
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
          const SizedBox(height: 12),
          const _NoteEditorial(
            'La claridad del material no se toca: el relieve depende de ella. '
            'Puedes teñirlo, no romperlo.',
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

class _DockSectionEditorial extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dock = ref.watch(dockProvider);
    final notifier = ref.read(dockProvider.notifier);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cuántas pestañas',
            style: EditorialTheme.text(
              14,
              weight: FontWeight.w700,
              color: EditorialTheme.ink,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var n = DockConfig.minSize; n <= DockConfig.maxSize; n++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: EditorialChoice(
                      label: '$n',
                      selected: dock.size == n,
                      accent: BentoTheme.accentBrain,
                      onTap: () => notifier.setSize(n),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const _NoteEditorial(
            'El botón de menú va aparte y siempre está. Lo que no entre en el '
            'dock lo sigues abriendo desde ahí.',
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Cuáles',
                  style: EditorialTheme.text(
                    14,
                    weight: FontWeight.w700,
                    color: EditorialTheme.ink,
                  ),
                ),
              ),
              Text(
                '${dock.slots.length}/${dock.size}',
                style: EditorialTheme.text(
                  13,
                  weight: FontWeight.w700,
                  color: dock.isFull
                      ? EditorialTheme.accent(BentoTheme.accentBrain, onDark: false)
                      : EditorialTheme.grayText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final destination in AppDestination.values) ...[
            _DockRowEditorial(
              destination: destination,
              position: dock.slots.indexOf(destination),
              enabled: dock.slots.contains(destination) || !dock.isFull,
              onTap: () => notifier.toggle(destination),
            ),
            const SizedBox(height: 8),
          ],
          if (dock.isFull)
            const _NoteEditorial('Para cambiar una, quítala primero y elige otra.'),
        ],
      ),
    );
  }
}

class _DockRowEditorial extends StatelessWidget {
  final AppDestination destination;
  final int position;
  final bool enabled;
  final VoidCallback onTap;

  const _DockRowEditorial({
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
                ? EditorialTheme.ink
                : (enabled ? EditorialTheme.grayText : EditorialTheme.grayStrong),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              destination.label,
              style: EditorialTheme.text(
                15,
                weight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? EditorialTheme.ink
                    : (enabled ? EditorialTheme.ink : EditorialTheme.grayText),
              ),
            ),
          ),
          if (selected)
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: EditorialTheme.gray,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${position + 1}',
                style: EditorialTheme.text(
                  12,
                  weight: FontWeight.w700,
                  color: EditorialTheme.ink,
                ),
              ),
            ),
        ],
      ),
    );

    return EditorialPressable(
      onTap: enabled ? onTap : null,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? EditorialTheme.gray : EditorialTheme.gray.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
        ),
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: content,
        ),
      ),
    );
  }
}

class _NoteEditorial extends StatelessWidget {
  final String text;
  const _NoteEditorial(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: EditorialTheme.text(
        12,
        color: EditorialTheme.grayText,
        height: 1.4,
      ),
    );
  }
}

class _ResetButtonEditorial extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EditorialButton(
      label: 'Restablecer colores',
      icon: Icons.restart_alt,
      ghost: true,
      onTap: () => ref.read(appearanceProvider.notifier).resetAll(),
    );
  }
}
