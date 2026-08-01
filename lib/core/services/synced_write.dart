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

/// Intenta escribir en Supabase y, si falla por red, lo apunta en el outbox.
///
/// Devuelve `true` si el servidor confirmó. Un `false` no es un error para el
/// usuario: la mutación ya se aplicó en local y se reintentará sola.
///
/// Los rechazos del servidor (RLS, restricciones) **no** se encolan: el
/// servidor ya dijo que no y guardarlos solo llenaría la cola de operaciones
/// condenadas a descartarse.
Future<bool> syncedWrite({
  required Future<void> Function() write,
  required OutboxOp Function() fallback,
}) async {
  try {
    await write();
    return true;
  } on PostgrestException catch (e) {
    // Los 5xx son caídas pasajeras del servidor y sí merecen reintento.
    if (e.code == null || e.code!.startsWith('5')) {
      await _queue(fallback());
      return false;
    }
    debugPrint('syncedWrite: el servidor rechazó la escritura: ${e.code} ${e.message}');
    return false;
  } catch (e) {
    await _queue(fallback());
    return false;
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
