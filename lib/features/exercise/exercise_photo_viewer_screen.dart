import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/exercise_model.dart';
import '../../core/providers/exercise_provider.dart';
import '../../core/theme/bento_theme.dart';

/// Visor a pantalla completa, deslizable entre fotos, con zoom y borrado.
class ExercisePhotoViewerScreen extends ConsumerStatefulWidget {
  final List<ExercisePhoto> photos;
  final int initialIndex;
  const ExercisePhotoViewerScreen({super.key, required this.photos, required this.initialIndex});

  @override
  ConsumerState<ExercisePhotoViewerScreen> createState() => _ExercisePhotoViewerScreenState();
}

class _ExercisePhotoViewerScreenState extends ConsumerState<ExercisePhotoViewerScreen> {
  late final PageController _controller;
  late List<ExercisePhoto> _photos;
  late int _index;

  @override
  void initState() {
    super.initState();
    _photos = widget.photos;
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final photo = _photos[_index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BentoTheme.darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: BentoTheme.errorRed.withValues(alpha: 0.6), width: 1.5),
        ),
        title: Text('¿Eliminar foto?', style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w700)),
        content: Text(
          'Esta foto de progreso se eliminará permanentemente.',
          style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar', style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.6), fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: BentoTheme.errorRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(exerciseProvider.notifier).deletePhoto(photo);
    if (!mounted) return;

    final remaining = [..._photos]..removeAt(_index);
    if (remaining.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _photos = remaining;
      _index = _index >= remaining.length ? remaining.length - 1 : _index;
    });
    _controller.jumpToPage(_index);
  }

  Future<String> _signedUrl(ExercisePhoto photo) {
    return Supabase.instance.client.storage.from('exercise-photos').createSignedUrl(photo.storagePath, 3600);
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photos[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: _photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final p = _photos[i];
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: p.localFile != null
                        ? Image.file(p.localFile!, fit: BoxFit.contain)
                        : FutureBuilder<String>(
                            future: _signedUrl(p),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const CircularProgressIndicator(color: Colors.white54);
                              }
                              return Image.network(
                                snapshot.data!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
                              );
                            },
                          ),
                  ),
                );
              },
            ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _RoundIconButton(icon: Icons.close, onTap: () => Navigator.pop(context)),
                  _RoundIconButton(icon: Icons.delete_outline, onTap: _confirmDelete, color: BentoTheme.errorRed),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Column(
                children: [
                  Text(
                    DateFormat('EEEE d MMM yyyy', 'es').format(photo.loggedDate),
                    style: GoogleFonts.montserrat(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${photo.classification.label} · ${_index + 1}/${_photos.length}',
                    style: GoogleFonts.montserrat(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  const _RoundIconButton({required this.icon, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
        child: Icon(icon, color: color ?? Colors.white, size: 20),
      ),
    );
  }
}
