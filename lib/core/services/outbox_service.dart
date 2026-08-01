import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Registro durable de escrituras que todavía no han llegado a Supabase.
///
/// Hasta ahora los providers hacían la escritura optimista en memoria y se
/// tragaban el error de red en silencio. El cambio sobrevivía en la caché…
/// hasta la siguiente recarga, que lo pisaba con los datos del servidor. Es
/// decir: sin conexión la app *mentía*, y el dato se perdía sin avisar.
///
/// El trato ahora es el de [QuickCaptureQueue], generalizado: la mutación se
/// aplica en local, y si no se puede confirmar contra el servidor se apunta
/// aquí. [OutboxSyncService] la reintenta más tarde, y mientras tanto
/// [reconcileRows] la vuelve a aplicar encima de lo que llegue del servidor
/// para que un refresh no la borre.
///
/// Se guarda en SharedPreferences y no en secure storage por lo mismo que
/// [CacheService]: es contenido no sensible y el coste de cifrar cada escritura
/// no compensa. Las credenciales y el vault siguen aparte.
enum OutboxOpKind { insert, update, upsert, delete }

class OutboxOp {
  /// Único dentro de la cola. No viaja a la base de datos.
  final String id;

  /// Tabla de Supabase sobre la que se escribe.
  final String table;

  final OutboxOpKind kind;

  /// Fila a escribir. Vacío en los `delete`.
  final Map<String, dynamic> payload;

  /// Filtros `eq` que identifican la fila en `update` y `delete`, y que también
  /// sirven de identidad para fusionar operaciones repetidas. Para tablas con
  /// clave compuesta (p.ej. `habit_logs` por `habit_id` + `completed_on`) lleva
  /// las dos columnas: un `id` suelto no bastaría.
  final Map<String, dynamic> match;

  /// Columnas del `onConflict` en los upsert.
  final String? onConflict;

  /// Momento de la mutación en el dispositivo, no del volcado: un hábito
  /// marcado el viernes sin conexión sigue siendo del viernes.
  final DateTime createdAt;

  /// Intentos de envío fallidos por red. Alimenta el backoff del sincronizador.
  final int attempts;

  final String? lastError;

  const OutboxOp({
    required this.id,
    required this.table,
    required this.kind,
    this.payload = const {},
    this.match = const {},
    this.onConflict,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
  });

  factory OutboxOp.create({
    required String table,
    required OutboxOpKind kind,
    Map<String, dynamic> payload = const {},
    Map<String, dynamic> match = const {},
    String? onConflict,
    DateTime? createdAt,
  }) {
    final now = createdAt ?? DateTime.now();
    return OutboxOp(
      id: '${now.microsecondsSinceEpoch}-$table-${kind.name}',
      table: table,
      kind: kind,
      payload: payload,
      match: match,
      onConflict: onConflict,
      createdAt: now,
    );
  }

  OutboxOp copyWith({
    Map<String, dynamic>? payload,
    int? attempts,
    String? lastError,
  }) =>
      OutboxOp(
        id: id,
        table: table,
        kind: kind,
        payload: payload ?? this.payload,
        match: match,
        onConflict: onConflict,
        createdAt: createdAt,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
      );

  /// Dos operaciones hablan de la misma fila si coinciden tabla y filtros. Se
  /// compara sobre las claves de [match] ordenadas para que el orden en que se
  /// construyó el mapa no cambie la identidad.
  bool sameRowAs(OutboxOp other) {
    if (table != other.table) return false;
    if (match.isEmpty || other.match.isEmpty) return false;
    if (match.length != other.match.length) return false;
    for (final entry in match.entries) {
      if (other.match[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// ¿La fila [row] que vino del servidor es la que toca esta operación?
  bool matchesRow(Map<String, dynamic> row) {
    if (match.isEmpty) return false;
    for (final entry in match.entries) {
      if (row[entry.key] != entry.value) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'table': table,
        'kind': kind.name,
        'payload': payload,
        'match': match,
        'on_conflict': onConflict,
        'created_at': createdAt.toIso8601String(),
        'attempts': attempts,
        'last_error': lastError,
      };

  factory OutboxOp.fromJson(Map<String, dynamic> json) => OutboxOp(
        id: json['id'] as String,
        table: json['table'] as String,
        kind: OutboxOpKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => OutboxOpKind.update,
        ),
        payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
        match: Map<String, dynamic>.from(json['match'] as Map? ?? {}),
        onConflict: json['on_conflict'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        lastError: json['last_error'] as String?,
      );
}

class OutboxService {
  const OutboxService._();

  static const _keyPrefix = 'outbox';

  /// Tope defensivo, como en [QuickCaptureQueue]: si el dispositivo pasara
  /// semanas sin red, la cola no debe crecer sin límite dentro de
  /// SharedPreferences. La fusión de operaciones de abajo hace que llegar aquí
  /// sea muy improbable.
  static const _maxOps = 500;

  static String get _userId =>
      Supabase.instance.client.auth.currentUser?.id ?? 'anon';

  static String get _key => '${_keyPrefix}_$_userId';

  /// La cola se lee y escribe desde varios sitios (providers, sincronizador,
  /// vuelta a primer plano). Este cerrojo serializa el ciclo leer-modificar-
  /// escribir para que dos mutaciones simultáneas no se pisen.
  static Future<void> _lock = Future.value();

  static Future<T> _synchronized<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    // La cadena no debe romperse si una acción lanza: se traga aquí para el
    // encadenado, pero el error sigue propagándose a quien llamó.
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Apunta una escritura pendiente, fusionándola con lo que ya hubiera para la
  /// misma fila.
  ///
  /// Sin fusión, marcar un hábito veinte veces sin conexión dejaría veinte
  /// operaciones que se enviarían una a una para acabar en el mismo estado. Y
  /// peor: un alta seguida de un borrado mandaría al servidor una fila que el
  /// usuario ya no quiere.
  static Future<void> enqueue(OutboxOp op) => _synchronized(() async {
        final ops = await _readRaw();
        final merged = mergeOps(ops, op);

        if (merged.length > _maxOps) {
          merged.removeRange(0, merged.length - _maxOps);
        }

        await _writeRaw(merged);
      });

  /// Reglas de fusión. Se aplican solo entre operaciones que aún no han salido
  /// del dispositivo, así que reescribir el pasado aquí es seguro.
  ///
  /// Es pura a propósito: define la semántica de la cola y se prueba sola, sin
  /// SharedPreferences ni sesión de Supabase por medio.
  @visibleForTesting
  static List<OutboxOp> mergeOps(List<OutboxOp> ops, OutboxOp incoming) {
    // Sin filtros no hay forma de saber de qué fila habla: se encola tal cual.
    if (incoming.match.isEmpty) return [...ops, incoming];

    final previous = ops.where(incoming.sameRowAs).toList();
    if (previous.isEmpty) return [...ops, incoming];

    final rest = ops.where((o) => !incoming.sameRowAs(o)).toList();

    switch (incoming.kind) {
      case OutboxOpKind.delete:
        // Si la fila nace y muere sin haber salido nunca del dispositivo, el
        // servidor no tiene por qué enterarse de ninguna de las dos cosas.
        final wasNew = previous.any((o) => o.kind == OutboxOpKind.insert);
        return wasNew ? rest : [...rest, incoming];

      case OutboxOpKind.update:
        // Se funde en lo que ya hubiera conservando su tipo: un update sobre un
        // alta pendiente es, en realidad, un alta con otros campos, y mandarlo
        // como update fallaría porque la fila aún no existe en el servidor.
        final base = previous.first;
        final fused = base.copyWith(payload: {...base.payload, ...incoming.payload});
        return _replacingAt(ops, base, fused);

      case OutboxOpKind.upsert:
      case OutboxOpKind.insert:
        // El último gana: es el estado que el usuario está viendo.
        final base = previous.first;
        if (base.kind == OutboxOpKind.insert && incoming.kind == OutboxOpKind.upsert) {
          final fused = base.copyWith(payload: {...base.payload, ...incoming.payload});
          return _replacingAt(ops, base, fused);
        }
        return _replacingAt(ops, base, incoming);
    }
  }

  /// Sustituye [old] por [replacement] sin moverlo de sitio: el orden de la cola
  /// es el orden en que se enviará, y adelantar una operación podría hacerla
  /// llegar antes que otra de la que depende.
  static List<OutboxOp> _replacingAt(
    List<OutboxOp> ops,
    OutboxOp old,
    OutboxOp replacement,
  ) {
    final out = <OutboxOp>[];
    var replaced = false;
    for (final o in ops) {
      if (o.id == old.id) {
        out.add(replacement);
        replaced = true;
      } else if (replaced && replacement.sameRowAs(o)) {
        // Restos de la misma fila que quedaran detrás: ya están representados
        // en la operación fusionada.
        continue;
      } else {
        out.add(o);
      }
    }
    return out;
  }

  /// Toda la cola, en orden de envío.
  static Future<List<OutboxOp>> readAll() => _synchronized(_readRaw);

  /// Operaciones pendientes de una tabla concreta. Lo usan los providers para
  /// reconciliar lo que acaban de descargar.
  static Future<List<OutboxOp>> pendingFor(String table) async {
    final ops = await readAll();
    return ops.where((o) => o.table == table).toList();
  }

  static Future<int> pendingCount() async => (await readAll()).length;

  static Future<void> remove(Iterable<String> ids) => _synchronized(() async {
        final toRemove = ids.toSet();
        if (toRemove.isEmpty) return;

        final ops = await _readRaw();
        await _writeRaw(ops.where((o) => !toRemove.contains(o.id)).toList());
      });

  /// Anota un intento fallido por red. Si la operación ya no está (porque otro
  /// drenaje la completó), no se recrea.
  static Future<void> bumpAttempt(String id, String error) =>
      _synchronized(() async {
        final ops = await _readRaw();
        final idx = ops.indexWhere((o) => o.id == id);
        if (idx == -1) return;

        ops[idx] = ops[idx].copyWith(
          attempts: ops[idx].attempts + 1,
          lastError: error,
        );
        await _writeRaw(ops);
      });

  static Future<void> clear() => _synchronized(() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_key);
      });

  /// Aplica las operaciones pendientes sobre las filas recién descargadas del
  /// servidor.
  ///
  /// Esta es la pieza que faltaba: sin ella, recargar hábitos con una marca sin
  /// sincronizar devuelve el estado antiguo del servidor y el check desaparece
  /// delante del usuario. Se trabaja sobre el JSON crudo, antes de mapear a
  /// modelos, para que sirva igual a cualquier tabla.
  static List<Map<String, dynamic>> reconcileRows(
    List<Map<String, dynamic>> rows,
    List<OutboxOp> ops,
  ) {
    final out = [...rows];

    for (final op in ops) {
      switch (op.kind) {
        case OutboxOpKind.delete:
          out.removeWhere(op.matchesRow);

        case OutboxOpKind.update:
          for (var i = 0; i < out.length; i++) {
            if (op.matchesRow(out[i])) {
              out[i] = {...out[i], ...op.payload};
            }
          }

        case OutboxOpKind.insert:
        case OutboxOpKind.upsert:
          final idx = out.indexWhere(op.matchesRow);
          if (idx == -1) {
            out.add({...op.match, ...op.payload});
          } else {
            out[idx] = {...out[idx], ...op.payload};
          }
      }
    }

    return out;
  }

  /// Lee descartando en silencio lo que no se pueda deserializar: una entrada
  /// corrupta no puede bloquear el resto de la cola para siempre.
  static Future<List<OutboxOp>> _readRaw() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      final raw = prefs.getStringList(_key) ?? const <String>[];
      final out = <OutboxOp>[];
      for (final entry in raw) {
        try {
          out.add(OutboxOp.fromJson(jsonDecode(entry) as Map<String, dynamic>));
        } catch (_) {
          continue;
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeRaw(List<OutboxOp> ops) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _key,
        ops.map((o) => jsonEncode(o.toJson())).toList(),
      );
    } catch (_) {}
  }
}
