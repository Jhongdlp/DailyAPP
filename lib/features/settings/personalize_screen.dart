import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/providers/appearance_provider.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/theme/oklch.dart';

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
                _ResetButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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

/// Réplica del dock con los acentos activos.
///
/// La vista previa es un dock y no unas muestras sueltas a propósito: los
/// acentos se juzgan en el sitio donde de verdad se van a ver, unos al lado de
/// otros y sobre el material real. Una fila de círculos grandes hace que
/// cualquier paleta parezca buena.
class _PreviewCard extends StatelessWidget {
  static const _icons = [
    Icons.check_circle_outline,
    Icons.psychology_outlined,
    Icons.alarm_outlined,
    Icons.account_balance_wallet_outlined,
    Icons.chat_bubble_outline,
  ];

  @override
  Widget build(BuildContext context) {
    final tabs = BentoTheme.accents.tabs;

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
              for (var i = 0; i < _icons.length; i++)
                Expanded(
                  child: _PreviewTab(
                    icon: _icons[i],
                    color: tabs[i],
                    // Solo una pestaña se dibuja hundida, como en el dock real:
                    // así se ve a la vez el acento activo y los inactivos.
                    selected: i == 0,
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

// ─── Tema ───

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

/// Opción de un grupo excluyente: elegida = hundida, no elegida = extruida.
/// El relieve ya comunica el estado, así que no hace falta ninguna marca extra.
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
          : NeuCard(borderRadius: 16, distance: 4, blur: 8, child: content),
    );
  }
}

// ─── Paleta ───

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
          // Las muestras van pegadas en una tira: así se leen como UNA paleta
          // y se ven las transiciones entre acentos vecinos.
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
          : NeuCard(borderRadius: 18, distance: 4, blur: 8, child: content),
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

// ─── Material ───

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
            // El degradado muestra el tinte a la lightness REAL del material,
            // así que es tan sutil como será el resultado. Es deliberado: el
            // control no debe prometer más color del que va a dar.
            track: _materialTrack(spec.hue),
            onChanged: (c) => notifier.setMaterial(
              MaterialSpec(hue: spec.hue, chroma: c),
              persist: false,
            ),
            onEnd: notifier.commit,
          ),
          const SizedBox(height: 12),
          _Note(
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

// ─── Controles ───

/// Slider de hue con la rueda de color como pista.
///
/// Las muestras se pintan a la lightness de un acento y en la cúspide de croma
/// de cada hue: es decir, la pista enseña exactamente la familia de colores
/// entre los que se está eligiendo, no un arcoíris HSL genérico.
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

/// Slider cuya pista ES el resultado: el usuario elige sobre el color real.
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
        // El pulgar no puede salirse de la pista, así que su centro solo
        // recorre el ancho útil; el mapeo posición↔valor usa ese mismo ancho o
        // los extremos serían inalcanzables.
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
      // El modo no se toca al restablecer: quien vuelve a los colores de
      // fábrica no está pidiendo que le enciendan la pantalla en blanco.
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
