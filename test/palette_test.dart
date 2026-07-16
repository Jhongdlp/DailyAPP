import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistem_daily/core/theme/app_palette.dart';
import 'package:sistem_daily/core/theme/oklch.dart';

/// La promesa de la pantalla de personalizar es que NINGUNA elección del
/// usuario puede dejar la app ilegible. Estos tests la comprueban: si alguien
/// afina la banda de lightness o el umbral de contraste y rompe esa promesa,
/// aquí se entera.
void main() {
  group('Oklch', () {
    test('ida y vuelta a sRGB conserva el color', () {
      for (final color in [
        const Color(0xFFFD4800),
        const Color(0xFF05E079),
        const Color(0xFF212121),
        const Color(0xFFE0E5EC),
        const Color(0xFFFFFFFF),
        const Color(0xFF000000),
      ]) {
        final back = Oklch.fromColor(color).toColor();
        expect((back.r - color.r).abs(), lessThan(0.005), reason: '$color');
        expect((back.g - color.g).abs(), lessThan(0.005), reason: '$color');
        expect((back.b - color.b).abs(), lessThan(0.005), reason: '$color');
      }
    });

    test('la cúspide está dentro del gamut y un pelo más es salirse', () {
      for (var h = 0.0; h < 360; h += 30) {
        final c = Oklch.cuspChroma(0.7, h);
        expect(Oklch(0.7, c, h).inGamut, isTrue, reason: 'hue $h');
        expect(Oklch(0.7, c + 0.01, h).inGamut, isFalse, reason: 'hue $h');
      }
    });

    test('el croma mide viveza donde la saturación HSL engaña', () {
      // #FFE9E5 marca saturación HSL del 100% y es un rosa pastel: el croma
      // OkLCh lo delata. Es el motivo de que toda la paleta viva en OkLCh.
      final pastel = Oklch.fromColor(const Color(0xFFFFE9E5));
      final vivid = Oklch.fromColor(const Color(0xFFFD4800));
      expect(pastel.c, lessThan(0.05));
      expect(vivid.c, greaterThan(0.20));
    });
  });

  group('Acentos derivados', () {
    test('todos los presets contrastan ≥3:1 en los dos modos', () {
      for (final preset in AppPalettes.presets) {
        final palette = preset.resolve();
        for (final isDark in [true, false]) {
          final surface = AppPalettes.surfaces(null, isDark: isDark).surface;
          for (final accent in palette.forMode(isDark).all) {
            expect(
              contrastRatio(accent, surface),
              greaterThanOrEqualTo(3.0),
              reason: '${preset.name} / ${isDark ? "oscuro" : "claro"} / $accent',
            );
          }
        }
      }
    });

    test('cualquier semilla y esquema da acentos legibles', () {
      for (var seed = 0.0; seed < 360; seed += 15) {
        for (final scheme in PaletteScheme.values) {
          final palette = AppPalettes.derive(seed, scheme, null);
          for (final isDark in [true, false]) {
            final surface = AppPalettes.surfaces(null, isDark: isDark).surface;
            for (final accent in palette.forMode(isDark).all) {
              expect(
                contrastRatio(accent, surface),
                greaterThanOrEqualTo(3.0),
                reason: 'semilla $seed / ${scheme.value} / ${isDark ? "oscuro" : "claro"}',
              );
            }
          }
        }
      }
    });

    test('los acentos derivados son vivos, no pasteles', () {
      for (var seed = 0.0; seed < 360; seed += 45) {
        final palette = AppPalettes.derive(seed, PaletteScheme.spread, null);
        for (final accent in palette.dark.all) {
          expect(Oklch.fromColor(accent).c, greaterThan(0.09), reason: 'semilla $seed / $accent');
        }
      }
    });

    test('las pestañas de la rueda se distinguen entre sí', () {
      final tabs = AppPalettes.derive(25, PaletteScheme.spread, null).dark.tabs;
      for (var i = 0; i < tabs.length; i++) {
        for (var j = i + 1; j < tabs.length; j++) {
          final a = Oklch.fromColor(tabs[i]);
          final b = Oklch.fromColor(tabs[j]);
          var delta = (a.h - b.h).abs();
          if (delta > 180) delta = 360 - delta;
          expect(delta, greaterThan(30), reason: 'pestañas $i y $j casi del mismo hue');
        }
      }
    });
  });

  group('Material', () {
    test('sin tinte devuelve las superficies de fábrica', () {
      expect(AppPalettes.surfaces(null, isDark: true).surface, const Color(0xFF212121));
      expect(AppPalettes.surfaces(null, isDark: false).surface, const Color(0xFFE0E5EC));
    });

    test('el tinte conserva la claridad del material en todos los hues', () {
      // Es la garantía que sostiene el relieve: si la lightness se moviera, las
      // sombras neumórficas dejarían de funcionar.
      for (var h = 0.0; h < 360; h += 45) {
        final spec = MaterialSpec(hue: h, chroma: MaterialSpec.maxChroma);

        final dark = Oklch.fromColor(AppPalettes.surfaces(spec, isDark: true).surface);
        expect((dark.l - 0.267).abs(), lessThan(0.02), reason: 'hue $h oscuro');

        final light = Oklch.fromColor(AppPalettes.surfaces(spec, isDark: false).surface);
        expect((light.l - 0.911).abs(), lessThan(0.02), reason: 'hue $h claro');
      }
    });

    test('el texto contrasta ≥4.5:1 con su material en todos los hues', () {
      for (var h = 0.0; h < 360; h += 45) {
        final spec = MaterialSpec(hue: h, chroma: MaterialSpec.maxChroma);
        for (final isDark in [true, false]) {
          final s = AppPalettes.surfaces(spec, isDark: isDark);
          expect(
            contrastRatio(s.text, s.surface),
            greaterThanOrEqualTo(4.5),
            reason: 'hue $h / ${isDark ? "oscuro" : "claro"}',
          );
        }
      }
    });
  });
}
