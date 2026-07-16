import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/providers/alarms_provider.dart';
import '../../core/theme/bento_theme.dart';
import '../habits/widgets/habit_blob_header.dart';
import 'alarm_card.dart';
import 'alarm_form.dart';
import 'notification_diagnostics_sheet.dart';

class AlarmTab extends ConsumerWidget {
  const AlarmTab({super.key});

  Widget _buildHeader(BuildContext context) {
    return SizedBox(
      height: 92,
      child: Stack(
        children: [
          Positioned.fill(child: HabitBlobHeader(accentColor: BentoTheme.accentAlarm)),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                'Alarma',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w800,
                  fontSize: 42,
                  height: 0.92,
                  letterSpacing: -1.4,
                  color: BentoTheme.cream,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, WidgetRef ref, int totalCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'TUS ALARMAS',
                style: GoogleFonts.montserrat(fontSize: 12, letterSpacing: 2.4, fontWeight: FontWeight.w600, color: BentoTheme.cream),
              ),
              const SizedBox(width: 10),
              Text(
                '${totalCount.toString().padLeft(2, '0')} en total',
                style: GoogleFonts.montserrat(fontSize: 11, letterSpacing: 1.1, color: BentoTheme.creamAlpha(0.4)),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => NotificationDiagnosticsSheet.show(context),
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(Icons.health_and_safety_outlined,
                      size: 20, color: BentoTheme.creamAlpha(0.55)),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AlarmForm()),
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                  decoration: BoxDecoration(color: BentoTheme.accentAlarm, borderRadius: BorderRadius.circular(100)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, size: 13, color: Color(0xFF0C0C0D)),
                      const SizedBox(width: 6),
                      Text(
                        'Nueva',
                        style: GoogleFonts.montserrat(fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: const Color(0xFF0C0C0D)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarmsAsync = ref.watch(alarmsProvider);

    return Container(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSectionHeader(context, ref, alarmsAsync.value?.length ?? 0),
                Expanded(
                  child: alarmsAsync.when(
                    loading: () => Center(
                      child: CircularProgressIndicator(color: BentoTheme.accentAlarm),
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
                            style: GoogleFonts.montserrat(
                                color: BentoTheme.creamAlpha(0.55),
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => ref.invalidate(alarmsProvider),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: BentoTheme.accentAlarm,
                              foregroundColor: const Color(0xFF0C0C0D),
                            ),
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
                                    color: BentoTheme.accentOrange.withValues(alpha: 0.14),
                                  ),
                                  child: Icon(Icons.alarm_add,
                                      size: 56, color: BentoTheme.accentOrange),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Sin alarmas',
                                  style: GoogleFonts.montserrat(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: BentoTheme.cream),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Toca + para crear tu primera alarma inteligente. La IA te obliga a levantarte.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.montserrat(
                                      color: BentoTheme.creamAlpha(0.55), fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(22, 4, 22, 110),
                        itemCount: alarms.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
