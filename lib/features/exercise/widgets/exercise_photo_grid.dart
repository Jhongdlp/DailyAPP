import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/exercise_model.dart';
import '../../../core/providers/exercise_provider.dart';
import '../../../core/theme/bento_theme.dart';

/// Grid de fotos de progreso agrupadas por fecha, más recientes primero.
/// Usado por la Galería (no por la pestaña principal, que ya no muestra
/// fotos de entrada).
class ExercisePhotoGrid extends ConsumerWidget {
  final void Function(ExercisePhoto photo)? onTapPhoto;
  const ExercisePhotoGrid({super.key, this.onTapPhoto});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(exerciseProvider);
    final byDate = ref.watch(exerciseProvider.notifier).photosByDate();
    if (byDate.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Todavía no hay fotos de progreso.',
          style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.5), fontSize: 13),
        ),
      );
    }

    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final day in dates) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text(
              DateFormat('EEEE d MMM', 'es').format(day),
              style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.6), fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final photo in byDate[day]!)
                _PhotoThumb(photo: photo, onTap: onTapPhoto == null ? null : () => onTapPhoto!(photo)),
            ],
          ),
        ],
      ],
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final ExercisePhoto photo;
  final VoidCallback? onTap;
  const _PhotoThumb({required this.photo, this.onTap});

  Future<String> _signedUrl() async {
    final res = await Supabase.instance.client.storage
        .from('exercise-photos')
        .createSignedUrl(photo.storagePath, 3600);
    return res;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            SizedBox(
              width: 104,
              height: 104,
              child: photo.localFile != null
                  ? Image.file(photo.localFile!, fit: BoxFit.cover)
                  : FutureBuilder<String>(
                      future: _signedUrl(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return Container(
                            color: BentoTheme.creamAlpha(0.06),
                            child: Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: BentoTheme.creamAlpha(0.4)),
                              ),
                            ),
                          );
                        }
                        return Image.network(
                          snapshot.data!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: BentoTheme.creamAlpha(0.06),
                            child: Icon(Icons.broken_image_outlined, color: BentoTheme.creamAlpha(0.4)),
                          ),
                        );
                      },
                    ),
            ),
            Positioned(
              left: 4,
              bottom: 4,
              child: _ClassificationBadge(classification: photo.classification),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassificationBadge extends StatelessWidget {
  final PhotoClassification classification;
  const _ClassificationBadge({required this.classification});

  @override
  Widget build(BuildContext context) {
    if (classification == PhotoClassification.pending || classification == PhotoClassification.classifying) {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
        child: const SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
        ),
      );
    }
    if (classification == PhotoClassification.failed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: BentoTheme.errorRed.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.refresh, color: Colors.white, size: 12),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
      child: Text(
        classification.label,
        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
      ),
    );
  }
}
