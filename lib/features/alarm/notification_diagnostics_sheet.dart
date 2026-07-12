import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/alarm_service.dart';
import '../../core/services/lock_task_service.dart';
import '../../core/theme/bento_theme.dart';

/// Panel de diagnóstico de notificaciones.
///
/// Muestra qué permisos concede realmente el sistema y cuántos recordatorios
/// tiene en cola, porque cuando una notificación no llega es imposible saber
/// desde la app si fue un permiso revocado, el ahorro de batería, o un fallo
/// al programar.
class NotificationDiagnosticsSheet extends StatefulWidget {
  const NotificationDiagnosticsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        backgroundColor: BentoTheme.darkBg,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => const NotificationDiagnosticsSheet(),
      );

  @override
  State<NotificationDiagnosticsSheet> createState() =>
      _NotificationDiagnosticsSheetState();
}

class _NotificationDiagnosticsSheetState
    extends State<NotificationDiagnosticsSheet> {
  NotificationDiagnostics? _diagnostics;
  bool _batteryExempt = true;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final diagnostics = await AlarmService.diagnose();
    final batteryExempt = await LockTaskService.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _diagnostics = diagnostics;
      _batteryExempt = batteryExempt;
    });
  }

  Future<void> _runTest(Future<String> Function() test, String label) async {
    setState(() => _testResult = '$label: ejecutando…');
    final result = await test();
    if (!mounted) return;
    setState(() => _testResult = '$label → $result');
  }

  @override
  Widget build(BuildContext context) {
    final d = _diagnostics;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'DIAGNÓSTICO DE NOTIFICACIONES',
              style: GoogleFonts.montserrat(
                fontSize: 12,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w600,
                color: BentoTheme.cream,
              ),
            ),
            const SizedBox(height: 18),
            if (d == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: BentoTheme.accentAlarm),
                ),
              )
            else ...[
              if (d.initError != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: BentoTheme.errorRed.withValues(alpha: 0.85),
                  ),
                  child: Text(
                    'El plugin de notificaciones no se inicializó. Ninguna '
                    'notificación puede mostrarse:\n\n${d.initError}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _CheckRow(
                label: 'Notificaciones permitidas',
                ok: d.notificationsEnabled,
                fixLabel: 'Activar',
                onFix: LockTaskService.openNotificationSettings,
              ),
              _CheckRow(
                label: 'Alarmas exactas permitidas',
                ok: d.exactAlarmsAllowed,
                detail: d.exactAlarmsAllowed
                    ? null
                    : 'Los recordatorios llegarán con retraso.',
                fixLabel: 'Ajustes',
                onFix: LockTaskService.openAppSettings,
              ),
              _CheckRow(
                label: 'Sin ahorro de batería',
                ok: _batteryExempt,
                detail: _batteryExempt
                    ? null
                    : 'El sistema puede matar los recordatorios.',
                fixLabel: 'Excluir',
                onFix: () async {
                  await LockTaskService.requestIgnoreBatteryOptimizations();
                  await _refresh();
                },
              ),
              const SizedBox(height: 14),
              _InfoRow('Zona horaria', d.timezone),
              _InfoRow('Notas en cola', '${d.pendingNotes}'),
              _InfoRow('Hábitos en cola', '${d.pendingHabits}'),
              _InfoRow('Otras en cola', '${d.pendingOther}'),
              _InfoRow('Alarmas programadas', '${d.scheduledAlarms}'),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _runTest(
                          AlarmService.testImmediateNotification, 'Inmediata'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BentoTheme.cream,
                        side: BorderSide(color: BentoTheme.creamAlpha(0.24)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Probar ahora'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _runTest(
                          AlarmService.testScheduledNotification, 'Programada'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BentoTheme.accentAlarm,
                        foregroundColor: const Color(0xFF0C0C0D),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Probar en 15 s',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: BentoTheme.creamAlpha(0.08),
                    border: Border.all(color: BentoTheme.creamAlpha(0.16)),
                  ),
                  child: SelectableText(
                    _testResult!,
                    style: GoogleFonts.robotoMono(
                      fontSize: 11,
                      color: BentoTheme.cream,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextButton(
                onPressed: _refresh,
                style: TextButton.styleFrom(
                    foregroundColor: BentoTheme.creamAlpha(0.55)),
                child: const Text('Refrescar'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final bool ok;
  final String? detail;
  final String fixLabel;
  final Future<void> Function() onFix;

  const _CheckRow({
    required this.label,
    required this.ok,
    required this.fixLabel,
    required this.onFix,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.cancel,
            size: 20,
            color: ok ? BentoTheme.successGreen : BentoTheme.errorRed,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.montserrat(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: BentoTheme.cream,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: GoogleFonts.montserrat(
                      fontSize: 11,
                      color: BentoTheme.creamAlpha(0.5),
                    ),
                  ),
              ],
            ),
          ),
          if (!ok)
            TextButton(
              onPressed: onFix,
              style: TextButton.styleFrom(
                foregroundColor: BentoTheme.accentAlarm,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(fixLabel,
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.montserrat(
              fontSize: 12,
              color: BentoTheme.creamAlpha(0.5),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.montserrat(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: BentoTheme.cream,
            ),
          ),
        ],
      ),
    );
  }
}
