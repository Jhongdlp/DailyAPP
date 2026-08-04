import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/achievement_catalog.dart';
import '../../../core/models/exercise_model.dart';
import '../../../core/providers/exercise_provider.dart';
import '../../../core/providers/rpg_provider.dart';
import '../../../core/services/synced_write.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/widgets/rpg_celebration.dart';

/// Abre el formulario de registro de una sesión (km/duración/notas) para
/// [forDate], opcionalmente ligada a [habitId]. Si ya existe una sesión ese
/// día, la precarga para editarla en vez de duplicarla.
Future<void> showExerciseLogForm(
  BuildContext context,
  WidgetRef ref, {
  required DateTime forDate,
  String? habitId,
}) {
  final existing = ref.read(exerciseProvider.notifier).logForDate(forDate);
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ExerciseLogFormSheet(forDate: forDate, habitId: habitId, existing: existing),
  );
}

class _ExerciseLogFormSheet extends ConsumerStatefulWidget {
  final DateTime forDate;
  final String? habitId;
  final ExerciseLog? existing;

  const _ExerciseLogFormSheet({required this.forDate, this.habitId, this.existing});

  @override
  ConsumerState<_ExerciseLogFormSheet> createState() => _ExerciseLogFormSheetState();
}

class _ExerciseLogFormSheetState extends ConsumerState<_ExerciseLogFormSheet> {
  late final TextEditingController _distanceController;
  late final TextEditingController _durationController;
  late final TextEditingController _notesController;
  late final String _logId;
  bool _saving = false;

  String? _routePhotoPath;
  File? _routePhotoPreview;
  bool _uploadingRoutePhoto = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _logId = e?.id ?? newRowId();
    _distanceController = TextEditingController(text: _formatNum(e?.distanceKm));
    _durationController = TextEditingController(text: _formatNum(e?.durationMinutes));
    _notesController = TextEditingController(text: e?.notes ?? '');
    _routePhotoPath = e?.routePhotoPath;
  }

  Future<void> _pickRoutePhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null || !mounted) return;

    final file = File(picked.path);
    setState(() {
      _routePhotoPreview = file;
      _uploadingRoutePhoto = true;
    });

    try {
      final path = await ref.read(exerciseProvider.notifier).uploadRoutePhoto(
            logId: _logId,
            file: file,
            previousPath: _routePhotoPath,
          );
      if (!mounted) return;
      setState(() {
        _routePhotoPath = path;
        _uploadingRoutePhoto = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadingRoutePhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo subir la captura: $e')),
      );
    }
  }

  void _removeRoutePhoto() {
    final path = _routePhotoPath;
    if (path != null) {
      Supabase.instance.client.storage.from('exercise-photos').remove([path]).catchError((_) => <FileObject>[]);
    }
    setState(() {
      _routePhotoPath = null;
      _routePhotoPreview = null;
    });
  }

  String _formatNum(double? v) {
    if (v == null) return '';
    return v % 1 == 0 ? v.toInt().toString() : v.toString();
  }

  double? get _pace {
    final km = double.tryParse(_distanceController.text.trim().replaceAll(',', '.'));
    final min = double.tryParse(_durationController.text.trim().replaceAll(',', '.'));
    if (km == null || km <= 0 || min == null) return null;
    return min / km;
  }

  @override
  void dispose() {
    _distanceController.dispose();
    _durationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final km = double.tryParse(_distanceController.text.trim().replaceAll(',', '.'));
    final duration = double.tryParse(_durationController.text.trim().replaceAll(',', '.'));
    if (km == null && duration == null) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _saving = true);
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final existing = widget.existing;
    final log = ExerciseLog(
      id: _logId,
      userId: userId,
      habitId: widget.habitId ?? existing?.habitId,
      loggedDate: widget.forDate,
      distanceKm: km,
      durationMinutes: duration,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
      routePhotoPath: _routePhotoPath,
    );

    await ref.read(exerciseProvider.notifier).upsertLog(log);
    await ref.read(exerciseProvider.notifier).linkPhotosToLog(widget.forDate, log.id);

    // Solo se premia la primera vez que se registra la sesión del día, para
    // que editar (p. ej. corregir el km) no farme XP infinito.
    if (existing == null) {
      final result = ref.read(rpgProvider.notifier).gainXpAndGold(
            10,
            5,
            counterKeys: const [RpgCounters.exerciseSessions],
            counterAmounts: km != null ? {RpgCounters.exerciseKm: km.round()} : const {},
          );
      if (mounted) {
        RpgCelebration.show(
          context,
          xp: result['xpGained'] as int,
          gold: result['goldGained'] as int,
          levelUp: result['levelUp'] as bool,
          newLevel: result['newLevel'] as int?,
        );
        AchievementToast.show(context, result['unlocked']);
      }
    }

    if (mounted) Navigator.of(context).pop();
  }

  InputDecoration _decoration(String hint, {String? suffix}) {
    return InputDecoration(
      hintText: hint,
      suffixText: suffix,
      hintStyle: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.35), fontWeight: FontWeight.w500),
      suffixStyle: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.5), fontWeight: FontWeight.w600),
      filled: true,
      fillColor: BentoTheme.creamAlpha(0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BentoTheme.creamAlpha(0.12))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BentoTheme.creamAlpha(0.12))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: BentoTheme.accentOrange, width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pace = _pace;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: NeuCard(
          radius: const BorderRadius.vertical(top: Radius.circular(28)),
          elevation: 22,
          convex: false,
          padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + MediaQuery.viewPaddingOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: NeuPressed(
                    borderRadius: 3,
                    distance: 2,
                    blur: 3,
                    child: const SizedBox(width: 40, height: 5),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Registrar carrera',
                  style: GoogleFonts.montserrat(color: BentoTheme.cream, fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _distanceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
                  decoration: _decoration('Distancia', suffix: 'km'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _durationController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
                  decoration: _decoration('Duración', suffix: 'min'),
                  onChanged: (_) => setState(() {}),
                ),
                if (pace != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Ritmo: ${pace.toStringAsFixed(2)} min/km',
                    style: GoogleFonts.montserrat(color: BentoTheme.accentOrange, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w500),
                  decoration: _decoration('Notas (opcional)'),
                ),
                const SizedBox(height: 16),
                _RoutePhotoField(
                  path: _routePhotoPath,
                  preview: _routePhotoPreview,
                  uploading: _uploadingRoutePhoto,
                  onPick: _pickRoutePhoto,
                  onRemove: _removeRoutePhoto,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving || _uploadingRoutePhoto ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BentoTheme.accentOrange,
                      foregroundColor: const Color(0xFF0C0C0D),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0C0C0D)))
                        : Text('Guardar', style: GoogleFonts.montserrat(fontWeight: FontWeight.w800, fontSize: 15)),
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

/// Adjuntar/reemplazar/quitar la captura de la ruta (p. ej. de Strava).
/// Sin clasificación IA ni subida en segundo plano: se sube al elegirla y
/// el botón "Guardar" ya espera con la ruta resuelta.
class _RoutePhotoField extends StatelessWidget {
  final String? path;
  final File? preview;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _RoutePhotoField({
    required this.path,
    required this.preview,
    required this.uploading,
    required this.onPick,
    required this.onRemove,
  });

  Future<String> _signedUrl(String storagePath) {
    return Supabase.instance.client.storage.from('exercise-photos').createSignedUrl(storagePath, 3600);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = preview != null || path != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ruta (captura de Strava)',
          style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.6), fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (hasPhoto)
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (preview != null)
                        Image.file(preview!, fit: BoxFit.cover)
                      else if (path != null)
                        FutureBuilder<String>(
                          future: _signedUrl(path!),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return Container(color: BentoTheme.creamAlpha(0.06));
                            }
                            return Image.network(snapshot.data!, fit: BoxFit.cover);
                          },
                        ),
                      if (uploading)
                        Container(
                          color: Colors.black45,
                          child: const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: uploading ? null : onPick,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                      child: Text('Reemplazar', style: GoogleFonts.montserrat(color: BentoTheme.accentOrange, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                    TextButton(
                      onPressed: uploading ? null : onRemove,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                      child: Text('Quitar', style: GoogleFonts.montserrat(color: BentoTheme.errorRed, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ],
          )
        else
          OutlinedButton.icon(
            onPressed: onPick,
            icon: Icon(Icons.map_outlined, size: 18, color: BentoTheme.creamAlpha(0.8)),
            label: Text('Adjuntar captura de Strava', style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w700, fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: BentoTheme.cream,
              side: BorderSide(color: BentoTheme.creamAlpha(0.2)),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
      ],
    );
  }
}
