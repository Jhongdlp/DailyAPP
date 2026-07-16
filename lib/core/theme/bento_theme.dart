import 'dart:math' as math;
import 'dart:ui' show PointMode, BlurStyle;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_palette.dart';

class BentoTheme {
  // ─── Modo de tema (claro/oscuro) ───
  // Fuente de verdad global del modo actual. main.dart lo sincroniza con el
  // themeModeProvider antes de construir el árbol; todos los getters de color
  // de abajo resuelven contra este flag, así que cualquier pantalla que use
  // BentoTheme.* se adapta al modo sin cambios propios.
  static final ValueNotifier<bool> darkMode = ValueNotifier(true);
  static bool get isDark => darkMode.value;

  // ─── Neumorfismo / Skeuomorph moderno ───
  // La luz virtual siempre viene de arriba-izquierda: sombra clara arriba-izq,
  // sombra oscura abajo-der. Si esa dirección se invierte en algún widget, la
  // pieza deja de leerse como extruida y rompe la ilusión en toda la pantalla.
  //
  // Regla de material: fondo y piezas comparten EXACTAMENTE la misma
  // superficie; solo las sombras separan los planos. Nada de transparencias.

  // ─── Apariencia activa ───
  //
  // Ni las superficies ni los acentos son ya hexes fijos: los elige el usuario
  // en la pantalla de personalizar. Estos campos son la apariencia RESUELTA
  // (colores ya calculados) y los sincroniza main.dart con appearanceProvider
  // antes de construir el árbol, igual que hace con darkMode.
  //
  // Se guardan como campos estáticos planos y no como ValueNotifier porque el
  // remonte lo dispara la Key de main.dart: media app son widgets const que
  // leen estos getters y no se reconstruirían por escuchar nada.
  static NeuSurfaces _darkSurfaces = AppPalettes.surfaces(null, isDark: true);
  static NeuSurfaces _lightSurfaces = AppPalettes.surfaces(null, isDark: false);
  static ResolvedPalette _palette = AppPalettes.presetById('vivid')!.resolve();

  /// Instala la apariencia elegida. Llamar ANTES de construir cualquier widget
  /// que lea estos colores.
  static void applyAppearance(ResolvedPalette palette, MaterialSpec? material) {
    _palette = palette;
    _darkSurfaces = AppPalettes.surfaces(material, isDark: true);
    _lightSurfaces = AppPalettes.surfaces(material, isDark: false);
  }

  /// Superficies del modo actual.
  static NeuSurfaces get _neu => isDark ? _darkSurfaces : _lightSurfaces;

  /// Acentos del modo actual.
  static AccentSet get accents => _palette.forMode(isDark);

  /// Superficie única del material (fondo, tarjetas, barras: todo es la misma pieza).
  static Color get neuSurface => _neu.surface;

  /// Base de los huecos (elementos hundidos/presionados), un paso más oscura.
  static Color get neuSurfaceSunken => _neu.sunken;

  /// Sombra proyectada (abajo-derecha).
  static Color get neuShadowDark => _neu.shadowDark;

  /// Luz reflejada (arriba-izquierda).
  static Color get neuShadowLight => _neu.shadowLight;

  /// Sombras de una pieza extruida (que sobresale del fondo).
  ///
  /// Dos capas por lado: la sombra de CONTACTO (corta, densa, pegada a la
  /// pieza) y la AMBIENTAL (larga, difusa). Una sola sombra por lado se lee
  /// como sticker plano; la pareja es lo que hace que la pieza "toque" la
  /// superficie de verdad.
  static List<BoxShadow> neuRaised({double distance = 6, double blur = 12}) => [
        // ambiental oscura (lejos, difusa)
        BoxShadow(
          color: neuShadowDark.withValues(alpha: isDark ? 0.75 : 0.55),
          offset: Offset(distance, distance),
          blurRadius: blur,
        ),
        // contacto oscura (pegada, densa)
        BoxShadow(
          color: neuShadowDark,
          offset: Offset(distance * 0.45, distance * 0.45),
          blurRadius: blur * 0.4,
        ),
        // ambiental clara
        BoxShadow(
          color: neuShadowLight.withValues(alpha: isDark ? 0.65 : 0.85),
          offset: Offset(-distance, -distance),
          blurRadius: blur,
        ),
        // contacto clara
        BoxShadow(
          color: neuShadowLight,
          offset: Offset(-distance * 0.45, -distance * 0.45),
          blurRadius: blur * 0.4,
        ),
      ];

  /// Sombra de una pieza que flota SOBRE la superficie (modales, sheets,
  /// diálogos) en vez de estar extruida de ella.
  ///
  /// [neuRaised] no vale aquí: su lóbulo claro arriba-izquierda simula el
  /// brillo de la superficie VECINA, y un modal recortado contra el scrim no
  /// tiene vecina — el lóbulo se queda flotando en el aire y se lee como un
  /// halo. Una pieza suspendida solo proyecta sombra, y con la luz arriba-
  /// izquierda cae hacia abajo-derecha. Tres lóbulos (contacto, media,
  /// ambiental) porque una sola sombra plana no da sensación de altura.
  static List<BoxShadow> neuFloating({double elevation = 16}) => [
        // contacto: corta y densa, ancla la pieza sobre lo que tapa
        BoxShadow(
          color: neuShadowDark.withValues(alpha: isDark ? 0.55 : 0.28),
          offset: Offset(elevation * 0.10, elevation * 0.18),
          blurRadius: elevation * 0.35,
        ),
        // media: el grueso de la penumbra
        BoxShadow(
          color: neuShadowDark.withValues(alpha: isDark ? 0.42 : 0.20),
          offset: Offset(elevation * 0.24, elevation * 0.50),
          blurRadius: elevation,
        ),
        // ambiental: larga y difusa, es la que comunica la altura
        BoxShadow(
          color: neuShadowDark.withValues(alpha: isDark ? 0.30 : 0.12),
          offset: Offset(elevation * 0.40, elevation * 0.90),
          blurRadius: elevation * 2.2,
        ),
      ];

  /// Gradiente de la CARA de una pieza (sombreado de material, no decoración):
  /// una superficie convexa recibe más luz arriba-izquierda y se oscurece en
  /// diagonal. `concavity` interpola hacia la cara cóncava (0 = convexa,
  /// 1 = cóncava/hundida) — al presionar una pieza se anima entre ambas.
  static Gradient neuFaceGradient(Color surface, {double concavity = 0}) {
    final double lift = isDark ? 0.30 : 0.45;
    final double drop = isDark ? 0.35 : 0.28;
    final Color lit = Color.lerp(surface, neuShadowLight, lift)!;
    final Color shaded = Color.lerp(surface, neuShadowDark, drop)!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(lit, shaded, concavity)!,
        surface,
        Color.lerp(shaded, lit, concavity)!,
      ],
      stops: const [0.0, 0.55, 1.0],
    );
  }

  // ─── Acentos ───
  //
  // Los acentos salen de la paleta activa, que el usuario elige en la pantalla
  // de personalizar (preset o derivada de una semilla). Sea cual sea, todos se
  // generan con la misma máquina — ver `app_palette.dart` y `oklch.dart`:
  // cúspide del gamut sRGB del hue dentro de la banda de lightness del modo,
  // con contraste ≥3:1 contra la superficie real.
  //
  // Un acento NO puede ser un único hex para los dos modos: sobre #212121 hay
  // que ser claro y sobre #E0E5EC hay que ser profundo. Por eso una paleta son
  // siempre dos AccentSet y estos getters resuelven contra el modo actual.

  /// Pestaña de hábitos.
  static Color get accentHabits => accents.habits;

  /// Pestaña de notas / segundo cerebro.
  static Color get accentBrain => accents.brain;

  /// Pestaña de alarma.
  static Color get accentAlarm => accents.alarm;

  /// Pestaña de finanzas.
  static Color get accentFinance => accents.finance;

  /// Pestaña de chat / copiloto.
  static Color get accentChat => accents.chat;

  /// Acento de marca.
  static Color get accentLime => accents.lime;

  /// Acento auxiliar (categorías de finanzas, hábitos).
  static Color get accentOrange => accents.orange;

  /// Acento auxiliar (categorías de finanzas, prioridades de notas).
  static Color get accentPurple => accents.purple;

  /// Alias explícito de [accentAlarm], que en la paleta de fábrica era
  /// literalmente el mismo hex; mejor un alias que dos valores que hay que
  /// recordar sincronizar.
  static Color get accentBlue => accentAlarm;

  // Colores de estado.
  //
  // NO son personalizables a propósito: "correcto" y "error" son significado,
  // no estilo. Si el verde de éxito pudiera girar a rojo con una paleta, un
  // ingreso y un gasto se leerían igual.
  static const Color successGreen = Color(0xFF38B000);
  static const Color errorRed = Color(0xFFD90429);

  // ─── Alias heredados (código pre-rediseño) ───
  // Todos resuelven a la superficie/texto del modo actual para que las
  // pantallas existentes se vuelvan neumórficas y sensibles al modo sin tocar
  // cada archivo. No usar en código nuevo: preferir neuSurface/neuText.
  static Color get bgLight => neuSurface;
  static Color get cardBg => neuSurface;
  static Color get borderMuted => neuShadowLight;
  static Color get primaryDark => isDark ? _darkSurfaces.text : const Color(0xFF27187E);
  static Color get textPrimary => neuText;
  static Color get textSecondary => neuText.withValues(alpha: 0.72);
  static Color get darkBgTop => neuSurface;
  static Color get darkBg => neuSurface;
  static Color get darkBlob => neuSurface;
  static Color get darkCard => neuSurface;
  static Color get darkCardAlt => neuSurfaceSunken;

  /// Texto principal del modo actual.
  static Color get neuText => _neu.text;

  /// Alias heredado: "cream" era el texto principal del modo oscuro.
  static Color get cream => neuText;

  /// Texto con opacidad, para las jerarquías secundarias.
  static Color creamAlpha(double opacity) => neuText.withValues(alpha: opacity);

  /// Texto secundario de alto contraste (subtítulos, metadatos).
  static Color get creamSecondary => creamAlpha(0.72);

  /// Texto terciario/deshabilitado (hints, placeholders).
  static Color get creamTertiary => creamAlpha(0.45);

  /// Tema claro neumórfico.
  static ThemeData get lightTheme => _buildTheme(
        brightness: Brightness.light,
        surface: _lightSurfaces.surface,
        sunken: _lightSurfaces.sunken,
        text: _lightSurfaces.text,
        accent: _palette.light.lime,
      );

  /// Tema oscuro neumórfico.
  static ThemeData get darkTheme => _buildTheme(
        brightness: Brightness.dark,
        surface: _darkSurfaces.surface,
        sunken: _darkSurfaces.sunken,
        text: _darkSurfaces.text,
        accent: _palette.dark.lime,
      );

  /// Ambos modos comparten la misma anatomía: superficie única, inputs
  /// hundidos sin borde (el hueco lo dibujan las sombras interiores de
  /// NeuPressed en pantallas rediseñadas; el fill oscuro es el fallback
  /// para inputs de Material sin envolver).
  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color surface,
    required Color sunken,
    required Color text,
    required Color accent,
  }) {
    final base = brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light();
    final secondaryText = text.withValues(alpha: 0.72);
    final tertiaryText = text.withValues(alpha: 0.45);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      primaryColor: text,
      scaffoldBackgroundColor: surface,
      canvasColor: surface,
      cardColor: surface,
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: text,
        onPrimary: surface,
        secondary: accentBlue,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: text,
        error: errorRed,
        onError: Colors.white,
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        base.textTheme.copyWith(
          titleLarge: TextStyle(fontWeight: FontWeight.bold, color: text),
          titleMedium: TextStyle(fontWeight: FontWeight.w600, color: text),
          titleSmall: TextStyle(fontWeight: FontWeight.w600, color: text),
          bodyLarge: TextStyle(color: text),
          bodyMedium: TextStyle(color: secondaryText),
          bodySmall: TextStyle(color: secondaryText),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: sunken,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        labelStyle: TextStyle(color: secondaryText),
        hintStyle: TextStyle(color: tertiaryText),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: surface,
          foregroundColor: text,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: text.withValues(alpha: 0.20), width: 2),
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
    // Delegado en NeuCard: un solo camino de renderizado neumórfico para toda
    // la app (sombras en capas, cara convexa, bisel y física de presión). El
    // borde solo se dibuja si el llamador pasó un borderColor explícito
    // (resaltes de selección); un borde por defecto rompería la ilusión.
    return NeuCard(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(20),
      borderRadius: borderRadius,
      distance: 5,
      blur: 10,
      color: backgroundColor,
      borderColor: borderColor,
      borderWidth: borderWidth,
      onTap: onTap,
      child: child,
    );
  }
}

/// Fondo limpio de color plano para las pantallas principales
class BentoBackground extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;

  /// Apagar cuando la pantalla tiene una pieza anclada al borde inferior que
  /// debe extenderse por debajo de la barra de gestos del sistema; entonces el
  /// hijo se encarga del inset con `MediaQuery.viewPadding.bottom`.
  final bool bottomSafeArea;

  const BentoBackground({
    super.key,
    required this.child,
    this.backgroundColor,
    this.bottomSafeArea = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor ?? BentoTheme.bgLight,
      body: SafeArea(
        bottom: bottomSafeArea,
        child: child,
      ),
    );
  }
}

/// Antes glassmorphic (blur + transparencia); ahora es una pieza neumórfica
/// sólida. Se mantiene el nombre y la firma para no tocar cada call site:
/// `blurSigma` se ignora y `backgroundColor` translúcidos se funden sobre la
/// superficie para conservar el tinte que cada pantalla le daba.
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
    return NeuCard(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(20),
      borderRadius: borderRadius,
      distance: 5,
      blur: 10,
      color: backgroundColor,
      borderColor: borderColor,
      borderWidth: borderWidth,
      onTap: onTap,
      child: child,
    );
  }
}

/// Pieza extruida estilo neumórfico / skeuomorph moderno.
///
/// Tres detalles de realismo además de las sombras duales en capas:
/// - Cara convexa: microgradiente diagonal (la luz baña más arriba-izquierda).
/// - Bisel especular: línea de ~1px que simula el chaflán redondeado del
///   borde atrapando la luz (clave del realismo en modo oscuro).
/// - Física de presión: si es tocable, al presionar las sombras colapsan, la
///   cara pasa de convexa a cóncava y la pieza se desplaza hacia su sombra.
class NeuCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final double borderRadius;

  /// Esquinas desiguales (p.ej. una pieza que nace del borde de la pantalla y
  /// solo redondea arriba). Tiene prioridad sobre [borderRadius].
  final BorderRadius? radius;

  final double distance;
  final double blur;

  /// Altura a la que la pieza flota SOBRE la superficie. Si es `null` (lo
  /// normal) la pieza está extruida de la superficie: sombras duales
  /// ([neuRaised]) y bisel especular. Si se da, la pieza está suspendida
  /// (modal, sheet, diálogo): solo proyecta sombra ([neuFloating]) y pierde el
  /// bisel, que sin superficie vecina se leería como un halo luminoso.
  final double? elevation;

  /// Tinte que se funde sobre la superficie del material (puede llevar alpha).
  final Color? color;

  /// Resalte explícito (p.ej. selección con color de acento).
  final Color? borderColor;
  final double borderWidth;

  /// Cara convexa con gradiente; apagar para superficies totalmente planas.
  final bool convex;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const NeuCard({
    super.key,
    required this.child,
    this.padding,
    this.width,
    this.height,
    this.borderRadius = 24.0,
    this.radius,
    this.distance = 6.0,
    this.blur = 12.0,
    this.elevation,
    this.color,
    this.borderColor,
    this.borderWidth = 1.5,
    this.convex = true,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<NeuCard> createState() => _NeuCardState();
}

class _NeuCardState extends State<NeuCard> {
  bool _pressed = false;

  bool get _tappable => widget.onTap != null || widget.onLongPress != null;

  @override
  Widget build(BuildContext context) {
    final Color surface = widget.color == null
        ? BentoTheme.neuSurface
        : Color.alphaBlend(widget.color!, BentoTheme.neuSurface);
    final BorderRadius radius =
        widget.radius ?? BorderRadius.circular(widget.borderRadius);

    final card = TweenAnimationBuilder<double>(
      tween: Tween(end: _pressed ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: Padding(
        padding: widget.padding ?? const EdgeInsets.all(20),
        child: widget.child,
      ),
      builder: (context, t, child) {
        // Al hundirse, la pieza pierde altura: sombras más cortas y densas,
        // y un desplazamiento físico de ~1.5px hacia donde caía su sombra.
        final double d = widget.distance * (1.0 - 0.78 * t);
        final double b = widget.blur * (1.0 - 0.55 * t);
        // Una pieza suspendida no se hunde: se acerca a lo que tapa.
        final double e = (widget.elevation ?? 0) * (1.0 - 0.55 * t);
        final bool floating = widget.elevation != null;
        return Transform.translate(
          offset: Offset(1.5 * t, 1.5 * t),
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: widget.convex ? null : surface,
              gradient: widget.convex
                  ? BentoTheme.neuFaceGradient(surface, concavity: t)
                  : null,
              borderRadius: radius,
              border: widget.borderColor == null
                  ? null
                  : Border.all(color: widget.borderColor!, width: widget.borderWidth),
              boxShadow: floating
                  ? BentoTheme.neuFloating(elevation: e)
                  : BentoTheme.neuRaised(distance: d, blur: b),
            ),
            child: CustomPaint(
              foregroundPainter: floating
                  ? null
                  : _NeuBevelPainter(
                      radius: radius,
                      concavity: t,
                      isDark: BentoTheme.isDark,
                    ),
              child: child,
            ),
          ),
        );
      },
    );

    if (!_tappable) return card;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: card,
    );
  }
}

/// Bisel especular: el chaflán redondeado del borde de una pieza atrapa la
/// luz — línea fina clara arriba-izquierda y oscura abajo-derecha. Con
/// `concavity` la dirección se invierte (el borde de un hueco se ilumina al
/// revés).
class _NeuBevelPainter extends CustomPainter {
  final BorderRadius radius;
  final double concavity;
  final bool isDark;

  _NeuBevelPainter({
    required this.radius,
    required this.concavity,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(0.75);
    final rrect = radius.toRRect(Offset.zero & size).deflate(0.75);

    final Color lit = BentoTheme.neuShadowLight
        .withValues(alpha: isDark ? 0.45 : 0.95);
    final Color shaded = BentoTheme.neuShadowDark
        .withValues(alpha: isDark ? 0.55 : 0.35);

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(lit, shaded, concavity)!,
          Colors.transparent,
          Color.lerp(shaded, lit, concavity)!,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);

    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _NeuBevelPainter old) {
    return old.radius != radius ||
        old.concavity != concavity ||
        old.isDark != isDark;
  }
}

/// Hueco neumórfico: la pieza se ve hundida dentro de la superficie.
///
/// CSS lo resolvería con `box-shadow: inset ...`, que Flutter no tiene, así que
/// las sombras interiores se pintan encima del contenido con un painter propio.
class NeuPressed extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final double distance;
  final double blur;
  final Color? color;
  final double intensity;

  const NeuPressed({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 16.0,
    this.distance = 3.0,
    this.blur = 6.0,
    this.color,
    this.intensity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    // El fondo de un hueco también tiene sombreado de material: cara cóncava
    // (más oscura hacia arriba-izquierda, donde la pared bloquea la luz) y
    // bisel invertido en el labio del borde.
    final Color base = color ?? BentoTheme.neuSurfaceSunken;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: BentoTheme.neuFaceGradient(base, concavity: 1),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: CustomPaint(
        foregroundPainter: _NeuInnerShadowPainter(
          borderRadius: borderRadius,
          distance: distance,
          blur: blur,
          intensity: intensity,
        ),
        child: CustomPaint(
          foregroundPainter: _NeuBevelPainter(
            radius: BorderRadius.circular(borderRadius),
            concavity: 1,
            isDark: BentoTheme.isDark,
          ),
          child: Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _NeuInnerShadowPainter extends CustomPainter {
  final double borderRadius;
  final double distance;
  final double blur;
  final double intensity;

  _NeuInnerShadowPainter({
    required this.borderRadius,
    required this.distance,
    required this.blur,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(borderRadius),
    );

    canvas.save();
    canvas.clipRRect(rrect);

    // Cada sombra interior es el "negativo" de la forma desplazada: se rellena
    // todo menos la forma, y el recorte de arriba deja ver solo la banda que
    // entra por el borde. Sin el clip, esto pintaría sobre la pantalla entera.
    void drawInner(Color color, Offset shift) {
      final path = Path()
        ..addRect(Rect.fromLTRB(-size.width, -size.height, size.width * 2, size.height * 2))
        ..addRRect(rrect.shift(shift))
        ..fillType = PathFillType.evenOdd;

      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
      );
    }

    // Luz desde arriba-izquierda: el borde superior-izquierdo queda en sombra
    // oscura y el inferior-derecho recibe el rebote claro — exactamente al
    // revés que una pieza extruida.
    drawInner(BentoTheme.neuShadowDark.withValues(alpha: 0.9 * intensity), Offset(distance, distance));
    drawInner(BentoTheme.neuShadowLight.withValues(alpha: 0.55 * intensity), Offset(-distance, -distance));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NeuInnerShadowPainter old) {
    return old.borderRadius != borderRadius ||
        old.distance != distance ||
        old.blur != blur ||
        old.intensity != intensity;
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

/// Fondo neumórfico: superficie sólida única del material del modo actual.
///
/// El neumorfismo exige que fondo y piezas sean el mismo material — nada de
/// degradados, blobs animados ni viñetas translúcidas. Solo se conserva una
/// capa estática de grano finísimo (textura de material mate, coherente con
/// el skeuomorph). `showRadialGradient` se mantiene en la firma por
/// compatibilidad pero ya no dibuja nada.
class AuroraBackground extends StatelessWidget {
  final Widget child;
  final bool showRadialGradient;

  const AuroraBackground({
    super.key,
    required this.child,
    this.showRadialGradient = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: BentoTheme.neuSurface),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _NoiseBackgroundPainter(isDarkMode: BentoTheme.isDark),
          ),
        ),
        Positioned.fill(
          child: child,
        ),
      ],
    );
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
