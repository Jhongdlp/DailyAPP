import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
                backgroundColor: BentoTheme.darkCard,
                title: Text('Eliminar alarma',
                    style: GoogleFonts.montserrat(fontWeight: FontWeight.w800, color: BentoTheme.cream)),
                content: Text('¿Eliminar "${alarm.label}"?',
                    style: TextStyle(color: BentoTheme.creamAlpha(0.7))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: TextButton.styleFrom(foregroundColor: BentoTheme.creamAlpha(0.7)),
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
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        borderRadius: 18,
        backgroundColor: BentoTheme.darkCardAlt.withValues(alpha: 0.60),
        child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (alarm.enabled)
                          const Padding(
                            padding: EdgeInsets.only(right: 10, bottom: 4),
                            child: _RingingBellIcon(),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(right: 10, bottom: 4),
                            child: Icon(
                              Icons.notifications_none_outlined,
                              size: 24,
                              color: BentoTheme.creamAlpha(0.24),
                            ),
                          ),
                        Text(
                          alarm.time12,
                          style: GoogleFonts.montserrat(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            letterSpacing: -0.5,
                            color: alarm.enabled
                                ? BentoTheme.cream
                                : BentoTheme.creamAlpha(0.35),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            alarm.amPm,
                            style: GoogleFonts.montserrat(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: alarm.enabled
                                  ? BentoTheme.accentOrange
                                  : BentoTheme.creamAlpha(0.35),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alarm.label,
                      style: GoogleFonts.montserrat(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: alarm.enabled
                            ? BentoTheme.cream
                            : BentoTheme.creamAlpha(0.4),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alarm.daysLabel,
                      style: GoogleFonts.montserrat(
                          fontSize: 12, color: BentoTheme.creamAlpha(0.45)),
                    ),
                    if (alarm.enabled && alarm.untilLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        alarm.untilLabel!,
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: BentoTheme.accentOrange,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.camera_alt_outlined,
                            size: 12, color: BentoTheme.creamAlpha(0.45)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            alarm.targetObject,
                            style: GoogleFonts.montserrat(
                                fontSize: 12, color: BentoTheme.creamAlpha(0.45)),
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
                activeThumbColor: BentoTheme.accentAlarm,
                activeTrackColor: BentoTheme.accentAlarm.withValues(alpha: 0.3),
                inactiveThumbColor: BentoTheme.creamAlpha(0.6),
                inactiveTrackColor: BentoTheme.creamAlpha(0.15),
                trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
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
      );
  }
}

class _RingingBellIcon extends StatefulWidget {
  const _RingingBellIcon();

  @override
  State<_RingingBellIcon> createState() => _RingingBellIconState();
}

class _RingingBellIconState extends State<_RingingBellIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final turns = 0.04 * math.sin(_controller.value * 2 * math.pi);
        return RotationTransition(
          turns: AlwaysStoppedAnimation(turns),
          alignment: Alignment.topCenter,
          child: Icon(
            Icons.notifications_active_outlined,
            size: 24,
            color: BentoTheme.accentAlarm,
          ),
        );
      },
    );
  }
}
