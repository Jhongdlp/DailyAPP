import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/exercise_model.dart';
import '../../../core/providers/exercise_provider.dart';
import '../../../core/services/synced_write.dart';
import '../../../core/theme/bento_theme.dart';

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
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _distanceController = TextEditingController(text: _formatNum(e?.distanceKm));
    _durationController = TextEditingController(text: _formatNum(e?.durationMinutes));
    _notesController = TextEditingController(text: e?.notes ?? '');
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
      id: existing?.id ?? newRowId(),
      userId: userId,
      habitId: widget.habitId ?? existing?.habitId,
      loggedDate: widget.forDate,
      distanceKm: km,
      durationMinutes: duration,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await ref.read(exerciseProvider.notifier).upsertLog(log);
    await ref.read(exerciseProvider.notifier).linkPhotosToLog(widget.forDate, log.id);

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
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _submit,
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
