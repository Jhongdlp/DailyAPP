import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/sleep_provider.dart';
import '../../../core/services/wake_check_service.dart';
import '../../../core/theme/bento_theme.dart';

/// "¿Sigues despierto?" — la comprobación que suena un rato después de apagar
/// la alarma.
///
/// Un solo toque, sin foto: ya demostraste con la cámara que te levantaste, y
/// volver a exigirla diez minutos después haría que acabaras ignorándola. La
/// alarma sigue sonando en bucle hasta que se pulsa, así que la presión la pone
/// el sonido, no la fricción.
class WakeCheckScreen extends ConsumerStatefulWidget {
  /// Id nativo de la alarma que está sonando. Se para siempre por este id, y no
  /// por el que haya en el estado, porque en arranque en frío la caché puede no
  /// haberse leído todavía y el usuario se quedaría con el sonido puesto.
  final int nativeId;

  const WakeCheckScreen({super.key, required this.nativeId});

  @override
  ConsumerState<WakeCheckScreen> createState() => _WakeCheckScreenState();
}

class _WakeCheckScreenState extends ConsumerState<WakeCheckScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    await WakeCheckService.cancel(widget.nativeId);
    await ref.read(sleepProvider.notifier).confirmAwake();
    if (mounted) Navigator.pop(context);
  }

  /// Reconoce la derrota con honestidad: se anota que te volviste a dormir y
  /// se para la vigilancia. Vale más un registro real que uno halagador.
  Future<void> _backToSleep() async {
    if (_busy) return;
    setState(() => _busy = true);
    final notifier = ref.read(sleepProvider.notifier);
    final nightKey = ref.read(sleepProvider).wakeCheck?.nightKey;
    await WakeCheckService.cancel(widget.nativeId);
    await notifier.cancelWakeCheck();
    if (nightKey != null) {
      // Se anota el momento actual como despertar real: si sigue durmiendo,
      // el check-in de la mañana lo corregirá.
      await notifier.registerBackToSleep(
        finalWakeAt: DateTime.now(),
        nightKey: nightKey,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(sleepProvider).wakeCheck;
    final minutesUp = pending == null
        ? null
        : DateTime.now().difference(pending.wokeAt).inMinutes;

    return PopScope(
      // No se sale con el botón atrás: eso es exactamente lo que haría alguien
      // medio dormido para volver a la cama.
      canPop: false,
      child: Scaffold(
        backgroundColor: BentoTheme.darkBg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: Tween<double>(begin: 0.94, end: 1.06).animate(
                    CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(26),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: BentoTheme.accentAlarm.withValues(alpha: 0.16),
                    ),
                    child: Icon(Icons.visibility_outlined,
                        size: 58, color: BentoTheme.accentAlarm),
                  ),
                ),
                const SizedBox(height: 34),
                Text(
                  '¿Sigues despierto?',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(
                    fontSize: 32,
                    height: 1.05,
                    letterSpacing: -1,
                    fontWeight: FontWeight.w800,
                    color: BentoTheme.cream,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  minutesUp == null
                      ? 'Confirma que no te has vuelto a la cama.'
                      : 'Llevas $minutesUp min levantado. '
                          'Confirma que no te has vuelto a la cama.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    height: 1.45,
                    color: BentoTheme.creamAlpha(0.55),
                  ),
                ),
                const SizedBox(height: 44),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BentoTheme.accentAlarm,
                      foregroundColor: const Color(0xFF0C0C0D),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      'Estoy despierto',
                      style: GoogleFonts.montserrat(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy ? null : _backToSleep,
                  child: Text(
                    'Me volví a dormir',
                    style: GoogleFonts.montserrat(
                      fontSize: 13,
                      color: BentoTheme.creamAlpha(0.45),
                    ),
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
