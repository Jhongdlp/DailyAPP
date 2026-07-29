import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Modo de lectura, independiente del tema general de la app: quien lee de
/// noche con la app en claro (o al revés) no debería tener que cambiar el
/// tema de toda la app solo para leer cómodo.
enum ReaderThemeMode {
  light,
  sepia,
  dark,
  black;

  static ReaderThemeMode fromName(String? name) => ReaderThemeMode.values.firstWhere(
        (m) => m.name == name,
        orElse: () => ReaderThemeMode.light,
      );
}

class ReaderPalette {
  final Color background;
  final Color surface;
  final Color foreground;

  /// Color del cuerpo de texto del EPUB. Se aplica vía `TextStyle`, no con un
  /// filtro de color: filtrar el subárbol también invertiría las ilustraciones
  /// y portadas incrustadas en el libro.
  final Color textColor;

  /// Color de los fragmentos resaltados sobre este fondo.
  final Color highlight;

  /// Filtro aplicado solo al PDF, donde la página es un bitmap y no hay forma
  /// de recolorear el texto: ahí invertir es el único modo oscuro posible.
  final ColorFilter? pdfFilter;

  const ReaderPalette({
    required this.background,
    required this.surface,
    required this.foreground,
    required this.textColor,
    required this.highlight,
    this.pdfFilter,
  });

  Color foregroundAlpha(double alpha) => foreground.withValues(alpha: alpha);
}

const _invertMatrix = <double>[
  -1, 0, 0, 0, 255, //
  0, -1, 0, 0, 255, //
  0, 0, -1, 0, 255, //
  0, 0, 0, 1, 0, //
];

const _sepiaMatrix = <double>[
  0.85, 0.35, 0.10, 0, 20, //
  0.30, 0.75, 0.10, 0, 20, //
  0.20, 0.30, 0.55, 0, 20, //
  0, 0, 0, 1, 0, //
];

ReaderPalette readerPaletteFor(ReaderThemeMode mode) {
  switch (mode) {
    case ReaderThemeMode.light:
      return const ReaderPalette(
        background: Color(0xFFFAFAF7),
        surface: Color(0xFFFFFFFF),
        foreground: Color(0xFF20202A),
        textColor: Color(0xFF20202A),
        highlight: Color(0x66FFD54F),
      );
    case ReaderThemeMode.sepia:
      return const ReaderPalette(
        background: Color(0xFFF4ECD8),
        surface: Color(0xFFEFE5CD),
        foreground: Color(0xFF5B4636),
        textColor: Color(0xFF5B4636),
        highlight: Color(0x66D8A657),
        pdfFilter: ColorFilter.matrix(_sepiaMatrix),
      );
    case ReaderThemeMode.dark:
      return const ReaderPalette(
        background: Color(0xFF121212),
        surface: Color(0xFF1C1C1E),
        foreground: Color(0xFFE6E6E6),
        textColor: Color(0xFFD6D6D6),
        highlight: Color(0x59FFC107),
        pdfFilter: ColorFilter.matrix(_invertMatrix),
      );
    case ReaderThemeMode.black:
      return const ReaderPalette(
        background: Color(0xFF000000),
        surface: Color(0xFF101010),
        foreground: Color(0xFFDADADA),
        textColor: Color(0xFFC4C4C4),
        highlight: Color(0x59FFC107),
        pdfFilter: ColorFilter.matrix(_invertMatrix),
      );
  }
}

/// Tema local para los paneles del lector.
///
/// Los Material de serie (Switch, TextButton, el splash del InkWell, el cursor
/// de los campos de texto) toman su color del tema de la app, que puede ser el
/// neumórfico oscuro mientras se lee en claro: sin esto quedan sin contraste
/// —o directamente invisibles— sobre el panel del lector.
ThemeData readerSheetTheme(ReaderPalette palette) {
  final brightness = ThemeData.estimateBrightnessForColor(palette.surface);
  final base = ThemeData(brightness: brightness, useMaterial3: true);

  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: palette.foreground,
      onPrimary: palette.surface,
      secondary: palette.foreground,
      onSecondary: palette.surface,
      surface: palette.surface,
      onSurface: palette.foreground,
      surfaceContainerHighest: palette.background,
      outline: palette.foregroundAlpha(0.35),
      outlineVariant: palette.foregroundAlpha(0.18),
    ),
    canvasColor: palette.surface,
    dividerColor: palette.foregroundAlpha(0.15),
    iconTheme: IconThemeData(color: palette.foreground),
    splashColor: palette.foregroundAlpha(0.08),
    highlightColor: palette.foregroundAlpha(0.05),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: palette.foreground),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: palette.foreground),
    ),
  );
}

IconData readerThemeIcon(ReaderThemeMode mode) => switch (mode) {
      ReaderThemeMode.light => Icons.light_mode_outlined,
      ReaderThemeMode.sepia => Icons.wb_twilight_outlined,
      ReaderThemeMode.dark => Icons.dark_mode_outlined,
      ReaderThemeMode.black => Icons.nightlight_outlined,
    };

String readerThemeLabel(ReaderThemeMode mode) => switch (mode) {
      ReaderThemeMode.light => 'Claro',
      ReaderThemeMode.sepia => 'Sepia',
      ReaderThemeMode.dark => 'Oscuro',
      ReaderThemeMode.black => 'Negro',
    };

class ReaderThemeNotifier extends Notifier<ReaderThemeMode> {
  static const _prefsKey = 'reader_theme_mode';

  @override
  ReaderThemeMode build() {
    _load();
    return ReaderThemeMode.light;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = ReaderThemeMode.fromName(prefs.getString(_prefsKey));
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, state.name);
  }

  void setMode(ReaderThemeMode mode) {
    state = mode;
    _persist();
  }

  /// Rota entre claro → sepia → oscuro → negro → claro, para un botón único
  /// en la barra.
  void cycle() {
    final next = ReaderThemeMode.values[(state.index + 1) % ReaderThemeMode.values.length];
    setMode(next);
  }
}

final readerThemeProvider =
    NotifierProvider<ReaderThemeNotifier, ReaderThemeMode>(ReaderThemeNotifier.new);
