import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/exercise_model.dart';
import '../../core/providers/exercise_provider.dart';
import '../../core/theme/bento_theme.dart';
import 'exercise_photo_viewer_screen.dart';
import 'widgets/exercise_photo_grid.dart';

/// Todas las fotos de progreso, agrupadas por fecha. Vive aparte de la
/// pestaña principal a propósito: el resumen de Ejercicio se lee con
/// números, la Galería se recorre con la vista.
class ExerciseGalleryScreen extends ConsumerWidget {
  const ExerciseGalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(exerciseProvider).photos;

    return Scaffold(
      backgroundColor: BentoTheme.darkBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
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
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Galería',
                    style: GoogleFonts.montserrat(color: BentoTheme.cream, fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                child: ExercisePhotoGrid(
                  onTapPhoto: (photo) => _openViewer(context, photos, photo),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, List<ExercisePhoto> allPhotos, ExercisePhoto tapped) {
    final ordered = [...allPhotos]..sort((a, b) => b.loggedDate.compareTo(a.loggedDate));
    final index = ordered.indexWhere((p) => p.id == tapped.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ExercisePhotoViewerScreen(photos: ordered, initialIndex: index < 0 ? 0 : index),
      ),
    );
  }
}
