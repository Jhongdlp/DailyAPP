import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_destination.dart';

/// Qué pestañas viven en el dock y cuántas caben.
///
/// [slots] nunca es más largo que [size]; lo que no entra en el dock sigue
/// siendo accesible desde el menú, así que recortar aquí no esconde nada.
@immutable
class DockConfig {
  static const int minSize = 3;
  static const int maxSize = 5;

  final int size;
  final List<AppDestination> slots;

  const DockConfig._({required this.size, required this.slots});

  factory DockConfig({required int size, required List<AppDestination> slots}) {
    final s = size.clamp(minSize, maxSize);
    // Sin duplicados y sin pasarse del tamaño: el resto de la app asume ambas
    // cosas (un destino en dos huecos se vería seleccionado dos veces).
    final unique = <AppDestination>[];
    for (final d in slots) {
      if (!unique.contains(d)) unique.add(d);
      if (unique.length == s) break;
    }
    return DockConfig._(size: s, slots: List.unmodifiable(unique));
  }

  static const _defaultSlots = [
    AppDestination.habits,
    AppDestination.notes,
    AppDestination.alarm,
    AppDestination.finance,
  ];

  static DockConfig get defaults =>
      DockConfig(size: _defaultSlots.length, slots: _defaultSlots);

  bool get isFull => slots.length >= size;

  /// Los destinos que NO están en el dock, en el orden canónico. Es lo que el
  /// menú tiene que ofrecer para que ninguna pantalla quede inalcanzable.
  List<AppDestination> get overflow =>
      [for (final d in AppDestination.values) if (!slots.contains(d)) d];

  DockConfig copyWith({int? size, List<AppDestination>? slots}) =>
      DockConfig(size: size ?? this.size, slots: slots ?? this.slots);

  Map<String, dynamic> toJson() => {
        'size': size,
        'slots': [for (final d in slots) d.name],
      };

  factory DockConfig.fromJson(Map<String, dynamic> json) => DockConfig(
        size: (json['size'] as num?)?.toInt() ?? _defaultSlots.length,
        slots: [
          for (final name in (json['slots'] as List? ?? const []))
            ?AppDestination.byName('$name'),
        ],
      );
}

class DockNotifier extends Notifier<DockConfig> {
  static const _prefsKey = 'dock_config';

  @override
  DockConfig build() {
    _load();
    return DockConfig.defaults;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      state = DockConfig.fromJson(
        (jsonDecode(raw) as Map).cast<String, dynamic>(),
      );
    } catch (e) {
      // Preferencia corrupta: se ignora. Un dock mal guardado no puede dejar
      // la app sin navegación.
      debugPrint('DockNotifier: configuración ilegible, uso la de fábrica: $e');
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }

  void setSize(int size) {
    state = state.copyWith(size: size);
    _persist();
  }

  /// Alterna un destino. Si el dock está lleno, la pulsación no hace nada: es
  /// preferible a expulsar en silencio una pestaña que el usuario eligió.
  void toggle(AppDestination destination) {
    final slots = [...state.slots];
    if (slots.remove(destination)) {
      // Vaciar el dock del todo dejaría la navegación solo en el menú.
      if (slots.isEmpty) return;
    } else {
      if (state.isFull) return;
      slots.add(destination);
    }
    state = state.copyWith(slots: slots);
    _persist();
  }

  void reset() {
    state = DockConfig.defaults;
    _persist();
  }
}

final dockProvider = NotifierProvider<DockNotifier, DockConfig>(DockNotifier.new);
