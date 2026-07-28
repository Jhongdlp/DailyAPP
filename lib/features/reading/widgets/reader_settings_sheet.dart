import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/reader_prefs_provider.dart';
import '../../../core/providers/reader_theme_provider.dart';
import 'reader_sheet.dart';

/// Panel de composición del texto: tema, tipografía, tamaño, interlineado,
/// márgenes, brillo y pantalla encendida.
Future<void> showReaderSettingsSheet(
  BuildContext context, {
  required ReaderPalette palette,
  required ValueChanged<double?> onBrightnessChanged,
}) {
  return showReaderSheet(
    context,
    palette: palette,
    builder: (_) => _ReaderSettingsSheet(onBrightnessChanged: onBrightnessChanged),
  );
}

class _ReaderSettingsSheet extends ConsumerWidget {
  final ValueChanged<double?> onBrightnessChanged;

  const _ReaderSettingsSheet({required this.onBrightnessChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(readerThemeProvider);
    final palette = readerPaletteFor(mode);
    final prefs = ref.watch(readerPrefsProvider);
    final notifier = ref.read(readerPrefsProvider.notifier);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReaderSheetTitle(
            text: 'Lectura',
            palette: palette,
            trailing: TextButton(
              onPressed: notifier.resetTypography,
              child: Text(
                'Restablecer',
                style: GoogleFonts.montserrat(
                  color: palette.foregroundAlpha(0.6),
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _themeRow(ref, palette, mode),
          const SizedBox(height: 18),
          _label('Tipografía', palette),
          const SizedBox(height: 8),
          _fontRow(ref, palette, prefs),
          const SizedBox(height: 18),
          _slider(
            palette: palette,
            icon: Icons.format_size,
            label: 'Tamaño',
            value: prefs.fontSize,
            min: ReaderPrefsNotifier.fontSizeRange.min,
            max: ReaderPrefsNotifier.fontSizeRange.max,
            display: prefs.fontSize.toStringAsFixed(0),
            onChanged: notifier.setFontSize,
          ),
          _slider(
            palette: palette,
            icon: Icons.format_line_spacing,
            label: 'Interlineado',
            value: prefs.lineHeight,
            min: ReaderPrefsNotifier.lineHeightRange.min,
            max: ReaderPrefsNotifier.lineHeightRange.max,
            display: prefs.lineHeight.toStringAsFixed(2),
            onChanged: notifier.setLineHeight,
          ),
          _slider(
            palette: palette,
            icon: Icons.width_normal,
            label: 'Márgenes',
            value: prefs.horizontalMargin,
            min: ReaderPrefsNotifier.marginRange.min,
            max: ReaderPrefsNotifier.marginRange.max,
            display: prefs.horizontalMargin.toStringAsFixed(0),
            onChanged: notifier.setHorizontalMargin,
          ),
          _slider(
            palette: palette,
            icon: Icons.brightness_6_outlined,
            label: 'Brillo',
            value: prefs.brightness ?? 0.5,
            min: 0.05,
            max: 1.0,
            display: prefs.brightness == null
                ? 'Sistema'
                : '${(prefs.brightness! * 100).round()}%',
            onChanged: (value) {
              notifier.setBrightness(value);
              onBrightnessChanged(value);
            },
            trailing: prefs.brightness == null
                ? null
                : _resetBrightnessButton(palette, notifier),
          ),
          const SizedBox(height: 4),
          _switchTile(
            palette: palette,
            icon: Icons.format_align_justify,
            label: 'Texto justificado',
            value: prefs.justify,
            onChanged: notifier.setJustify,
          ),
          _switchTile(
            palette: palette,
            icon: Icons.screen_lock_portrait_outlined,
            label: 'Mantener pantalla encendida',
            value: prefs.keepScreenOn,
            onChanged: notifier.setKeepScreenOn,
          ),
        ],
      ),
    );
  }

  Widget _resetBrightnessButton(ReaderPalette palette, ReaderPrefsNotifier notifier) {
    return IconButton(
      tooltip: 'Devolver el brillo al sistema',
      visualDensity: VisualDensity.compact,
      icon: Icon(Icons.restart_alt, size: 18, color: palette.foregroundAlpha(0.6)),
      onPressed: () {
        notifier.setBrightness(null);
        onBrightnessChanged(null);
      },
    );
  }

  Widget _label(String text, ReaderPalette palette) => Text(
        text,
        style: GoogleFonts.montserrat(
          color: palette.foregroundAlpha(0.6),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      );

  Widget _themeRow(WidgetRef ref, ReaderPalette palette, ReaderThemeMode current) {
    return Row(
      children: [
        for (final mode in ReaderThemeMode.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => ref.read(readerThemeProvider.notifier).setMode(mode),
                child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                    color: readerPaletteFor(mode).background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: mode == current
                          ? palette.foreground
                          : palette.foregroundAlpha(0.15),
                      width: mode == current ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Aa',
                    style: GoogleFonts.montserrat(
                      color: readerPaletteFor(mode).textColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _fontRow(WidgetRef ref, ReaderPalette palette, ReaderPrefs prefs) {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ReaderFontFamily.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final family = ReaderFontFamily.values[index];
          final selected = family == prefs.fontFamily;
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => ref.read(readerPrefsProvider.notifier).setFontFamily(family),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? palette.foreground : palette.foregroundAlpha(0.15),
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    family.fontName,
                    style: prefs
                        .copyWith(fontFamily: family, fontSize: 16, lineHeight: 1.2)
                        .textStyle(palette.foreground),
                  ),
                  Text(
                    family.description,
                    style: GoogleFonts.montserrat(
                      color: palette.foregroundAlpha(0.5),
                      fontSize: 10,
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

  Widget _slider({
    required ReaderPalette palette,
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 18, color: palette.foregroundAlpha(0.6)),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: GoogleFonts.montserrat(
                color: palette.foregroundAlpha(0.8),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: palette.foregroundAlpha(0.7),
                inactiveTrackColor: palette.foregroundAlpha(0.15),
                thumbColor: palette.foreground,
                overlayColor: palette.foregroundAlpha(0.1),
                trackHeight: 3,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 54,
            child: Text(
              display,
              textAlign: TextAlign.right,
              style: GoogleFonts.montserrat(
                color: palette.foregroundAlpha(0.6),
                fontSize: 11,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _switchTile({
    required ReaderPalette palette,
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: palette.foregroundAlpha(0.6)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.montserrat(
              color: palette.foregroundAlpha(0.8),
              fontSize: 13,
            ),
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: palette.foreground,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
