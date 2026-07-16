import 'dart:ui' show Color;
import 'oklch.dart';

/// Los ocho acentos de la app, ya resueltos para UN modo (claro u oscuro).
///
/// Un acento no puede ser un único hex para los dos modos: sobre #212121 hay
/// que ser claro y sobre #E0E5EC hay que ser profundo. Por eso una paleta
/// completa son SIEMPRE dos AccentSet (ver [ResolvedPalette]).
class AccentSet {
  final Color habits;
  final Color brain;
  final Color alarm;
  final Color finance;
  final Color chat;
  final Color purple;
  final Color orange;
  final Color lime;

  const AccentSet({
    required this.habits,
    required this.brain,
    required this.alarm,
    required this.finance,
    required this.chat,
    required this.purple,
    required this.orange,
    required this.lime,
  });

  /// En orden de slot. El mismo orden que consume [_slotHues].
  List<Color> get all => [habits, brain, alarm, finance, chat, purple, orange, lime];

  /// Solo los cinco acentos que identifican pestañas (los que el usuario ve
  /// como "los colores de la app").
  List<Color> get tabs => [habits, brain, alarm, finance, chat];
}

/// Las superficies neumórficas de UN modo. Todas se derivan de la base.
class NeuSurfaces {
  final Color surface;
  final Color sunken;
  final Color shadowDark;
  final Color shadowLight;
  final Color text;

  const NeuSurfaces({
    required this.surface,
    required this.sunken,
    required this.shadowDark,
    required this.shadowLight,
    required this.text,
  });
}

/// Cómo quiere el usuario que se repartan los hues alrededor de su semilla.
enum PaletteScheme {
  /// Hues vecinos: la app entera en una familia de color. Cohesiva, pero las
  /// pestañas se distinguen menos entre sí.
  analogous('analogous', 'Análoga'),

  /// Tres anclas a 120°: contraste fuerte manteniendo estructura.
  triad('triad', 'Tríada'),

  /// Rueda completa, 45° entre acentos. Máxima distinción por pestaña — es
  /// como está construida la paleta por defecto.
  spread('spread', 'Rueda');

  final String value;
  final String label;
  const PaletteScheme(this.value, this.label);

  static PaletteScheme fromValue(String? v) =>
      PaletteScheme.values.firstWhere((s) => s.value == v, orElse: () => spread);
}

/// Lo que se guarda en disco: NO los colores, sino la receta para generarlos.
///
/// Guardar la receta y no los hexes significa que si algún día se afina la
/// máquina de derivación (banda de lightness, umbral de contraste), las
/// paletas de los usuarios mejoran solas en vez de quedarse congeladas.
class PaletteSpec {
  /// Id de un preset, o `null` si es una paleta derivada de [seedHue].
  final String? presetId;

  /// Hue OkLCh de la semilla, 0–360. Solo se usa si [presetId] es null.
  final double seedHue;

  final PaletteScheme scheme;

  const PaletteSpec({this.presetId, this.seedHue = 25, this.scheme = PaletteScheme.spread});

  bool get isCustom => presetId == null;

  Map<String, dynamic> toJson() => {
        'presetId': presetId,
        'seedHue': seedHue,
        'scheme': scheme.value,
      };

  factory PaletteSpec.fromJson(Map<String, dynamic> json) => PaletteSpec(
        presetId: json['presetId'] as String?,
        seedHue: (json['seedHue'] as num?)?.toDouble() ?? 25,
        scheme: PaletteScheme.fromValue(json['scheme'] as String?),
      );

  /// La paleta vívida calibrada a mano — el punto de partida de la app.
  static const PaletteSpec defaults = PaletteSpec(presetId: 'vivid');
}

/// Tinte del material neumórfico.
///
/// El usuario elige HUE y CROMA, nunca la lightness: el relieve neumórfico
/// depende de que la superficie viva en una lightness concreta (oscura ~0.27,
/// clara ~0.91). Si se pudiera elegir libre, un gris casi negro en modo claro
/// mataría las sombras y no habría relieve que ver. Así el material se puede
/// teñir de frío, sepia o verde sin poder romperse.
class MaterialSpec {
  /// Hue OkLCh del tinte, 0–360.
  final double hue;

  /// Intensidad del tinte. 0 = gris neutro. Se corta bajo para que el material
  /// siga leyéndose como material y no como color plano.
  final double chroma;

  const MaterialSpec({this.hue = 255, this.chroma = 0});

  /// `null` = las superficies calibradas a mano (ver [_defaultDark]).
  static const MaterialSpec? defaults = null;

  static const double maxChroma = 0.045;

  Map<String, dynamic> toJson() => {'hue': hue, 'chroma': chroma};

  factory MaterialSpec.fromJson(Map<String, dynamic> json) => MaterialSpec(
        hue: (json['hue'] as num?)?.toDouble() ?? 255,
        chroma: (json['chroma'] as num?)?.toDouble() ?? 0,
      );
}

/// Una paleta lista para pintar: los dos modos resueltos.
class ResolvedPalette {
  final AccentSet dark;
  final AccentSet light;
  const ResolvedPalette({required this.dark, required this.light});

  AccentSet forMode(bool isDark) => isDark ? dark : light;
}

/// Un preset con nombre, tal como se ofrece en la pantalla de personalizar.
class PalettePreset {
  final String id;
  final String name;

  /// Qué evoca. Es lo que se lee bajo el nombre en la lista.
  final String blurb;

  final ResolvedPalette Function() _build;

  const PalettePreset(this.id, this.name, this.blurb, this._build);

  ResolvedPalette resolve() => AppPalettes._cache.putIfAbsent(id, _build);
}

class AppPalettes {
  /// Derivar cuesta ~400 búsquedas binarias por paleta: barato de sobra para
  /// hacerlo una vez, caro si se hiciera en cada build. Los presets son
  /// inmutables, así que se cachean por id de por vida.
  static final Map<String, ResolvedPalette> _cache = {};

  // ─── Superficies calibradas a mano (el material por defecto) ───

  static const NeuSurfaces _defaultDark = NeuSurfaces(
    surface: Color(0xFF212121),
    sunken: Color(0xFF1B1B1B),
    shadowDark: Color(0xFF191919),
    shadowLight: Color(0xFF3C3C3C),
    text: Color(0xFFF5F3EE),
  );

  static const NeuSurfaces _defaultLight = NeuSurfaces(
    surface: Color(0xFFE0E5EC),
    sunken: Color(0xFFD3DAE5),
    shadowDark: Color(0xFFA3B1C6),
    shadowLight: Color(0xFFFFFFFF),
    text: Color(0xFF2C3145),
  );

  /// Superficies del modo pedido para un tinte dado. `null` = las de fábrica.
  ///
  /// Las lightness y cromas relativos salen de medir las superficies de fábrica
  /// en OkLCh: se conserva su anatomía exacta y solo se sustituye el tinte.
  static NeuSurfaces surfaces(MaterialSpec? spec, {required bool isDark}) {
    if (spec == null || spec.chroma <= 0.0005) {
      return isDark ? _defaultDark : _defaultLight;
    }
    final c = spec.chroma.clamp(0.0, MaterialSpec.maxChroma);
    final h = spec.hue;

    if (isDark) {
      return NeuSurfaces(
        surface: Oklch(0.267, c, h).toColor(),
        sunken: Oklch(0.232, c, h).toColor(),
        shadowDark: Oklch(0.220, c, h).toColor(),
        // La luz reflejada lleva menos tinte: es luz rebotando, no material.
        shadowLight: Oklch(0.396, c * 0.6, h).toColor(),
        text: Oklch(0.962, c * 0.25, h).toColor(),
      );
    }
    return NeuSurfaces(
      surface: Oklch(0.911, c, h).toColor(),
      sunken: Oklch(0.870, c * 1.15, h).toColor(),
      shadowDark: Oklch(0.735, c * 2.2, h).toColor(),
      // En modo claro la luz reflejada es blanco puro: es el brillo especular
      // de la fuente, y teñirlo delataría el truco.
      shadowLight: const Color(0xFFFFFFFF),
      text: Oklch(0.330, c * 1.6, h).toColor(),
    );
  }

  // ─── Derivación de acentos ───

  /// El acento más vivo posible para [hue] que aún contrasta ≥3:1 con
  /// [surface], recorriendo la cúspide del gamut dentro de la banda de
  /// lightness del modo.
  ///
  /// La banda es distinta por modo (sobre fondo oscuro el acento tiene que ser
  /// claro y al revés) y NO se fija una lightness única dentro de ella: la
  /// cúspide del amarillo cae en L≈0.79 y la del azul en L≈0.62, así que
  /// forzarlos a la misma L convertiría el ámbar en un ocre pardo.
  static Color deriveAccent(double hue, {required bool isDark, required Color surface}) {
    final lo = isDark ? 0.60 : 0.46;
    final hi = isDark ? 0.82 : 0.68;
    const steps = 28;

    Color? best;
    var bestChroma = -1.0;
    Color? mostContrast;
    var bestContrast = -1.0;

    for (var i = 0; i <= steps; i++) {
      final l = lo + (hi - lo) * i / steps;
      final chroma = Oklch.cuspChroma(l, hue);
      final color = Oklch(l, chroma, hue).toColor();
      final ratio = contrastRatio(color, surface);

      if (ratio > bestContrast) {
        bestContrast = ratio;
        mostContrast = color;
      }
      if (ratio >= 3.0 && chroma > bestChroma) {
        bestChroma = chroma;
        best = color;
      }
    }

    // Hay hues que no llegan a 3:1 en toda la banda: un amarillo vivo sobre
    // gris claro, por ejemplo, es física del gamut y no un error. En ese caso
    // se cede viveza a cambio del contraste máximo alcanzable.
    return best ?? mostContrast!;
  }

  /// Reparte ocho hues alrededor de la semilla según el esquema.
  ///
  /// Los índices no se asignan en orden: las cinco pestañas se llevan los hues
  /// más separados entre sí (0, 2, 4, 6, 7) y los tres acentos auxiliares se
  /// intercalan. Con un esquema análogo eso es la diferencia entre cinco
  /// pestañas distinguibles y cinco pestañas del mismo color.
  static List<double> _slotHues(double seed, PaletteScheme scheme) {
    final List<double> ring;
    switch (scheme) {
      case PaletteScheme.spread:
        ring = [for (var i = 0; i < 8; i++) seed + i * 45];
      case PaletteScheme.analogous:
        // 140° de abanico: ancho para que las pestañas se separen, estrecho
        // para que la familia de color siga leyéndose como una.
        ring = [for (var i = 0; i < 8; i++) seed - 70 + i * 20];
      case PaletteScheme.triad:
        ring = [for (var i = 0; i < 8; i++) seed + (i % 3) * 120 + (i ~/ 3) * 18];
    }
    const order = [0, 2, 4, 6, 7, 1, 3, 5]; // habits, brain, alarm, finance, chat, purple, orange, lime
    return [for (final i in order) ring[i] % 360];
  }

  static AccentSet _deriveSet(double seed, PaletteScheme scheme, Color surface, bool isDark) {
    final hues = _slotHues(seed, scheme);
    final c = [for (final h in hues) deriveAccent(h, isDark: isDark, surface: surface)];
    return AccentSet(
      habits: c[0],
      brain: c[1],
      alarm: c[2],
      finance: c[3],
      chat: c[4],
      purple: c[5],
      orange: c[6],
      lime: c[7],
    );
  }

  /// Genera una paleta completa desde una semilla. El material entra en juego
  /// porque el contraste se mide contra la superficie real, no contra un gris
  /// supuesto: teñir el material de azul cambia qué acentos son legibles.
  static ResolvedPalette derive(double seed, PaletteScheme scheme, MaterialSpec? material) {
    return ResolvedPalette(
      dark: _deriveSet(seed, scheme, surfaces(material, isDark: true).surface, true),
      light: _deriveSet(seed, scheme, surfaces(material, isDark: false).surface, false),
    );
  }

  // ─── Presets ───

  /// La paleta de fábrica: calibrada a mano acento por acento. Es el único
  /// preset con hexes escritos, porque sus hues se eligieron por significado
  /// (ámbar = dinero, verde = mente) y no por geometría en la rueda.
  static const ResolvedPalette _vivid = ResolvedPalette(
    dark: AccentSet(
      habits: Color(0xFFFD4800),
      brain: Color(0xFF05E079),
      alarm: Color(0xFF6174FF),
      finance: Color(0xFFFDA200),
      chat: Color(0xFF01B6FE),
      purple: Color(0xFF7F68FF),
      orange: Color(0xFFFF8600),
      lime: Color(0xFFC9F24E),
    ),
    light: AccentSet(
      habits: Color(0xFFEC4200),
      brain: Color(0xFF00964F),
      alarm: Color(0xFF4B52FF),
      finance: Color(0xFFB57301),
      chat: Color(0xFF0089C0),
      purple: Color(0xFF6E3FFF),
      orange: Color(0xFFC66802),
      // #6E8F1D a mano se quedaba en 2.96:1 — el único acento de fábrica que
      // no llegaba al mínimo. Este es el que devuelve la máquina para su mismo
      // hue: además de legal es más vivo (C 0.141 → 0.150).
      lime: Color(0xFF6A8D00),
    ),
  );

  /// Los presets se derivan con la máquina y el material de fábrica: son
  /// recetas con nombre, no listas de hexes. Uno solo escapa a la regla.
  static final List<PalettePreset> presets = [
    PalettePreset('vivid', 'Vívida', 'La de fábrica, calibrada a mano', () => _vivid),
    PalettePreset('sunset', 'Atardecer', 'Ámbares y magentas, familia cálida',
        () => derive(30, PaletteScheme.analogous, null)),
    PalettePreset('ocean', 'Océano', 'Cianes e índigos, familia fría',
        () => derive(230, PaletteScheme.analogous, null)),
    PalettePreset('forest', 'Bosque', 'Verdes y teales, tono terroso',
        () => derive(150, PaletteScheme.analogous, null)),
    PalettePreset('neon', 'Neón', 'Rueda completa desde el magenta',
        () => derive(320, PaletteScheme.spread, null)),
    PalettePreset('cobalt', 'Cobalto', 'Tríada anclada en azul',
        () => derive(255, PaletteScheme.triad, null)),
  ];

  static PalettePreset? presetById(String? id) {
    if (id == null) return null;
    for (final p in presets) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Resuelve una spec a colores. Es la única puerta de entrada del resto de
  /// la app: preset o semilla, aquí salen siempre dos AccentSet.
  static ResolvedPalette resolve(PaletteSpec spec, MaterialSpec? material) {
    final preset = presetById(spec.presetId);
    if (preset != null) return preset.resolve();
    return derive(spec.seedHue, spec.scheme, material);
  }
}
