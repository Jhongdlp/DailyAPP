import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'outbox_service.dart';
import 'outbox_sync_service.dart';

const _uuid = Uuid();

/// Identificador generado en el dispositivo para una fila nueva.
///
/// Antes las altas usaban `millisecondsSinceEpoch` como id temporal y luego lo
/// cambiaban por el que devolvía Supabase. Eso tenía dos problemas: el id
/// provisional no es un UUID, así que las mutaciones posteriores quedaban
/// bloqueadas por la comprobación de formato y nunca llegaban al servidor; y
/// sin conexión el intercambio no ocurría jamás. Generando aquí un UUID v4
/// válido, la fila nace con su id definitivo y el alta se puede encolar como
/// cualquier otra escritura.
String newRowId() => _uuid.v4();

/// En qué acabó una escritura.
///
/// La distinción entre [queued] y [rejected] importa: las dos dejan el estado
/// local por delante del servidor, pero solo una se arregla sola. Cuando se
/// devolvía un `bool` no se podían separar, y un rechazo del servidor quedaba
/// indistinguible de "ya se reintentará". Así fue como una política RLS que
/// faltaba en `habit_logs` estuvo tirando marcas de hábitos en silencio: la UI
/// mostraba el check hasta la siguiente recarga y entonces desaparecía.
enum WriteOutcome {
  /// El servidor confirmó la escritura.
  confirmed,

  /// No se pudo llegar al servidor. Quedó en el outbox y se reintentará sola;
  /// mientras tanto `reconcileRows` la mantiene visible sobre lo que se
  /// descargue.
  queued,

  /// El servidor la rechazó (RLS, restricción, payload inválido). No se
  /// reintenta, así que el estado local es mentira desde ya: quien llame debe
  /// recargar en vez de seguir mostrándolo.
  rejected;

  bool get isConfirmed => this == WriteOutcome.confirmed;
  bool get isRejected => this == WriteOutcome.rejected;
}

/// Intenta escribir en Supabase y, si falla por red, lo apunta en el outbox.
///
/// Los rechazos del servidor (RLS, restricciones) **no** se encolan: el
/// servidor ya dijo que no y guardarlos solo llenaría la cola de operaciones
/// condenadas a descartarse. Se devuelven como [WriteOutcome.rejected] para que
/// el provider pueda deshacer o recargar.
Future<WriteOutcome> syncedWrite({
  required Future<void> Function() write,
  required OutboxOp Function() fallback,
}) async {
  try {
    await write();
    return WriteOutcome.confirmed;
  } on PostgrestException catch (e) {
    // Los 5xx son caídas pasajeras del servidor y sí merecen reintento.
    if (e.code == null || e.code!.startsWith('5')) {
      await _queue(fallback());
      return WriteOutcome.queued;
    }
    debugPrint('syncedWrite: el servidor rechazó la escritura: ${e.code} ${e.message}');
    return WriteOutcome.rejected;
  } catch (e) {
    await _queue(fallback());
    return WriteOutcome.queued;
  }
}

Future<void> _queue(OutboxOp op) async {
  await OutboxService.enqueue(op);
  await OutboxSyncService.refreshPendingCount();
}

/// ¿Hay sesión y configuración suficientes para escribir en Supabase?
///
/// Si no la hay, la mutación se queda solo en local y **no** se encola: sin
/// usuario no se puede rellenar `user_id` ni pasarían las RLS.
bool get canWriteToSupabase =>
    Supabase.instance.client.auth.currentUser != null;
