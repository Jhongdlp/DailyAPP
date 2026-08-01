import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/connectivity_provider.dart';
import '../theme/bento_theme.dart';

/// Pastilla que avisa de que hay escrituras sin subir.
///
/// Solo aparece cuando hace falta: estar conectado y sin cola es el caso normal
/// y no merece ni un píxel. Antes esto no existía porque los cambios sin red se
/// perdían en silencio; ahora se guardan, y el usuario tiene derecho a saber
/// que aún no están en el servidor.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
      child: status.needsAttention
          ? _Pill(status: status, key: const ValueKey('sync-pill'))
          : const SizedBox.shrink(key: ValueKey('sync-none')),
    );
  }
}

class _Pill extends ConsumerWidget {
  const _Pill({required this.status, super.key});

  final SyncStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // El ámbar se reserva para "pendiente pero a salvo"; el rojo diría que algo
    // se rompió, y aquí no se ha roto nada.
    final accent = status.online
        ? BentoTheme.accentOrange
        : BentoTheme.textSecondary;

    // Sin red no hay nada que reintentar: pulsar solo sirve cuando el problema
    // es que la cola todavía no ha salido.
    final onTap = status.online && !status.syncing
        ? () => ref.read(syncStatusProvider.notifier).sync()
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        child: NeuPressed(
          borderRadius: 999,
          lite: true,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Leading(status: status, accent: accent),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  _label(status),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: BentoTheme.textPrimary,
                  ),
                ),
              ),
              if (status.online && !status.syncing && status.hasPending) ...[
                const SizedBox(width: 8),
                Icon(Icons.refresh_rounded, size: 16, color: accent),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _label(SyncStatus status) {
    if (status.syncing) return 'Sincronizando…';

    if (!status.online) {
      return status.hasPending
          ? 'Sin conexión · ${_changes(status.pending)} por subir'
          : 'Sin conexión · los cambios se guardan aquí';
    }

    return '${_changes(status.pending)} sin sincronizar';
  }

  static String _changes(int n) => n == 1 ? '1 cambio' : '$n cambios';
}

class _Leading extends StatelessWidget {
  const _Leading({required this.status, required this.accent});

  final SyncStatus status;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (status.syncing) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: accent),
      );
    }

    return Icon(
      status.online ? Icons.cloud_upload_outlined : Icons.cloud_off_rounded,
      size: 16,
      color: accent,
    );
  }
}
