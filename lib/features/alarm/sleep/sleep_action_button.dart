import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/sleep_model.dart';
import '../../../core/providers/alarms_provider.dart';
import '../../../core/providers/sleep_provider.dart';
import '../../../core/theme/bento_theme.dart';
import 'sleep_check_in_screen.dart';

/// Los dos botones que cierran el ciclo a mano: **Voy a dormir** y
/// **Ya desperté**.
///
/// Existen porque depender de la notificación era frágil: basta con barrer el
/// panel de notificaciones para quedarte sin forma de confirmar, y la noche se
/// quedaba sin registrar. Aquí el control está siempre donde el usuario ya
/// está mirando.
class SleepActionButton extends ConsumerStatefulWidget {
  /// En el panel de Calidad de sueño el botón se muestra siempre (permite
  /// acostarse antes de hora); en la pestaña de alarmas solo aparece cuando
  /// toca, para no añadir ruido permanente.
  final bool alwaysVisible;

  const SleepActionButton({super.key, this.alwaysVisible = false});

  @override
  ConsumerState<SleepActionButton> createState() => _SleepActionButtonState();
}

class _SleepActionButtonState extends ConsumerState<SleepActionButton> {
  bool _busy = false;
  Timer? _ticker;

  /// Margen antes de la hora de dormir en el que el botón aparece solo.
  static const _windowBefore = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    // El botón depende de la hora actual, no solo del estado: sin este latido
    // no aparecería hasta que algo más provocara un rebuild.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _goToSleep() async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    await ref.read(sleepProvider.notifier).confirmBedtime();
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: const Text('Buenas noches. Ciclo de sueño iniciado.'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          backgroundColor: BentoTheme.accentAlarm,
        ),
      );
    }
  }

  Future<void> _wakeUp() async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();

    // Pasar la alarma de sueño arranca la verificación de vigilia, igual que
    // al apagar la alarma con la foto.
    final sleepAlarm = ref.read(sleepAlarmProvider);
    final session = await ref.read(sleepProvider.notifier).registerWake(
          alarmId: sleepAlarm?.id,
        );

    if (!mounted) return;
    setState(() => _busy = false);

    if (session?.timeInBed != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SleepCheckInScreen(nightKey: session!.nightKey),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(sleepProvider);
    final sleepAlarm = ref.watch(sleepAlarmProvider);

    final open = data.openNight;
    final sleeping = open?.lightsOutAt != null && open?.wokeAt == null;

    if (sleeping) {
      return _Button(
        icon: Icons.wb_sunny_outlined,
        label: 'Ya desperté',
        // Contraste invertido respecto a "voy a dormir": por la mañana este es
        // el único botón que importa.
        background: BentoTheme.accentOrange,
        foreground: const Color(0xFF0C0C0D),
        busy: _busy,
        onTap: _wakeUp,
        caption: open?.lightsOutAt == null
            ? null
            : 'Dormiste desde las '
                '${open!.lightsOutAt!.hour.toString().padLeft(2, '0')}:'
                '${open.lightsOutAt!.minute.toString().padLeft(2, '0')}',
      );
    }

    // Ya se registró el despertar de hoy: no hay nada que pulsar todavía.
    final todayKey = nightKeyFor(DateTime.now());
    final todayDone = data.sessions[todayKey]?.wokeAt != null;

    final untilBedtime = sleepAlarm?.nextBedtime()?.difference(DateTime.now());
    final nearBedtime = untilBedtime != null && untilBedtime <= _windowBefore;

    if (!widget.alwaysVisible && !nearBedtime) return const SizedBox.shrink();
    if (widget.alwaysVisible && sleepAlarm == null) {
      return const SizedBox.shrink();
    }

    String? caption;
    if (untilBedtime != null) {
      final mins = untilBedtime.inMinutes;
      if (mins <= 0) {
        caption = 'Ya pasó tu hora de dormir';
      } else if (mins < 60) {
        caption = 'Te toca dormir en $mins min';
      } else if (todayDone || widget.alwaysVisible) {
        caption = 'Tu hora es a las ${sleepAlarm!.formattedBedtime}';
      }
    }

    return _Button(
      icon: Icons.bedtime_outlined,
      label: 'Voy a dormir',
      background: BentoTheme.accentAlarm,
      foreground: const Color(0xFF0C0C0D),
      busy: _busy,
      onTap: _goToSleep,
      caption: caption,
    );
  }
}

class _Button extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? caption;
  final Color background;
  final Color foreground;
  final bool busy;
  final VoidCallback onTap;

  const _Button({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.busy,
    required this.onTap,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                if (busy)
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: foreground),
                  )
                else
                  Icon(icon, size: 22, color: foreground),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.montserrat(
                          fontSize: 17,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: foreground,
                        ),
                      ),
                      if (caption != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          caption!,
                          style: GoogleFonts.montserrat(
                            fontSize: 11,
                            color: foreground.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
