import 'dart:math' as math;
import 'dart:ui' show Color;

/// Color en el espacio OkLCh (lightness, croma, hue).
///
/// OkLCh es perceptualmente uniforme: a diferencia de HSL, su croma SÍ mide la
/// viveza real de un color y su lightness SÍ mide el brillo percibido. La
/// saturación HSL engaña — #FFE9E5 marca S=100% y es un rosa pastel — por eso
/// toda la generación de paletas de la app vive en este espacio y no en HSL.
class Oklch {
  /// Lightness percibida, 0 (negro) a 1 (blanco).
  final double l;

  /// Croma: distancia al gris. 0 = gris; el máximo depende del hue y de la
  /// lightness (la "cúspide" del gamut sRGB), y ronda 0.13–0.32.
  final double c;

  /// Hue en grados, 0–360.
  final double h;

  const Oklch(this.l, this.c, this.h);

  Oklch copyWith({double? l, double? c, double? h}) =>
      Oklch(l ?? this.l, c ?? this.c, h ?? this.h);

  // ─── sRGB → OkLCh ───

  static double _toLinear(double channel) => channel <= 0.04045
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

  static double _toGamma(double channel) => channel <= 0.0031308
      ? channel * 12.92
      : 1.055 * math.pow(channel, 1 / 2.4).toDouble() - 0.055;

  /// Raíz cúbica con signo: la conversión LMS→Oklab la aplica a valores que
  /// pueden ser negativos fuera del gamut, y `pow` no acepta base negativa.
  static double _cbrt(double x) =>
      x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();

  factory Oklch.fromColor(Color color) {
    final r = _toLinear(color.r);
    final g = _toLinear(color.g);
    final b = _toLinear(color.b);

    final lms0 = _cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    final lms1 = _cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    final lms2 = _cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);

    final lightness = 0.2104542553 * lms0 + 0.7936177850 * lms1 - 0.0040720468 * lms2;
    final a = 1.9779984951 * lms0 - 2.4285922050 * lms1 + 0.4505937099 * lms2;
    final bb = 0.0259040371 * lms0 + 0.7827717662 * lms1 - 0.8086757660 * lms2;

    final chroma = math.sqrt(a * a + bb * bb);
    var hue = math.atan2(bb, a) * 180 / math.pi;
    if (hue < 0) hue += 360;
    return Oklch(lightness, chroma, hue);
  }

  // ─── OkLCh → sRGB ───

  /// Canales lineales sin recortar. Fuera del gamut sRGB alguno sale <0 o >1;
  /// [inGamut] se apoya precisamente en eso.
  List<double> _linearRgb() {
    final rad = h * math.pi / 180;
    final a = c * math.cos(rad);
    final b = c * math.sin(rad);

    final lms0 = math.pow(l + 0.3963377774 * a + 0.2158037573 * b, 3).toDouble();
    final lms1 = math.pow(l - 0.1055613458 * a - 0.0638541728 * b, 3).toDouble();
    final lms2 = math.pow(l - 0.0894841775 * a - 1.2914855480 * b, 3).toDouble();

    return [
      4.0767416621 * lms0 - 3.3077115913 * lms1 + 0.2309699292 * lms2,
      -1.2684380046 * lms0 + 2.6097574011 * lms1 - 0.3413193965 * lms2,
      -0.0041960863 * lms0 - 0.7034186147 * lms1 + 1.7076147010 * lms2,
    ];
  }

  /// ¿Existe este color en sRGB? Con una tolerancia mínima para el ruido de
  /// coma flotante justo en el borde del gamut.
  bool get inGamut {
    const eps = 0.0001;
    return _linearRgb().every((v) => v >= -eps && v <= 1 + eps);
  }

  /// Convierte a Color recortando al gamut. Recortar tuerce el hue, así que
  /// para generar acentos hay que llegar aquí con un color ya dentro del gamut
  /// (ver [cuspChroma]) en vez de confiar en el recorte.
  Color toColor() {
    final rgb = _linearRgb()
        .map((v) => (_toGamma(v.clamp(0.0, 1.0)) * 255).round().clamp(0, 255))
        .toList();
    return Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);
  }

  /// Croma máximo que sRGB admite para esta lightness y este hue: la "cúspide"
  /// del gamut. Es el punto más vivo que ese hue puede alcanzar sin salirse del
  /// espacio de la pantalla, y es donde se sitúan todos los acentos de la app.
  ///
  /// Búsqueda binaria porque la frontera del gamut no tiene forma cerrada: es
  /// el poliedro RGB deformado por la transformación no lineal a Oklab.
  static double cuspChroma(double lightness, double hue) {
    var lo = 0.0;
    var hi = 0.4; // ningún hue de sRGB pasa de ~0.32
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      if (Oklch(lightness, mid, hue).inGamut) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

/// Ratio de contraste WCAG entre dos colores opacos (1:1 a 21:1).
///
/// Los acentos de la app son gráficos (iconos, barras, puntos), no texto, así
/// que el umbral que aplica es el 3:1 de WCAG 1.4.11 y no el 4.5:1 de texto.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}
