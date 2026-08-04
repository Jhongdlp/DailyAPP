import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/models/exercise_model.dart';
import '../../core/providers/exercise_provider.dart';
import '../../core/services/signed_url_cache.dart';
import '../../core/theme/bento_theme.dart';
import 'exercise_photo_viewer_screen.dart';
import 'exercise_stats.dart';
import 'widgets/exercise_log_form.dart';
import 'widgets/exercise_weekly_chart.dart';

const _exercisePhotosBucket = 'exercise-photos';

/// Pantalla de detalle: todo el avance por kilómetros, días y tiempo, sin
/// fotos de por medio. `habitId` solo se usa para precargar el hábito al
/// abrir el formulario de edición desde el historial.
class ExerciseStatsScreen extends ConsumerWidget {
  final String habitId;
  const ExerciseStatsScreen({super.key, required this.habitId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exerciseState = ref.watch(exerciseProvider);
    final stats = computeExerciseStats(exerciseState.logs);
    final logs =
        exerciseState.logs
            .where((l) => l.distanceKm != null || l.durationMinutes != null)
            .toList()
          ..sort((a, b) => b.loggedDate.compareTo(a.loggedDate));

    return Scaffold(
      backgroundColor: BentoTheme.darkBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _BackButton(onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 12),
                  Text(
                    'Detalles',
                    style: GoogleFonts.montserrat(
                      color: BentoTheme.cream,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.5,
                children: [
                  _MetricTile(
                    icon: Icons.map_outlined,
                    accent: BentoTheme.accentOrange,
                    value: '${stats.totalKmAll.toStringAsFixed(1)} km',
                    label: 'Total acumulado',
                  ),
                  _MetricTile(
                    icon: Icons.calendar_month,
                    accent: BentoTheme.accentBlue,
                    value: '${stats.sessionsAll}',
                    label: 'Sesiones registradas',
                  ),
                  _MetricTile(
                    icon: Icons.timer_outlined,
                    accent: BentoTheme.accentLime,
                    value: _formatMinutes(stats.totalMinutes30),
                    label: 'Tiempo en 30 días',
                  ),
                  _MetricTile(
                    icon: Icons.emoji_events_outlined,
                    accent: BentoTheme.accentPurple,
                    value: stats.bestDistance == null
                        ? '—'
                        : '${stats.bestDistance!.toStringAsFixed(1)} km',
                    label: 'Mejor carrera',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              NeuCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Últimas 8 semanas',
                      style: GoogleFonts.montserrat(
                        color: BentoTheme.cream,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ExerciseWeeklyChart(
                      weeks: stats.weeks,
                      color: BentoTheme.accentOrange,
                      height: 150,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Historial',
                style: GoogleFonts.montserrat(
                  color: BentoTheme.cream,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              if (logs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Todavía no hay carreras registradas.',
                    style: GoogleFonts.montserrat(
                      color: BentoTheme.creamAlpha(0.45),
                      fontSize: 13,
                    ),
                  ),
                )
              else
                Column(
                  children: [
                    for (final log in logs) ...[
                      _LogRow(
                        log: log,
                        onViewDetail: () => showExerciseLogForm(
                          context,
                          ref,
                          forDate: log.loggedDate,
                          habitId: habitId,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatMinutes(double minutes) {
    if (minutes <= 0) return '0 min';
    final hours = minutes ~/ 60;
    final mins = (minutes % 60).round();
    if (hours == 0) return '$mins min';
    return '${hours}h ${mins}min';
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: BentoTheme.creamAlpha(0.08),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: BentoTheme.creamAlpha(0.14)),
        ),
        child: Icon(Icons.arrow_back, size: 18, color: BentoTheme.cream),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String value;
  final String label;
  const _MetricTile({
    required this.icon,
    required this.accent,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.montserrat(
              color: BentoTheme.cream,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.montserrat(
              color: BentoTheme.creamAlpha(0.45),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de una sesión, plegable: al tocar el encabezado despliega la
/// captura de ruta adjunta (si hay) y un enlace "Ver detalle" que abre el
/// formulario de edición. La tarjeta no navega directo para no perder el
/// lugar en el historial cada vez que solo se quiere ver la ruta.
class _LogRow extends StatefulWidget {
  final ExerciseLog log;
  final VoidCallback onViewDetail;
  const _LogRow({required this.log, required this.onViewDetail});

  @override
  State<_LogRow> createState() => _LogRowState();
}

class _LogRowState extends State<_LogRow> {
  bool _expanded = false;

  Future<String> _signedUrl(String path) {
    return SignedUrlCache.get(_exercisePhotosBucket, path);
  }

  void _openRoutePhoto(String path) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => RoutePhotoViewerScreen(storagePath: path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final pace = log.computedPace;
    final routePhoto = log.routePhotoPath;

    return NeuCard(
      onTap: () => setState(() => _expanded = !_expanded),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: BentoTheme.accentOrange.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.directions_run,
                  color: BentoTheme.accentOrange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE d MMM', 'es').format(log.loggedDate),
                      style: GoogleFonts.montserrat(
                        color: BentoTheme.cream,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (log.distanceKm != null)
                          '${log.distanceKm!.toStringAsFixed(1)} km',
                        if (log.durationMinutes != null)
                          '${log.durationMinutes!.toStringAsFixed(0)} min',
                        if (pace != null) '${pace.toStringAsFixed(2)} min/km',
                      ].join(' · '),
                      style: GoogleFonts.montserrat(
                        color: BentoTheme.creamAlpha(0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (routePhoto != null) ...[
                Icon(
                  Icons.map_outlined,
                  color: BentoTheme.creamAlpha(0.35),
                  size: 16,
                ),
                const SizedBox(width: 6),
              ],
              AnimatedRotation(
                turns: _expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  Icons.chevron_right,
                  color: BentoTheme.creamAlpha(0.3),
                  size: 18,
                ),
              ),
            ],
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (routePhoto != null)
                    GestureDetector(
                      onTap: () => _openRoutePhoto(routePhoto),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: AspectRatio(
                          aspectRatio: 16 / 10,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              FutureBuilder<String>(
                                future: _signedUrl(routePhoto),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData) {
                                    return Container(
                                      color: BentoTheme.creamAlpha(0.06),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: BentoTheme.creamAlpha(0.4),
                                        ),
                                      ),
                                    );
                                  }
                                  return Image.network(
                                    snapshot.data!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      color: BentoTheme.creamAlpha(0.06),
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: BentoTheme.creamAlpha(0.4),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              Positioned(
                                right: 8,
                                bottom: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Colors.black45,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.zoom_in,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        'Sin ruta adjunta.',
                        style: GoogleFonts.montserrat(
                          color: BentoTheme.creamAlpha(0.4),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: widget.onViewDetail,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      child: Text(
                        'Ver detalle',
                        style: GoogleFonts.montserrat(
                          color: BentoTheme.accentOrange,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
