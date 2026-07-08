import 'dart:math' as math;
import 'dart:ui' show ImageFilter, PointMode, BlurStyle;
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

  // Engineered Accents (Rich Jewel & Earth tones, optimized for dark-mode contrast, non-neon, non-pastel)
  static const Color accentHabits = Color(0xFFE07A5F);  // Burnt Terracotta
  static const Color accentBrain = Color(0xFF6E9B7B);   // Eucalyptus Sage
  static const Color accentAlarm = Color(0xFF758BFD);   // Rich Periwinkle
  static const Color accentFinance = Color(0xFFE2A04E); // Amber Gold
  static const Color accentChat = Color(0xFF5FA8D3);    // Slate Blue

  /// Texto crema con opacidad, para las jerarquías secundarias sobre fondo oscuro.
  static Color creamAlpha(double opacity) => cream.withValues(alpha: opacity);

  /// Texto secundario de alto contraste (subtítulos, metadatos).
  static Color get creamSecondary => creamAlpha(0.72);

  /// Texto terciario/deshabilitado (hints, placeholders).
  static Color get creamTertiary => creamAlpha(0.45);

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

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryDark,
      scaffoldBackgroundColor: darkBg,
      canvasColor: darkBg,
      cardColor: darkCard,
      dialogTheme: const DialogThemeData(
        backgroundColor: darkCard,
        surfaceTintColor: Colors.transparent,
      ),
      colorScheme: const ColorScheme.dark(
        primary: primaryDark,
        secondary: accentBlue,
        surface: darkCard,
        error: errorRed,
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        ThemeData.dark().textTheme.copyWith(
          titleLarge: const TextStyle(fontWeight: FontWeight.bold, color: cream),
          titleMedium: const TextStyle(fontWeight: FontWeight.w600, color: cream),
          titleSmall: const TextStyle(fontWeight: FontWeight.w600, color: cream),
          bodyLarge: const TextStyle(color: cream),
          bodyMedium: TextStyle(color: creamSecondary),
          bodySmall: TextStyle(color: creamSecondary),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkCardAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: creamAlpha(0.20), width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: creamAlpha(0.20), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: accentLime, width: 2),
        ),
        labelStyle: TextStyle(color: creamSecondary),
        hintStyle: TextStyle(color: creamTertiary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryDark,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cream,
          side: BorderSide(color: creamAlpha(0.20), width: 2),
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

/// Tarjeta Glassmorphic estilo iOS / iPhone con bordes delgados nítidos y desenfoque
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final double borderWidth;
  final double blurSigma;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.width,
    this.height,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = 20.0,
    this.borderWidth = 1.0, // Muy iPhone: bordes súper delgados y nítidos
    this.blurSigma = 15.0,  // Muy iPhone: desenfoque alto para mayor legibilidad
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary aísla el costo del BackdropFilter de cada tarjeta del
    // resto del árbol (fondo animado, tarjetas vecinas), sin afectar el
    // resultado visual: evita que tocar una tarjeta fuerce recomposición de
    // las demás y viceversa.
    final cardWidget = RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          children: [
            // Filtro de desenfoque de fondo
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
            // Contenedor de contenido con color translúcido de fondo y borde delgado plano
            Container(
              width: width,
              height: height,
              padding: padding ?? const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: backgroundColor ?? BentoTheme.darkCard.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(
                  color: borderColor ?? BentoTheme.creamAlpha(0.12),
                  width: borderWidth,
                ),
              ),
              child: child,
            ),
          ],
        ),
      ),
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

/// Wrapper compatible con el código anterior que redirige a AuroraBackground
class OrganicAnimatedBackground extends StatelessWidget {
  final Widget child;
  const OrganicAnimatedBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return AuroraBackground(
      showRadialGradient: true,
      child: child,
    );
  }
}

/// Fondo orgánico minimalista tipo "Organic Glass Shader" con líneas topográficas y blobs líquidos.
///
/// Diseñado para optimizar el efecto de glassmorphic (frosted glass) en las tarjetas de la app,
/// proporcionando variaciones de luz lentas y elegantes debajo de ellas sin saturar con degradados.
/// En las áreas descubiertas, dibuja líneas de contorno ultrafinas y orgánicas que se mueven
/// como fluido en cámara lenta.
class AuroraBackground extends StatefulWidget {
  final Widget child;
  final bool showRadialGradient;

  const AuroraBackground({
    super.key,
    required this.child,
    this.showRadialGradient = true,
  });

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40), // Movimiento aún más lento, elegante e hipnótico
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Forzamos a modo oscuro ya que el dashboard y la planeación están diseñados sobre la paleta oscura Bento.
    const isDarkMode = true;
    const baseBgColor = BentoTheme.darkBg;

    return Stack(
      children: [
        // 1. Capa animada de blobs y contornos orgánicos (diseño generativo similar a un shader de fragmentos).
        // El difuminado de las líneas topográficas ahora se aplica directamente a los
        // trazos dentro de _AuroraPainter (ver linePaint1/linePaint2), en vez de un
        // BackdropFilter de pantalla completa recalculado cada frame — mismo resultado
        // visual, mucho más barato porque el blur queda acotado a los trazos delgados
        // en vez de recomponer toda la pantalla en cada tick de la animación.
        // RepaintBoundary aísla los repaints continuos de esta capa (40s en loop,
        // para siempre) del resto del árbol (viñeta, ruido estático, y sobre todo
        // el contenido del dashboard), para que no se recompongan entre sí.
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _AuroraPainter(
                    animationValue: _controller.value,
                    isDarkMode: isDarkMode,
                    baseColor: baseBgColor,
                  ),
                );
              },
            ),
          ),
        ),
        // 2. Máscara de gradiente radial opcional (viñeta muy sutil para enfocar el contenido central)
        if (widget.showRadialGradient)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.2), // Centrado y sutil
                  radius: 1.5,
                  colors: [
                    Colors.transparent,
                    baseBgColor.withValues(alpha: 0.15),
                    baseBgColor.withValues(alpha: 0.45),
                    baseBgColor,
                  ],
                  stops: const [0.0, 0.5, 0.8, 1.0],
                ),
              ),
            ),
          ),
        // 3. Capa estática de ruido (grain) para textura orgánica tipo papel mate (sin movimiento)
        Positioned.fill(
          child: CustomPaint(
            painter: _NoiseBackgroundPainter(isDarkMode: isDarkMode),
          ),
        ),
        // 4. Capa interactiva de contenido
        Positioned.fill(
          child: widget.child,
        ),
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final double animationValue;
  final bool isDarkMode;
  final Color baseColor;

  _AuroraPainter({
    required this.animationValue,
    required this.isDarkMode,
    required this.baseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final double t = animationValue * 2 * math.pi;

    // 1. Dibujar el fondo base plano
    final Paint bgPaint = Paint()..color = baseColor;
    canvas.drawRect(rect, bgPaint);

    // Si el ancho o alto es cero, no dibujamos para evitar errores de división por cero
    if (size.width == 0 || size.height == 0) return;

    if (isDarkMode) {
      // --- CAPAS OSCURAS (Elegancia minimalista con tonos orgánicos apagados) ---
      
      // Blob 1: Verde Eucalipto (Representa mente/salud) - Posición superior izquierda
      _drawOrganicCell(
        canvas: canvas,
        size: size,
        t: t,
        cx: size.width * (0.28 + 0.08 * math.cos(t * 0.2)),
        cy: size.height * (0.35 + 0.06 * math.sin(t * 0.15)),
        radius: size.width * 0.32,
        color: BentoTheme.accentBrain.withValues(alpha: 0.016),
        lineColor: BentoTheme.accentBrain.withValues(alpha: 0.07),
        phaseShift: 0.0,
      );

      // Blob 2: Azul Suave / Periwinkle (Representa alarmas/tiempo) - Posición media derecha
      _drawOrganicCell(
        canvas: canvas,
        size: size,
        t: t,
        cx: size.width * (0.76 + 0.07 * math.sin(t * 0.12)),
        cy: size.height * (0.48 + 0.08 * math.cos(t * 0.18)),
        radius: size.width * 0.35,
        color: BentoTheme.accentBlue.withValues(alpha: 0.018),
        lineColor: BentoTheme.accentBlue.withValues(alpha: 0.07),
        phaseShift: 2.5,
      );

      // Blob 3: Terracota Cálido (Representa hábitos/acción) - Posición inferior centro
      _drawOrganicCell(
        canvas: canvas,
        size: size,
        t: t,
        cx: size.width * (0.48 + 0.08 * math.cos(t * 0.14)),
        cy: size.height * (0.74 + 0.06 * math.sin(t * 0.22)),
        radius: size.width * 0.30,
        color: BentoTheme.accentHabits.withValues(alpha: 0.014),
        lineColor: BentoTheme.accentHabits.withValues(alpha: 0.06),
        phaseShift: 4.8,
      );

    } else {
      // --- CAPAS CLARAS (Colores ultrafinos y limpios) ---
      
      _drawOrganicCell(
        canvas: canvas,
        size: size,
        t: t,
        cx: size.width * (0.30 + 0.06 * math.cos(t * 0.18)),
        cy: size.height * (0.38 + 0.05 * math.sin(t * 0.12)),
        radius: size.width * 0.30,
        color: BentoTheme.accentBlue.withValues(alpha: 0.015),
        lineColor: BentoTheme.accentBlue.withValues(alpha: 0.06),
        phaseShift: 0.0,
      );

      _drawOrganicCell(
        canvas: canvas,
        size: size,
        t: t,
        cx: size.width * (0.72 + 0.05 * math.sin(t * 0.15)),
        cy: size.height * (0.50 + 0.06 * math.cos(t * 0.20)),
        radius: size.width * 0.33,
        color: BentoTheme.accentPurple.withValues(alpha: 0.015),
        lineColor: BentoTheme.accentPurple.withValues(alpha: 0.06),
        phaseShift: 2.0,
      );
    }
  }

  /// Dibuja una célula/metaball orgánica fluida con su relleno difuminado y contornos concéntricos nítidos.
  void _drawOrganicCell({
    required Canvas canvas,
    required Size size,
    required double t,
    required double cx,
    required double cy,
    required double radius,
    required Color color,
    required Color lineColor,
    required double phaseShift,
  }) {
    // 1. Relleno con difuminado por GPU (MaskFilter) para simular emisión de luz suave
    final Paint fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 48.0);

    final Path fillPath = _getOrganicBlobPath(
      cx: cx,
      cy: cy,
      radius: radius,
      t: t,
      numPoints: 8,
      morphIntensity: 1.0,
      phaseShift: phaseShift,
    );
    canvas.drawPath(fillPath, fillPaint);

    // 2. Contorno principal nítido (línea topográfica). El difuminado suave
    // que antes daba un BackdropFilter de pantalla completa (recalculado cada
    // frame sobre toda la pantalla) ahora se aplica acá, solo a este trazo
    // delgado, con el mismo resultado visual mucho más barato.
    final Paint linePaint1 = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);

    canvas.drawPath(fillPath, linePaint1);

    // 3. Contorno secundario concéntrico (línea topográfica externa ligeramente desfasada)
    final Paint linePaint2 = Paint()
      ..color = lineColor.withValues(alpha: lineColor.alpha * 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);

    final Path outerPath = _getOrganicBlobPath(
      cx: cx,
      cy: cy,
      radius: radius * 1.12,
      t: t,
      numPoints: 8,
      morphIntensity: 1.08,
      phaseShift: phaseShift + 0.6, // desfasado para comportamiento líquido
    );
    canvas.drawPath(outerPath, linePaint2);
  }

  /// Genera un Path cerrado y perfectamente suavizado usando beziers cuadráticos a partir de puntos oscilantes.
  Path _getOrganicBlobPath({
    required double cx,
    required double cy,
    required double radius,
    required double t,
    required int numPoints,
    required double morphIntensity,
    required double phaseShift,
  }) {
    final Path path = Path();
    final List<Offset> points = [];

    for (int i = 0; i < numPoints; i++) {
      final double angle = (i * 2 * math.pi) / numPoints;

      // Interferencia de múltiples frecuencias armónicas para simular ruido simplex de forma ligera y determinista
      final double offset1 = math.sin(3 * angle + t + phaseShift) * 32.0 * morphIntensity;
      final double offset2 = math.cos(2 * angle - t * 0.7 + phaseShift * 1.4) * 18.0 * morphIntensity;
      final double offset3 = math.sin(5 * angle + t * 1.3) * 10.0 * morphIntensity;

      final double r = radius + offset1 + offset2 + offset3;
      final double x = cx + r * math.cos(angle);
      final double y = cy + r * math.sin(angle);
      points.add(Offset(x, y));
    }

    final int len = points.length;
    if (len == 0) return path;

    // Inicializamos el path en el punto medio entre el primer y último punto para asegurar continuidad total
    final double startX = (points[0].dx + points[len - 1].dx) / 2;
    final double startY = (points[0].dy + points[len - 1].dy) / 2;
    path.moveTo(startX, startY);

    for (int i = 0; i < len; i++) {
      final p0 = points[i];
      final p1 = points[(i + 1) % len];
      
      // El punto de destino es el punto medio entre p0 y p1, usando p0 como punto de control del bezier
      final xc = (p0.dx + p1.dx) / 2;
      final yc = (p0.dy + p1.dy) / 2;
      path.quadraticBezierTo(p0.dx, p0.dy, xc, yc);
    }

    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isDarkMode != isDarkMode ||
        oldDelegate.baseColor != baseColor;
  }
}

class _NoiseBackgroundPainter extends CustomPainter {
  final bool isDarkMode;

  _NoiseBackgroundPainter({required this.isDarkMode});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Dibujar ruido determinista fino (Fine Grain) para dar textura orgánica sin movimiento
    final Color grainColor = isDarkMode ? BentoTheme.cream : BentoTheme.primaryDark;

    // Lote 1: 2000 puntos ultrafinos (0.8px) con opacidad muy baja (1.5%)
    final Paint noisePaint1 = Paint()
      ..color = grainColor.withValues(alpha: 0.015)
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;

    final List<Offset> points1 = [];
    const int count1 = 2000;
    for (int i = 0; i < count1; i++) {
      final double x = (math.sin(i * 432.12) * 0.5 + 0.5) * size.width;
      final double y = (math.cos(i * 765.43) * 0.5 + 0.5) * size.height;
      points1.add(Offset(x, y));
    }
    canvas.drawPoints(PointMode.points, points1, noisePaint1);

    // Lote 2: 1200 puntos ligeramente mayores (1.2px) con opacidad sutil (2.4%)
    final Paint noisePaint2 = Paint()
      ..color = grainColor.withValues(alpha: 0.024)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final List<Offset> points2 = [];
    const int count2 = 1200;
    for (int i = 0; i < count2; i++) {
      final double x = (math.sin(i * 987.65) * 0.5 + 0.5) * size.width;
      final double y = (math.cos(i * 234.56) * 0.5 + 0.5) * size.height;
      points2.add(Offset(x, y));
    }
    canvas.drawPoints(PointMode.points, points2, noisePaint2);
  }

  @override
  bool shouldRepaint(covariant _NoiseBackgroundPainter oldDelegate) {
    return oldDelegate.isDarkMode != isDarkMode;
  }
}
