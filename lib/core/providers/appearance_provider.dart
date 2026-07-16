import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_palette.dart';

/// Toda la apariencia elegida por el usuario: modo, paleta y material.
///
/// Los colores resueltos viven aquí y no se recalculan en cada build: derivar
/// una paleta son ~11k comprobaciones de gamut, barato una vez y caro sesenta
/// veces por segundo.
@immutable
class AppearanceState {
  final ThemeMode mode;
  final PaletteSpec palette;

  /// `null` = el material calibrado de fábrica (sin tinte).
  final MaterialSpec? material;

  /// Cache de [palette] + [material] ya convertidos a colores.
  final ResolvedPalette resolved;

  const AppearanceState._({
    required this.mode,
    required this.palette,
    required this.material,
    required this.resolved,
  });

  factory AppearanceState({
    required ThemeMode mode,
    required PaletteSpec palette,
    required MaterialSpec? material,
  }) =>
      AppearanceState._(
        mode: mode,
        palette: palette,
        material: material,
        resolved: AppPalettes.resolve(palette, material),
      );

  static AppearanceState get defaults => AppearanceState(
        mode: ThemeMode.dark,
        palette: PaletteSpec.defaults,
        material: MaterialSpec.defaults,
      );

  AppearanceState copyWith({
    ThemeMode? mode,
    PaletteSpec? palette,
    MaterialSpec? material,
    bool clearMaterial = false,
  }) =>
      AppearanceState(
        mode: mode ?? this.mode,
        palette: palette ?? this.palette,
        material: clearMaterial ? null : (material ?? this.material),
      );

  /// Resuelve el modo contra el brillo del sistema operativo.
  bool isDarkFor(Brightness platformBrightness) => switch (mode) {
        ThemeMode.dark => true,
        ThemeMode.light => false,
        ThemeMode.system => platformBrightness == Brightness.dark,
      };

  /// Firma de lo que afecta al color pintado. main.dart la usa como Key para
  /// remontar el árbol: media app son widgets const que leen los getters
  /// estáticos de BentoTheme y no se reconstruirían solos al cambiar la paleta.
  Object get signature => Object.hash(
        mode,
        palette.presetId,
        palette.seedHue,
        palette.scheme,
        material?.hue,
        material?.chroma,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'palette': palette.toJson(),
        'material': material?.toJson(),
      };

  factory AppearanceState.fromJson(Map<String, dynamic> json) => AppearanceState(
        mode: ThemeMode.values.firstWhere(
          (m) => m.name == json['mode'],
          orElse: () => ThemeMode.dark,
        ),
        palette: json['palette'] is Map
            ? PaletteSpec.fromJson((json['palette'] as Map).cast<String, dynamic>())
            : PaletteSpec.defaults,
        material: json['material'] is Map
            ? MaterialSpec.fromJson((json['material'] as Map).cast<String, dynamic>())
            : null,
      );
}

class AppearanceNotifier extends Notifier<AppearanceState> {
  static const _prefsKey = 'appearance';

  /// Clave del provider de tema anterior, que solo guardaba 'light' | 'dark'.
  static const _legacyModeKey = 'theme_mode';

  @override
  AppearanceState build() {
    _load();
    return AppearanceState.defaults;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        state = AppearanceState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        return;
      } catch (e) {
        // Preferencia corrupta: se ignora y se sigue con los valores de
        // fábrica en vez de dejar la app sin arrancar por un tema.
        debugPrint('AppearanceNotifier: preferencia ilegible, uso los valores por defecto: $e');
      }
    }

    // Migración desde el provider viejo: quien ya tenía el modo claro elegido
    // no debe encontrárselo reseteado al actualizar.
    if (prefs.getString(_legacyModeKey) == 'light') {
      state = state.copyWith(mode: ThemeMode.light);
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }

  void setMode(ThemeMode mode) {
    state = state.copyWith(mode: mode);
    _persist();
  }

  /// Alterna claro/oscuro. Desde 'sistema' salta a lo contrario de lo que se
  /// está viendo, que es lo que espera quien pulsa el atajo del dashboard.
  void toggleMode(bool currentlyDark) {
    setMode(currentlyDark ? ThemeMode.light : ThemeMode.dark);
  }

  void setPreset(String presetId) {
    state = state.copyWith(palette: PaletteSpec(presetId: presetId));
    _persist();
  }

  /// [persist] a false mientras se arrastra un slider: el color se actualiza en
  /// cada frame (que es el sentido de la vista previa) pero escribir en disco
  /// sesenta veces por segundo no.
  void setCustomPalette({double? seedHue, PaletteScheme? scheme, bool persist = true}) {
    final current = state.palette;
    state = state.copyWith(
      palette: PaletteSpec(
        seedHue: seedHue ?? current.seedHue,
        scheme: scheme ?? current.scheme,
      ),
    );
    if (persist) _persist();
  }

  void setMaterial(MaterialSpec? material, {bool persist = true}) {
    state = state.copyWith(material: material, clearMaterial: material == null);
    if (persist) _persist();
  }

  /// Guarda lo que haya en memoria. Para llamar al soltar un slider que se
  /// estuvo actualizando sin persistir.
  void commit() => _persist();

  void resetAll() {
    state = AppearanceState.defaults.copyWith(mode: state.mode);
    _persist();
  }
}

final appearanceProvider =
    NotifierProvider<AppearanceNotifier, AppearanceState>(AppearanceNotifier.new);

/// Atajo de solo lectura para quien únicamente necesita el modo.
final themeModeProvider = Provider<ThemeMode>((ref) => ref.watch(appearanceProvider).mode);
