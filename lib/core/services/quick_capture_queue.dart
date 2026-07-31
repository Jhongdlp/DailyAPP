import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'quick_capture_parser.dart';

/// Buzón entre el modal de captura rápida y la app.
///
/// El modal corre en su propio engine de Flutter, sin Supabase ni sesión: se
/// abre desde el desplegable del sistema, guarda aquí y se cierra. Esperar a la
/// red antes de cerrar convertiría una anotación de dos segundos en una de
/// diez, y encima fallaría sin conexión. La app principal drena este buzón
/// cuando arranca o vuelve a primer plano.
///
/// Ambos engines viven en el mismo proceso y comparten el fichero de
/// SharedPreferences, pero **no** la copia en memoria: quien lea debe llamar
/// antes a `reload()` o verá una versión vieja.
class QuickCaptureQueue {
  static const _key = 'quick_capture_queue';

  /// Tope defensivo. Si la app llevara semanas sin abrirse, la cola no debe
  /// crecer sin límite dentro de SharedPreferences.
  static const _maxEntries = 200;

  const QuickCaptureQueue._();

  static Future<void> enqueue(QuickCaptureDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final entries = prefs.getStringList(_key) ?? <String>[];
    entries.add(jsonEncode(QuickCaptureEntry.fromDraft(draft).toJson()));

    if (entries.length > _maxEntries) {
      entries.removeRange(0, entries.length - _maxEntries);
    }

    await prefs.setStringList(_key, entries);
  }

  /// Lee la cola descartando en silencio lo que no se pueda deserializar: una
  /// entrada corrupta no puede bloquear las demás para siempre.
  static Future<List<QuickCaptureEntry>> readAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final entries = prefs.getStringList(_key) ?? <String>[];
    final out = <QuickCaptureEntry>[];
    for (final raw in entries) {
      try {
        out.add(QuickCaptureEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  /// Quita las entradas ya guardadas en Supabase. Se releen justo antes de
  /// escribir porque el modal puede haber encolado algo mientras se drenaba.
  static Future<void> removeAll(Iterable<String> ids) async {
    final toRemove = ids.toSet();
    if (toRemove.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final entries = prefs.getStringList(_key) ?? <String>[];
    final kept = entries.where((raw) {
      try {
        final id = (jsonDecode(raw) as Map<String, dynamic>)['id'] as String?;
        return id == null || !toRemove.contains(id);
      } catch (_) {
        return false; // basura: se aprovecha el paso para limpiarla
      }
    }).toList();

    await prefs.setStringList(_key, kept);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

class QuickCaptureEntry {
  final String id;
  final QuickCaptureDraft draft;

  /// Momento en que se capturó, no en que se sincronizó: es la fecha que debe
  /// acabar en `occurred_at` de la transacción aunque se guarde días después.
  final DateTime capturedAt;

  const QuickCaptureEntry({
    required this.id,
    required this.draft,
    required this.capturedAt,
  });

  factory QuickCaptureEntry.fromDraft(QuickCaptureDraft draft) {
    final now = DateTime.now();
    return QuickCaptureEntry(
      // Basta con ser único dentro de la cola: no viaja a la base de datos.
      id: '${now.microsecondsSinceEpoch}-${draft.kind.name}',
      draft: draft,
      capturedAt: now,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'captured_at': capturedAt.toIso8601String(),
        'draft': draft.toJson(),
      };

  factory QuickCaptureEntry.fromJson(Map<String, dynamic> json) => QuickCaptureEntry(
        id: json['id'] as String,
        capturedAt: DateTime.parse(json['captured_at'] as String),
        draft: QuickCaptureDraft.fromJson(json['draft'] as Map<String, dynamic>),
      );
}
