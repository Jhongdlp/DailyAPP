import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/alarm_model.dart';
import '../../core/providers/alarms_provider.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/utils/error_snackbar.dart';

class AlarmCard extends ConsumerWidget {
  final AlarmModel alarm;
  final VoidCallback onTap;

  const AlarmCard({super.key, required this.alarm, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: Key(alarm.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: BentoTheme.errorRed,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Eliminar alarma'),
                content: Text('¿Eliminar "${alarm.label}"?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar')),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Eliminar',
                        style: TextStyle(color: BentoTheme.errorRed)),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) async {
        try {
          await ref.read(alarmsProvider.notifier).deleteAlarm(alarm.id);
        } catch (e) {
          if (context.mounted) {
            showErrorSnackBar(context, message: 'No se pudo eliminar: $e');
          }
        }
      },
      child: GestureDetector(
        onTap: onTap,
        child: BentoCard(
          borderColor: BentoTheme.borderMuted,
          borderWidth: 1,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          alarm.time12,
                          style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            height: 1,
                            color: alarm.enabled
                                ? BentoTheme.textPrimary
                                : BentoTheme.textSecondary,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            alarm.amPm,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: alarm.enabled
                                  ? BentoTheme.accentOrange
                                  : BentoTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alarm.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: alarm.enabled
                            ? BentoTheme.textPrimary
                            : BentoTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alarm.daysLabel,
                      style: const TextStyle(
                          fontSize: 12, color: BentoTheme.textSecondary),
                    ),
                    if (alarm.enabled && alarm.untilLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        alarm.untilLabel!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: BentoTheme.accentOrange,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.camera_alt_outlined,
                            size: 12, color: BentoTheme.textSecondary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            alarm.targetObject,
                            style: const TextStyle(
                                fontSize: 12, color: BentoTheme.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: alarm.enabled,
                activeThumbColor: BentoTheme.primaryDark,
                activeTrackColor: BentoTheme.primaryDark.withValues(alpha: 0.2),
                onChanged: (val) async {
                  try {
                    await ref
                        .read(alarmsProvider.notifier)
                        .toggleAlarm(alarm.id, val);
                  } catch (e) {
                    if (context.mounted) {
                      showErrorSnackBar(context, message: 'No se pudo actualizar: $e');
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
