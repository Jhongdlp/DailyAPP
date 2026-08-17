import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sistema de diseño minimalista — piloto en la pestaña de Hábitos.
///
/// Deliberadamente NO toca [BentoTheme]: mientras se prueba el lenguaje sobre
/// una sola pantalla, conviven los dos sistemas sin interferirse. Si el piloto
/// convence, esto se convierte en el skin y BentoTheme pasa a delegar aquí.
///
/// Tres reglas que gobiernan todo lo de abajo:
///
///  1. Nunca blanco puro sobre negro puro. El blanco puro sobre negro absoluto
///     produce halación (el texto parece derramarse), notoriamente peor con
///     astigmatismo, y en OLED el scroll arrastra. Off-white sobre off-black
///     elimina las dos cosas.
///  2. La jerarquía sale de la escalera de opacidad + el peso, casi nunca de
///     saltos de tamaño. Cuatro niveles de etiqueta y ninguno más.
///  3. Elevación = un escalón de luminosidad. Cero sombras, cero bordes, cero
///     gradientes.
class MinimalTheme {
  MinimalTheme._();

  // ─── Superficies ───

  /// Lienzo. Off-black, no #000.
  static const Color canvas = Color(0xFF111113);

  /// Grupo elevado. Un escalón de luminosidad sobre el lienzo: eso ES la
  /// elevación, no hay sombra que la acompañe.
  static const Color surface = Color(0xFF1A1A1D);

  /// Fila bajo el dedo.
  static const Color surfacePressed = Color(0xFF232327);

  /// Tinta. Off-white; ver regla 1.
  static const Color _ink = Color(0xFFF5F5F7);

  // ─── Escalera de etiqueta ───
  // Estos cuatro niveles son TODA la jerarquía de color de la interfaz.

  static const Color label = _ink;
  static Color get secondaryLabel => _ink.withValues(alpha: 0.60);
  static Color get tertiaryLabel => _ink.withValues(alpha: 0.38);
  static Color get quaternaryLabel => _ink.withValues(alpha: 0.22);

  /// Filete separador. Va ENTRADO hasta el texto, nunca al borde del grupo.
  static Color get separator => _ink.withValues(alpha: 0.12);

  /// Relleno de pistas vacías (fondo de una barra de progreso, celda sin dato).
  static Color get fill => _ink.withValues(alpha: 0.08);

  // ─── Geometría ───

  static const double margin = 20;
  static const double groupRadius = 14;
  static const double rowHeight = 56;

  /// Diámetro del control de completar.
  static const double controlSize = 24;

  /// Separación entre el control y el texto.
  static const double controlGap = 14;

  /// Inset del separador: alineado al texto de la fila. Este detalle es el que
  /// hace que una lista se lea como nativa y no como una tabla.
  static const double separatorInset = margin + controlSize + controlGap;

  // ─── Tipografía ───
  //
  // Inter, no SF: la licencia de SF Pro la restringe a plataformas Apple y no
  // se puede embeber en una app Flutter. Inter está construida con la misma
  // lógica (grotesca neutra hecha para UI, con cifras tabulares).
  //
  // Solo dos pesos en toda la app: Regular y Semibold.

  static TextStyle _inter(
    double size,
    FontWeight weight,
    double tracking,
    double height, {
    bool tabular = false,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        letterSpacing: tracking,
        height: height,
        color: label,
        fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
      );

  static TextStyle get largeTitle => _inter(34, FontWeight.w600, -0.8, 1.2);
  static TextStyle get title => _inter(22, FontWeight.w600, -0.4, 1.25);
  static TextStyle get body => _inter(17, FontWeight.w400, -0.2, 1.3);
  static TextStyle get bodyEmphasis => _inter(17, FontWeight.w600, -0.2, 1.3);
  static TextStyle get callout => _inter(15, FontWeight.w400, -0.1, 1.35);
  static TextStyle get footnote => _inter(13, FontWeight.w400, 0, 1.4);
  static TextStyle get caption => _inter(11, FontWeight.w400, 0.1, 1.4);

  /// Cifras tabulares: sin esto los números bailan al actualizarse y la lista
  /// tiembla. Obligatorio en todo lo que sea dato.
  static TextStyle get numeric => _inter(15, FontWeight.w400, 0, 1.35, tabular: true);

  // ─── Movimiento ───
  //
  // Solo opacidad y traslación corta. Sin resortes, sin rebote, sin escala:
  // el movimiento explica de dónde vino algo, nunca celebra.

  static const Duration motion = Duration(milliseconds: 250);
  static const Curve motionCurve = Curves.easeOutCubic;
}
