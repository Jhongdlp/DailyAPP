import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/alarms_provider.dart';
import '../../core/theme/bento_theme.dart';
import 'alarm_card.dart';
import 'alarm_form.dart';

class AlarmTab extends ConsumerWidget {
  const AlarmTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarmsAsync = ref.watch(alarmsProvider);

    return Stack(
      children: [
        alarmsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: BentoTheme.primaryDark),
          ),
          error: (e, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    size: 48, color: BentoTheme.errorRed),
                const SizedBox(height: 8),
                Text(
                  'Error al cargar alarmas',
                  style: const TextStyle(
                      color: BentoTheme.textSecondary,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(alarmsProvider),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
          data: (alarms) {
            if (alarms.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: BentoTheme.accentOrange.withValues(alpha: 0.1),
                        ),
                        child: const Icon(Icons.alarm_add,
                            size: 56, color: BentoTheme.accentOrange),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Sin alarmas',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: BentoTheme.textPrimary),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Toca + para crear tu primera alarma inteligente. La IA te obliga a levantarte.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: BentoTheme.textSecondary, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
              itemCount: alarms.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (ctx, i) => AlarmCard(
                alarm: alarms[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AlarmForm(alarm: alarms[i]),
                  ),
                ),
              ),
            );
          },
        ),

        // FAB para agregar
        Positioned(
          bottom: 16,
          right: 20,
          child: FloatingActionButton(
            heroTag: 'alarm_fab',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AlarmForm()),
            ),
            backgroundColor: BentoTheme.accentOrange,
            foregroundColor: Colors.white,
            elevation: 2,
            child: const Icon(Icons.add, size: 28),
          ),
        ),
      ],
    );
  }
}
