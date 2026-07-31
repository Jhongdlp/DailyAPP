import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/sleep_model.dart';
import '../../../core/providers/sleep_provider.dart';
import '../../../core/theme/bento_theme.dart';
import 'sleep_schedule_form.dart';
import 'widgets/consistency_chart.dart';
import 'widgets/duration_quality_scatter.dart';
import 'widgets/sleep_chart_shell.dart';
import 'widgets/sleep_clock_heatmap.dart';
import 'widgets/sleep_debt_ring.dart';
import 'widgets/sleep_duration_bars.dart';
import 'widgets/sleep_kpi_row.dart';
import 'widgets/sleep_window_chart.dart';
import 'widgets/snooze_strip.dart';

/// Panel de calidad de sueño.
///
/// El orden de los bloques va de la respuesta al porqué: primero las cifras,
/// luego la forma de tus noches, después lo que te está costando (deuda,
/// snooze) y al final lo que puedes ajustar (consistencia, duración óptima).
class SleepDashboardScreen extends ConsumerWidget {
  const SleepDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(sleepProvider);
    final analytics = ref.watch(sleepAnalyticsProvider);
    final nights = data.sessions.values.toList();

    return Scaffold(
      backgroundColor: BentoTheme.darkBg,
      appBar: AppBar(
        backgroundColor: BentoTheme.darkBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: BentoTheme.cream),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Calidad de sueño',
          style: GoogleFonts.montserrat(
            color: BentoTheme.cream,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Horario de sueño',
            icon: Icon(Icons.tune, color: BentoTheme.cream),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SleepScheduleForm()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 40),
        children: [
          _TonightBanner(data: data),
          SleepKpiRow(analytics: analytics),
          SleepWindowChart(analytics: analytics, nights: nights),
          SleepDurationBars(analytics: analytics),
          SleepDebtRing(analytics: analytics),
          SnoozeStrip(analytics: analytics, nights: nights),
          ConsistencyChart(analytics: analytics),
          DurationQualityScatter(analytics: analytics),
          SleepClockHeatmap(nights: nights),
          if (kDebugMode) const _DebugTools(),
        ],
      ),
    );
  }
}

/// Estado de esta noche arriba del todo: sin esto el panel es solo historia y
/// no dice qué toca hacer ahora.
class _TonightBanner extends ConsumerWidget {
  final SleepData data;

  const _TonightBanner({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = data.schedule;
    final open = data.openNight;

    String text;
    IconData icon;

    if (!schedule.enabled) {
      text = 'Configura tu horario para empezar a registrar noches.';
      icon = Icons.bedtime_outlined;
    } else if (open?.lightsOutAt != null) {
      final at = open!.lightsOutAt!;
      text = 'Ciclo en curso desde las '
          '${at.hour.toString().padLeft(2, '0')}:'
          '${at.minute.toString().padLeft(2, '0')}.';
      icon = Icons.nightlight_round;
    } else {
      final next = schedule.nextBedtime();
      if (next == null) {
        text = 'Sin días activos en tu horario.';
        icon = Icons.bedtime_off_outlined;
      } else {
        final diff = next.difference(DateTime.now());
        final hours = diff.inHours;
        final mins = diff.inMinutes % 60;
        text = 'Te toca dormir en '
            '${hours > 0 ? '$hours h $mins min' : '$mins min'} '
            '(${schedule.formattedBedtime}).';
        icon = Icons.bedtime_outlined;
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: BentoTheme.accentAlarm.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: BentoTheme.accentAlarm),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.montserrat(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: BentoTheme.cream,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sembrar y borrar datos de prueba. Sin esto, revisar los ocho gráficos
/// obligaría a esperar un mes de noches reales.
class _DebugTools extends ConsumerWidget {
  const _DebugTools();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SleepChartShell(
      title: 'DEBUG',
      subtitle: 'Solo visible en builds de desarrollo.',
      available: 1,
      minimum: 1,
      child: Row(
        children: [
          TextButton(
            onPressed: () =>
                ref.read(sleepProvider.notifier).seedDemoNights(30),
            child: Text('Sembrar 30 noches',
                style: GoogleFonts.montserrat(
                    fontSize: 12, color: BentoTheme.accentAlarm)),
          ),
          TextButton(
            onPressed: () => ref.read(sleepProvider.notifier).clearHistory(),
            child: Text('Borrar historial',
                style: GoogleFonts.montserrat(
                    fontSize: 12, color: BentoTheme.errorRed)),
          ),
        ],
      ),
    );
  }
}
