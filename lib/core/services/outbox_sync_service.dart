import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'outbox_service.dart';

/// Resultado de un drenaje. `pending` son operaciones que siguen esperando red;
/// `dropped` son las que el servidor rechazó de forma definitiva y no tiene
/// sentido reintentar.
typedef OutboxDrainResult = ({int sent, int pending, int dropped});

/// Vuelca a Supabase las escrituras que [OutboxService] guardó mientras no
/// había conexión.
///
/// La distinción importante es entre *no pude* y *no debo*: un fallo de red se
/// reintenta indefinidamente, pero un rechazo del servidor (RLS, restricción,
/// columna inexistente) se descarta. Reintentar eternamente una operación que
/// nunca va a pasar solo sirve para que la cola crezca y el usuario vea un
/// contador de pendientes que no baja nunca.
class OutboxSyncService {
  const OutboxSyncService._();

  static bool _running = false;

  /// Tras este número de fallos de red seguidos se asume que la operación está
  /// envenenada (payload que el cliente construye mal, por ejemplo) y se tira.
  /// Es alto a propósito: perder un dato del usuario es peor que reintentar de
  /// más.
  static const _maxAttempts = 25;

  /// Notifica cuántas escrituras quedan sin sincronizar. La UI se cuelga de
  /// aquí para el indicador de offline, en vez de sondear SharedPreferences.
  static final ValueNotifier<int> pending = ValueNotifier<int>(0);

  /// Recuenta lo pendiente y lo publica en [pending].
  static Future<int> refreshPendingCount() async {
    final count = await OutboxService.pendingCount();
    pending.value = count;
    return count;
  }

  /// Drena la cola entera. Es seguro llamarla de más (arranque, vuelta a primer
  /// plano, recuperación de red): sin nada pendiente sale en una lectura de
  /// SharedPreferences.
  static Future<OutboxDrainResult> drain() async {
    // Android puede encadenar dos avisos de "volviste a primer plano"; sin este
    // cerrojo la misma operación se enviaría dos veces, porque no se quita de
    // la cola hasta que el servidor confirma.
    if (_running) return (sent: 0, pending: pending.value, dropped: 0);
    _running = true;

    try {
      final ops = await OutboxService.readAll();
      if (ops.isEmpty) {
        pending.value = 0;
        return (sent: 0, pending: 0, dropped: 0);
      }

      // Sin sesión no hay dónde escribir, y encima las RLS rechazarían todo
      // como error permanente. Se deja intacto para cuando vuelva el usuario.
      if (Supabase.instance.client.auth.currentUser == null) {
        pending.value = ops.length;
        return (sent: 0, pending: ops.length, dropped: 0);
      }

      final done = <String>[];
      final dropped = <String>[];

      for (final op in ops) {
        try {
          await _apply(op);
          done.add(op.id);
        } on _PermanentFailure catch (e) {
          debugPrint('Outbox: descarto ${op.table}/${op.kind.name}: ${e.message}');
          dropped.add(op.id);
        } catch (e) {
          // Fallo de red: se queda en la cola. No se corta el bucle porque las
          // operaciones son independientes entre sí y alguna podría ir a otra
          // tabla que sí responda.
          await OutboxService.bumpAttempt(op.id, e.toString());
          if (op.attempts + 1 >= _maxAttempts) {
            debugPrint('Outbox: ${op.table}/${op.kind.name} agotó reintentos');
            dropped.add(op.id);
          }
        }
      }

      await OutboxService.remove([...done, ...dropped]);
      final left = await refreshPendingCount();

      return (sent: done.length, pending: left, dropped: dropped.length);
    } finally {
      _running = false;
    }
  }

  static Future<void> _apply(OutboxOp op) async {
    final table = Supabase.instance.client.from(op.table);

    try {
      switch (op.kind) {
        case OutboxOpKind.insert:
          await table.insert(op.payload);

        case OutboxOpKind.upsert:
          await table.upsert(op.payload, onConflict: op.onConflict);

        case OutboxOpKind.update:
          var query = table.update(op.payload);
          for (final entry in op.match.entries) {
            query = query.eq(entry.key, entry.value as Object);
          }
          await query;

        case OutboxOpKind.delete:
          var query = table.delete();
          for (final entry in op.match.entries) {
            query = query.eq(entry.key, entry.value as Object);
          }
          await query;
      }
    } on PostgrestException catch (e) {
      // El servidor contestó y dijo que no. Salvo que sea un 5xx (caída
      // temporal), insistir no va a cambiar la respuesta.
      if (_isTransientServerCode(e.code)) rethrow;

      // Un insert duplicado significa que la operación ya había llegado en un
      // intento anterior del que no nos enteramos: se da por buena.
      if (e.code == '23505') return;

      throw _PermanentFailure('${e.code} ${e.message}');
    } on AuthException catch (e) {
      // La sesión puede renovarse sola: se reintenta.
      throw StateError('sesión no válida: ${e.message}');
    } on SocketException {
      rethrow;
    } on TimeoutException {
      rethrow;
    }
  }

  /// Los 5xx son del servidor y suelen ser pasajeros; el resto de códigos de
  /// PostgREST describen un problema con la petición en sí.
  static bool _isTransientServerCode(String? code) {
    if (code == null) return true;
    return code.startsWith('5');
  }
}

class _PermanentFailure implements Exception {
  final String message;
  const _PermanentFailure(this.message);

  @override
  String toString() => 'OutboxPermanentFailure: $message';
}
