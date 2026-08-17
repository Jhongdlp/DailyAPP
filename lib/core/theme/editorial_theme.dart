import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'oklch.dart';

/// Sistema editorial plano — tres tonos, cero sombras.
///
/// Destilado de las referencias: negro cálido, crema tibia y un gris medio.
/// Nada más. Las reglas que lo sostienen:
///
///  1. **La inversión es la jerarquía.** Un plano se separa de otro por
///     contraste de área, no por sombra, borde ni gradiente. Una tarjeta crema
///     sobre lienzo negro ya salta sola; agregarle elevación la ensucia.
///  2. **La crema no es blanco y el negro no es negro.** Ambos tienen
///     temperatura. Ese medio paso fuera del gris puro es lo que separa
///     "diseñado" de "valor por defecto".
///  3. **Mayúsculas grandes y apretadas, nunca chicas y abiertas.** Un título
///     en caps a 30px con tracking cerrado se lee editorial; el mismo recurso a
///     8px con tracking abierto es lo que envejece una pantalla. Las versalitas
///     chicas existen, pero como etiqueta de tarjeta y de a una por bloque.
class EditorialTheme {
  EditorialTheme._();

  // ─── Los tres tonos ───
  //
  // La temperatura va cruzada, y ese cruce es lo que separa este editorial del
  // editorial de revista vieja: el negro tira frío y el papel tira cálido. La
  // versión anterior tenía los dos cálidos (#141412 sobre #F0EDE6) y el
  // conjunto se leía sepia, envejecido. Con el lienzo enfriado un paso y el
  // papel subido casi a blanco, el mismo sistema pasa a leerse actual sin
  // perder el carácter: la crema plana es lo que fecha una pantalla, no el
  // contraste.

  /// Lienzo. El gris casi negro de Notion en oscuro.
  static const Color canvas = Color(0xFF191919);

  /// Superficie elevada oscura: un escalón de luminosidad sobre el lienzo.
  ///
  /// Existe porque un panel pintado con [ink] es exactamente del color del
  /// fondo, y entonces sólo lo separa su filete: se lee como un agujero
  /// recortado, no como una pieza apoyada encima. Con un gris un paso más claro
  /// recupera volumen y el borde pasa a ser un remate, no el único recurso que
  /// lo sostiene.
  static const Color surface = Color(0xFF202020);

  /// Segundo escalón, para lo que se apoya sobre [surface] (chips dentro de un
  /// panel, fila presionada). Sin él, todo lo anidado tiene que recurrir a un
  /// borde.
  static const Color surfaceHigh = Color(0xFF2F2F2F);

  /// Tarjetas y paneles. Blanco de página.
  static const Color paper = Color(0xFFFFFFFF);

  /// Tinta sobre papel. **No es negro**, y ahí está media la diferencia: es un
  /// gris cálido oscuro. Un título en negro puro sobre blanco puro tiene tanto
  /// contraste que vibra y endurece toda la pantalla; bajarlo a este valor
  /// mantiene la legibilidad y quita el filo. Es el truco más barato de la
  /// escala de Notion y el que más se nota.
  static const Color ink = Color(0xFF37352F);

  /// Gris de relleno: el fondo de un bloque neutro sobre papel.
  ///
  /// Va como color literal y no como [ink] con alfa. Una tinta cálida diluida
  /// arrastra su propio tinte y a valores bajos el gris se ensucia hacia el
  /// beige; esta escala está hecha para leerse neutra a cualquier tamaño. La
  /// diferencia contra el papel es de sólo 14 niveles y es deliberada: el
  /// bloque tiene que leerse como superficie aparte sin convertirse en una
  /// mancha.
  static const Color gray = Color(0xFFF1F1EF);

  /// Un escalón más del mismo gris, para lo que se apoya sobre [gray] o para un
  /// filete que lo termine.
  static const Color grayStrong = Color(0xFFE9E9E7);

  /// Gris de texto secundario sobre papel.
  static const Color grayText = Color(0xFF787774);

  /// Tercer tono: gris medio para lo secundario que vive sobre el lienzo.
  static const Color muted = Color(0xFF979593);

  static Color inkAlpha(double a) => ink.withValues(alpha: a);
  static Color paperAlpha(double a) => paper.withValues(alpha: a);

  // ─── Acento del hábito ───

  static final Map<int, Color> _accentCache = {};

  /// Pone el color crudo de un hábito en el registro del sistema.
  ///
  /// El hex que el usuario eligió no se puede pintar tal cual: los acentos
  /// vienen de una paleta pensada para el diseño anterior y, a plena viveza,
  /// arrasan con un sistema de tres tonos. Se conserva **el hue** —que es lo
  /// que identifica al hábito— y se reescriben lightness y croma:
  ///
  ///  - **Lightness fijada por el fondo.** Un mismo hex no puede servir sobre
  ///    crema y sobre la tarjeta invertida: sobre `#141412` hay que ser claro y
  ///    sobre `#F0EDE6` hay que ser profundo. Por eso hay dos variantes y la
  ///    tarjeta interpola entre ellas junto con el resto de sus colores.
  ///  - **Croma al 95% de la cúspide del gamut.** Casi el punto más vivo que el
  ///    hue admite sin salirse de sRGB. El 5% que se recorta no se ve, pero
  ///    evita quedar pegado al borde del gamut, donde el recorte a sRGB tuerce
  ///    el hue y dos acentos vecinos empiezan a parecerse.
  static const double accentChromaRatio = 0.95;

  // La superficie de la tarjeta NO lleva el acento. Se probó teñirla hacia el
  // hue del hábito para darle marca, y el resultado es una pantalla de tarjetas
  // de colores que compite con el contraste crema/negro. El volumen lo da el
  // escalón de luminosidad (ver [surface]); el color vive en las piezas de
  // dentro —icono, círculo, cuadraditos—, donde señala estado en vez de teñir
  // superficie.

  static Color accent(Color raw, {required bool onDark}) =>
      accentAt(raw, onDark ? 0.80 : 0.54);

  /// Lightness fija = 0.62. Es el punto del bloque de color del icono: el más
  /// vivo que todavía sostiene un glifo blanco encima con contraste de lectura.
  /// Por debajo el bloque se apaga y deja de ser "la parte con color"; por
  /// encima el icono blanco empieza a desaparecer.
  static const double accentBlockLightness = 0.62;

  /// Misma receta que [accent] pero con la lightness a mano, para las piezas
  /// que no viven ni sobre el lienzo ni sobre el papel sino sobre el propio
  /// color (el bloque del icono y lo que se pinta encima de él).
  static Color accentAt(Color raw, double l) {
    final key = Object.hash(raw.toARGB32(), l);
    final cached = _accentCache[key];
    if (cached != null) return cached;

    final base = Oklch.fromColor(raw);
    final c = math.min(base.c, Oklch.cuspChroma(l, base.h) * accentChromaRatio);
    final result = Oklch(l, c, base.h).toColor();

    _accentCache[key] = result;
    return result;
  }

  // ─── Geometría ───

  static const double margin = 20;
  static const double gutter = 12;

  /// Separación horizontal entre los siete días. La comparten el selector y el
  /// mapa de calor, que es lo que mantiene sus columnas alineadas: lunes sobre
  /// lunes. Si cada uno usara la suya, la pieza se partiría en dos.
  static const double dayGap = 6;

  /// Radio de tarjeta y de panel. Generoso: en las referencias nada es
  /// cuadrado y nada es píldora salvo los botones.
  static const double radiusCard = 20;
  static const double radiusPanel = 26;
  static const double radiusChip = 12;

  // ─── Tipografía ───
  //
  // Outfit, la familia del tema. Dos registros: caps para títulos, caja normal
  // para todo lo demás.

  /// Título en mayúsculas. Tracking NEGATIVO — es lo que lo mantiene actual.
  static TextStyle caps(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color? color,
    double letterSpacing = -0.4,
    double? height,
  }) =>
      GoogleFonts.outfit(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  /// Etiqueta chica en versalitas. Usar de a una por tarjeta, nunca más.
  static TextStyle label(double size, {Color? color}) => GoogleFonts.outfit(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 1.1,
      );

  static TextStyle text(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color? color,
    double letterSpacing = -0.2,
    double? height,
  }) =>
      GoogleFonts.outfit(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  // ─── Movimiento ───

  static const Duration motion = Duration(milliseconds: 260);
  static const Curve curve = Curves.easeOutCubic;
}
