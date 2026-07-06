import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BentoTheme {
  // Paleta de colores solicitada por el usuario (Colores planos sin degradados)
  static const Color bgLight = Color(0xFFF7F7FF);      // Fondo general claro de la app
  static const Color primaryDark = Color(0xFF27187E);  // Color primario oscuro (azul profundo / índigo)
  static const Color cardBg = Color(0xFFFFFFFF);       // Fondo de tarjetas (blanco puro)
  static const Color borderMuted = Color(0xFFEAEBFF);   // Borde secundario/suave
  
  // Acentos de la paleta (Neon Indigo / Warm Orange flat)
  static const Color accentOrange = Color(0xFFFF8600); // Naranja brillante
  static const Color accentBlue = Color(0xFF758BFD);   // Azul medio/índigo suave
  static const Color accentPurple = Color(0xFF8A84E2); // Periwinkle/Púrpura
  
  // Colores de estado (planos)
  static const Color successGreen = Color(0xFF38B000); // Verde plano para éxitos
  static const Color errorRed = Color(0xFFD90429);    // Rojo plano para alarmas o borrado
  static const Color textPrimary = Color(0xFF27187E);  // Texto principal
  static const Color textSecondary = Color(0xFF5C5E7F); // Texto secundario

  // ─── Paleta oscura del rediseño (importado de Claude Design) ───
  static const Color darkBgTop = Color(0xFF101012);   // inicio del degradado de fondo
  static const Color darkBg = Color(0xFF0A0A0B);      // fondo general oscuro
  static const Color darkBlob = Color(0xFF1B1C1E);    // forma orgánica decorativa
  static const Color darkCard = Color(0xFF151517);    // tarjeta destacada (expandida)
  static const Color darkCardAlt = Color(0xFF141416); // fila compacta
  static const Color cream = Color(0xFFF5F3EE);       // texto principal sobre fondo oscuro
  static const Color accentLime = Color(0xFFC9F24E);  // acento de marca del rediseño

  /// Texto crema con opacidad, para las jerarquías secundarias sobre fondo oscuro.
  static Color creamAlpha(double opacity) => cream.withValues(alpha: opacity);

  /// Obtiene la configuración del tema de la aplicación (100% plano, moderno y Bento UI)
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryDark,
      scaffoldBackgroundColor: bgLight,
      colorScheme: const ColorScheme.light(
        primary: primaryDark,
        secondary: accentBlue,
        surface: cardBg,
        error: errorRed,
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        ThemeData.light().textTheme.copyWith(
          titleLarge: const TextStyle(fontWeight: FontWeight.bold, color: textPrimary),
          titleMedium: const TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
          titleSmall: const TextStyle(fontWeight: FontWeight.w600, color: textPrimary),
          bodyLarge: const TextStyle(color: textPrimary),
          bodyMedium: const TextStyle(color: textSecondary),
          bodySmall: const TextStyle(color: textSecondary),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderMuted, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: borderMuted, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryDark, width: 2),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: Colors.black38),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryDark,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: primaryDark, width: 2),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryDark,
          side: const BorderSide(color: primaryDark, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}

/// Contenedor Bento para estructurar la UI en bloques limpios y planos
class BentoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final double borderWidth;
  final VoidCallback? onTap;

  const BentoCard({
    super.key,
    required this.child,
    this.padding,
    this.width,
    this.height,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = 20.0, // Bento UI suele usar esquinas bien redondeadas
    this.borderWidth = 2.0, // Borde marcado para estilo flat-moderno
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardWidget = Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: backgroundColor ?? BentoTheme.cardBg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? BentoTheme.borderMuted,
          width: borderWidth,
        ),
      ),
      child: child,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: cardWidget,
      );
    }

    return cardWidget;
  }
}

/// Fondo limpio de color plano para las pantallas principales
class BentoBackground extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;

  const BentoBackground({
    super.key,
    required this.child,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor ?? BentoTheme.bgLight,
      body: SafeArea(
        child: child,
      ),
    );
  }
}
