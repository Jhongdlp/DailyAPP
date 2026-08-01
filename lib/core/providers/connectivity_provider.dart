import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/outbox_sync_service.dart';

/// Estado de sincronización que ve la UI.
///
/// `online` es lo que dice el sistema operativo sobre la interfaz de red, que
/// no es lo mismo que "Supabase responde": un wifi de hotel con portal cautivo
/// cuenta como conectado. Por eso el contador de pendientes manda sobre el
/// icono: mientras haya cola, hay algo sin confirmar, diga lo que diga Android.
class SyncStatus {
  final bool online;
  final int pending;
  final bool syncing;

  const SyncStatus({
    this.online = true,
    this.pending = 0,
    this.syncing = false,
  });

  bool get hasPending => pending > 0;

  /// Solo hay algo que contarle al usuario si está sin red o si quedaron
  /// escrituras esperando. Estar online y a cero es el caso normal y no merece
  /// ni un píxel de la pantalla.
  bool get needsAttention => !online || hasPending;

  SyncStatus copyWith({bool? online, int? pending, bool? syncing}) => SyncStatus(
        online: online ?? this.online,
        pending: pending ?? this.pending,
        syncing: syncing ?? this.syncing,
      );
}

class SyncStatusNotifier extends Notifier<SyncStatus> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _retryTimer;

  /// Red de seguridad para el caso en que el sistema no avise del cambio de
  /// conectividad (pasa en algunos Android con datos móviles): cada tanto se
  /// intenta drenar igualmente. Es barato cuando no hay nada pendiente.
  static const _retryInterval = Duration(minutes: 5);

  @override
  SyncStatus build() {
    ref.onDispose(() {
      _sub?.cancel();
      _retryTimer?.cancel();
      OutboxSyncService.pending.removeListener(_onPendingChanged);
    });

    OutboxSyncService.pending.addListener(_onPendingChanged);
    unawaited(OutboxSyncService.refreshPendingCount());

    _listenToConnectivity();
    _retryTimer = Timer.periodic(_retryInterval, (_) {
      if (state.online && state.hasPending) unawaited(sync());
    });

    return const SyncStatus();
  }

  void _onPendingChanged() {
    state = state.copyWith(pending: OutboxSyncService.pending.value);
  }

  Future<void> _listenToConnectivity() async {
    final connectivity = Connectivity();

    try {
      _applyResults(await connectivity.checkConnectivity());
    } catch (_) {
      // Si no se puede consultar, se asume que hay red: es mejor intentar la
      // escritura y que falle (acabaría en el outbox de todos modos) que
      // bloquearla por una lectura de estado que no funcionó.
    }

    _sub = connectivity.onConnectivityChanged.listen(_applyResults);
  }

  void _applyResults(List<ConnectivityResult> results) {
    final online =
        results.isNotEmpty && !results.every((r) => r == ConnectivityResult.none);
    final wasOffline = !state.online;

    state = state.copyWith(online: online);

    // El momento en que vuelve la red es exactamente cuando merece la pena
    // drenar: es la única transición que puede desatascar la cola.
    if (online && wasOffline) unawaited(sync());
  }

  /// Drena el outbox. La llaman el arranque, la vuelta a primer plano, la
  /// recuperación de red y el botón de reintentar del indicador.
  Future<void> sync() async {
    if (state.syncing) return;
    state = state.copyWith(syncing: true);

    try {
      final result = await OutboxSyncService.drain();
      if (result.dropped > 0) {
        debugPrint('Outbox: ${result.dropped} operaciones descartadas');
      }
    } finally {
      state = state.copyWith(
        syncing: false,
        pending: OutboxSyncService.pending.value,
      );
    }
  }
}

final syncStatusProvider =
    NotifierProvider<SyncStatusNotifier, SyncStatus>(SyncStatusNotifier.new);
