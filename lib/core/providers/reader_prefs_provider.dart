import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tipografías ofrecidas en el lector. Son fuentes pensadas para leer texto
/// largo, no las de la interfaz: por eso no se reutiliza la Montserrat de la
/// app salvo como opción explícita.
enum ReaderFontFamily {
  literata('Literata', 'Serif clásica'),
  lora('Lora', 'Serif suave'),
  merriweather('Merriweather', 'Serif densa'),
  inter('Inter', 'Sans neutra'),
  atkinson('Atkinson Hyperlegible', 'Sans accesible'),
  montserrat('Montserrat', 'La de la app');

  const ReaderFontFamily(this.fontName, this.description);

  /// Nombre tal cual lo espera Google Fonts.
  final String fontName;
  final String description;

  static ReaderFontFamily fromName(String? name) =>
      ReaderFontFamily.values.firstWhere(
        (f) => f.name == name,
        orElse: () => ReaderFontFamily.literata,
      );
}

/// Lo único de las preferencias que cambia cómo se compone el texto.
///
/// El lector reconstruye el libro cuando esto cambia, y solo cuando cambia:
/// `flutter_html` vuelve a parsear y re-inflar cada párrafo visible en cada
/// reconstrucción, así que mover el brillo o reajustar las palabras por minuto
/// medidas no puede arrastrar consigo a la vista del EPUB.
typedef ReaderComposition = ({
  double fontSize,
  double lineHeight,
  double horizontalMargin,
  ReaderFontFamily fontFamily,
  bool justify,
});

/// Preferencias de composición del texto. Cambiarlas reconstruye la vista del
/// EPUB, por eso el lector reancla la posición con el CFI actual.
class ReaderPrefs {
  final double fontSize;
  final double lineHeight;
  final double horizontalMargin;
  final ReaderFontFamily fontFamily;
  final bool justify;

  /// Brillo forzado dentro del lector (0..1). `null` = respetar el del sistema.
  final double? brightness;

  final bool keepScreenOn;

  /// Palabras por minuto medidas del propio usuario, para estimar el tiempo
  /// restante. Arranca en 220 (media adulta) y se ajusta con la lectura real.
  final double wordsPerMinute;

  /// Pasar página en vez de desplazar de forma continua. Es opcional a
  /// propósito: el scroll sigue siendo el modo por defecto.
  final bool paginated;

  /// Multiplicador de la velocidad del auto-scroll sobre la velocidad de
  /// lectura estimada. 1.0 = leer al ritmo de [wordsPerMinute].
  final double autoScrollSpeed;

  /// Velocidad de la voz del lector en voz alta (0.1–1.0 en flutter_tts).
  final double ttsRate;

  /// Idioma forzado para la voz (`es-ES`, `en-US`…). `null` = el del sistema.
  final String? ttsLanguage;

  const ReaderPrefs({
    this.fontSize = 18,
    this.lineHeight = 1.6,
    this.horizontalMargin = 20,
    this.fontFamily = ReaderFontFamily.literata,
    this.justify = false,
    this.brightness,
    this.keepScreenOn = true,
    this.wordsPerMinute = 220,
    this.paginated = false,
    this.autoScrollSpeed = 1.0,
    this.ttsRate = 0.5,
    this.ttsLanguage,
  });

  ReaderPrefs copyWith({
    double? fontSize,
    double? lineHeight,
    double? horizontalMargin,
    ReaderFontFamily? fontFamily,
    bool? justify,
    double? brightness,
    bool clearBrightness = false,
    bool? keepScreenOn,
    double? wordsPerMinute,
    bool? paginated,
    double? autoScrollSpeed,
    double? ttsRate,
    String? ttsLanguage,
    bool clearTtsLanguage = false,
  }) {
    return ReaderPrefs(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      horizontalMargin: horizontalMargin ?? this.horizontalMargin,
      fontFamily: fontFamily ?? this.fontFamily,
      justify: justify ?? this.justify,
      brightness: clearBrightness ? null : brightness ?? this.brightness,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      wordsPerMinute: wordsPerMinute ?? this.wordsPerMinute,
      paginated: paginated ?? this.paginated,
      autoScrollSpeed: autoScrollSpeed ?? this.autoScrollSpeed,
      ttsRate: ttsRate ?? this.ttsRate,
      ttsLanguage: clearTtsLanguage ? null : ttsLanguage ?? this.ttsLanguage,
    );
  }

  ReaderComposition get composition => (
        fontSize: fontSize,
        lineHeight: lineHeight,
        horizontalMargin: horizontalMargin,
        fontFamily: fontFamily,
        justify: justify,
      );

  /// Estilo base del cuerpo del libro, ya con la tipografía resuelta.
  TextStyle textStyle(Color color) => GoogleFonts.getFont(
        fontFamily.fontName,
        fontSize: fontSize,
        height: lineHeight,
        color: color,
      );

  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'horizontalMargin': horizontalMargin,
        'fontFamily': fontFamily.name,
        'justify': justify,
        'brightness': brightness,
        'keepScreenOn': keepScreenOn,
        'wordsPerMinute': wordsPerMinute,
        'paginated': paginated,
        'autoScrollSpeed': autoScrollSpeed,
        'ttsRate': ttsRate,
        'ttsLanguage': ttsLanguage,
      };

  factory ReaderPrefs.fromJson(Map<String, dynamic> json) => ReaderPrefs(
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18,
        lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.6,
        horizontalMargin: (json['horizontalMargin'] as num?)?.toDouble() ?? 20,
        fontFamily: ReaderFontFamily.fromName(json['fontFamily'] as String?),
        justify: json['justify'] as bool? ?? false,
        brightness: (json['brightness'] as num?)?.toDouble(),
        keepScreenOn: json['keepScreenOn'] as bool? ?? true,
        wordsPerMinute: (json['wordsPerMinute'] as num?)?.toDouble() ?? 220,
        paginated: json['paginated'] as bool? ?? false,
        autoScrollSpeed: (json['autoScrollSpeed'] as num?)?.toDouble() ?? 1.0,
        ttsRate: (json['ttsRate'] as num?)?.toDouble() ?? 0.5,
        ttsLanguage: json['ttsLanguage'] as String?,
      );
}

class ReaderPrefsNotifier extends Notifier<ReaderPrefs> {
  static const _prefsKey = 'reader_prefs';

  static const fontSizeRange = (min: 12.0, max: 30.0);
  static const lineHeightRange = (min: 1.1, max: 2.4);
  static const marginRange = (min: 0.0, max: 56.0);
  static const autoScrollRange = (min: 0.4, max: 2.5);
  static const ttsRateRange = (min: 0.2, max: 1.0);

  @override
  ReaderPrefs build() {
    _load();
    return const ReaderPrefs();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      state = ReaderPrefs.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Preferencias corruptas: se conservan las de fábrica
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }

  void _update(ReaderPrefs next) {
    state = next;
    _persist();
  }

  void setFontSize(double value) => _update(state.copyWith(
      fontSize: value.clamp(fontSizeRange.min, fontSizeRange.max)));

  void setLineHeight(double value) => _update(state.copyWith(
      lineHeight: value.clamp(lineHeightRange.min, lineHeightRange.max)));

  void setHorizontalMargin(double value) => _update(state.copyWith(
      horizontalMargin: value.clamp(marginRange.min, marginRange.max)));

  void setFontFamily(ReaderFontFamily family) =>
      _update(state.copyWith(fontFamily: family));

  void setJustify(bool value) => _update(state.copyWith(justify: value));

  void setKeepScreenOn(bool value) => _update(state.copyWith(keepScreenOn: value));

  void setPaginated(bool value) => _update(state.copyWith(paginated: value));

  void setAutoScrollSpeed(double value) => _update(state.copyWith(
      autoScrollSpeed: value.clamp(autoScrollRange.min, autoScrollRange.max)));

  void setTtsRate(double value) => _update(state.copyWith(
      ttsRate: value.clamp(ttsRateRange.min, ttsRateRange.max)));

  /// `null` devuelve la voz al idioma del sistema.
  void setTtsLanguage(String? value) => _update(value == null
      ? state.copyWith(clearTtsLanguage: true)
      : state.copyWith(ttsLanguage: value));

  /// `null` devuelve el control del brillo al sistema.
  void setBrightness(double? value) => _update(value == null
      ? state.copyWith(clearBrightness: true)
      : state.copyWith(brightness: value.clamp(0.01, 1.0)));

  void resetTypography() => _update(state.copyWith(
        fontSize: 18,
        lineHeight: 1.6,
        horizontalMargin: 20,
        fontFamily: ReaderFontFamily.literata,
        justify: false,
      ));

  /// Ajusta la velocidad de lectura estimada con una media móvil, para que la
  /// estimación de "tiempo restante" converja al ritmo real del usuario.
  void registerReadingSpeed(double observedWpm) {
    if (observedWpm < 60 || observedWpm > 900) return; // medición poco creíble
    final blended = state.wordsPerMinute * 0.8 + observedWpm * 0.2;
    _update(state.copyWith(wordsPerMinute: blended));
  }
}

final readerPrefsProvider =
    NotifierProvider<ReaderPrefsNotifier, ReaderPrefs>(ReaderPrefsNotifier.new);
