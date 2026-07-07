import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/alarm_model.dart';
import '../../core/providers/alarms_provider.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/utils/error_snackbar.dart';
import 'widgets/bento_time_picker.dart';

class AlarmForm extends ConsumerStatefulWidget {
  final AlarmModel? alarm;

  const AlarmForm({super.key, this.alarm});

  @override
  ConsumerState<AlarmForm> createState() => _AlarmFormState();
}

class _AlarmFormState extends ConsumerState<AlarmForm> {
  late TimeOfDay _time;
  late Set<int> _days;
  late TextEditingController _labelCtrl;
  late TextEditingController _objectCtrl;
  bool _saving = false;

  static const _suggestions = [
    'Taza de café',
    'Lavamanos del baño',
    'Cafetera',
    'Medicamento',
  ];

  static const _labelSuggestions = [
    'Despertar',
    'Ir al gym',
    'Estudiar',
  ];

  static const _dayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
  static const _weekdays = {1, 2, 3, 4, 5};
  static const _weekend = {6, 7};
  static const _allDays = {1, 2, 3, 4, 5, 6, 7};

  @override
  void initState() {
    super.initState();
    final a = widget.alarm;
    _time = a != null
        ? TimeOfDay(hour: a.hour, minute: a.minute)
        : const TimeOfDay(hour: 7, minute: 0);
    _days = a != null ? Set.of(a.daysOfWeek) : {1, 2, 3, 4, 5, 6, 7};
    _labelCtrl = TextEditingController(text: a?.label ?? '');
    _objectCtrl = TextEditingController(text: a?.targetObject ?? 'Taza de café');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _objectCtrl.dispose();
    super.dispose();
  }

  /// Texto en vivo de cuánto falta para que suene con la hora/días elegidos
  String get _untilPreview {
    final preview = AlarmModel(
      id: '',
      userId: '',
      enabled: true,
      hour: _time.hour,
      minute: _time.minute,
      targetObject: '',
      label: '',
      daysOfWeek: _days.toList(),
      createdAt: DateTime.now(),
    );
    return preview.untilLabel ?? 'Selecciona al menos un día';
  }

  Future<void> _save() async {
    if (_objectCtrl.text.trim().isEmpty) {
      showErrorSnackBar(context, message: 'Escribe el objeto a fotografiar');
      return;
    }
    if (_days.isEmpty) {
      showErrorSnackBar(context, message: 'Selecciona al menos un día');
      return;
    }

    setState(() => _saving = true);

    try {
      final notifier = ref.read(alarmsProvider.notifier);
      final daysOrdered = _days.toList()..sort();
      final labelText =
          _labelCtrl.text.trim().isEmpty ? 'Alarma' : _labelCtrl.text.trim();
      final objectText = _objectCtrl.text.trim();

      if (widget.alarm == null) {
        final placeholder = AlarmModel(
          id: '',
          userId: '',
          enabled: true,
          hour: _time.hour,
          minute: _time.minute,
          targetObject: objectText,
          label: labelText,
          daysOfWeek: daysOrdered,
          createdAt: DateTime.now(),
        );
        await notifier.addAlarm(placeholder);
      } else {
        final updated = widget.alarm!.copyWith(
          hour: _time.hour,
          minute: _time.minute,
          targetObject: objectText,
          label: labelText,
          daysOfWeek: daysOrdered,
        );
        await notifier.updateAlarm(updated);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, message: 'Error al guardar: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final nav = Navigator.of(context);
    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: BentoTheme.darkCard,
            title: Text('Eliminar alarma',
                style: GoogleFonts.montserrat(fontWeight: FontWeight.w800, color: BentoTheme.cream)),
            content: Text('¿Estás seguro?', style: TextStyle(color: BentoTheme.creamAlpha(0.7))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(foregroundColor: BentoTheme.creamAlpha(0.7)),
                  child: const Text('Cancelar')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Eliminar',
                    style: TextStyle(color: BentoTheme.errorRed)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      await ref.read(alarmsProvider.notifier).deleteAlarm(widget.alarm!.id);
      if (mounted) nav.pop();
    } catch (e) {
      if (mounted) showErrorSnackBar(context, message: 'Error al eliminar: $e');
    }
  }

  Widget _sectionTitle(String text, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text,
            style: GoogleFonts.montserrat(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: BentoTheme.cream)),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle,
              style: GoogleFonts.montserrat(
                  fontSize: 12, color: BentoTheme.creamAlpha(0.55))),
        ],
      ],
    );
  }

  Widget _divider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Divider(height: 1, thickness: 1, color: BentoTheme.creamAlpha(0.12)),
      );

  Widget _chip(String label, {required bool active, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: active ? BentoTheme.accentAlarm : BentoTheme.darkCardAlt,
          border: active ? null : Border.all(color: BentoTheme.creamAlpha(0.14)),
        ),
        child: Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? const Color(0xFF0C0C0D) : BentoTheme.creamAlpha(0.55),
          ),
        ),
      ),
    );
  }

  bool _sameDays(Set<int> preset) =>
      _days.length == preset.length && _days.containsAll(preset);

  InputDecoration _darkInputDecoration({required String hint, required IconData icon, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: BentoTheme.creamAlpha(0.3)),
      prefixIcon: Icon(icon, color: BentoTheme.creamAlpha(0.55)),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: BentoTheme.darkCardAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: BentoTheme.creamAlpha(0.14)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: BentoTheme.creamAlpha(0.14)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: BentoTheme.accentAlarm, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BentoTheme.darkBg,
      appBar: AppBar(
        backgroundColor: BentoTheme.darkBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: BentoTheme.cream),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.alarm == null ? 'Nueva Alarma' : 'Editar Alarma',
          style: GoogleFonts.montserrat(
              color: BentoTheme.cream, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (widget.alarm != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: BentoTheme.errorRed),
              onPressed: _delete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hora — único elemento con caja, es el foco principal
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: BentoTheme.darkCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: BentoTheme.accentAlarm, width: 1.5),
              ),
              child: Column(
                children: [
                  BentoTimePicker(
                    initialTime: _time,
                    onChanged: (t) => setState(() => _time = t),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.notifications_active_outlined,
                          size: 14, color: BentoTheme.accentOrange),
                      const SizedBox(width: 6),
                      Text(
                        _untilPreview,
                        style: GoogleFonts.montserrat(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: BentoTheme.accentOrange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            _divider(),

            // Objeto objetivo — es el campo obligatorio, va primero
            _sectionTitle(
              'Objeto a fotografiar',
              subtitle:
                  'La IA validará que estés con este objeto para apagar la alarma',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _objectCtrl,
              style: const TextStyle(color: BentoTheme.cream),
              onChanged: (_) => setState(() {}),
              decoration: _darkInputDecoration(
                hint: 'Ej: Taza de café',
                icon: Icons.camera_alt_outlined,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _suggestions
                  .map((s) => _chip(s,
                      active: _objectCtrl.text == s,
                      onTap: () => setState(() => _objectCtrl.text = s)))
                  .toList(),
            ),

            _divider(),

            // Días de la semana con presets rápidos
            _sectionTitle('Repetir'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('Todos los días',
                    active: _sameDays(_allDays),
                    onTap: () => setState(() => _days = Set.of(_allDays))),
                _chip('Lun – Vie',
                    active: _sameDays(_weekdays),
                    onTap: () => setState(() => _days = Set.of(_weekdays))),
                _chip('Fin de semana',
                    active: _sameDays(_weekend),
                    onTap: () => setState(() => _days = Set.of(_weekend))),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(7, (i) {
                final day = i + 1;
                final active = _days.contains(day);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (active) {
                        _days.remove(day);
                      } else {
                        _days.add(day);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? BentoTheme.accentAlarm
                          : BentoTheme.darkCardAlt,
                      border: active ? null : Border.all(color: BentoTheme.creamAlpha(0.14)),
                    ),
                    child: Center(
                      child: Text(
                        _dayLabels[i],
                        style: TextStyle(
                          color: active
                              ? const Color(0xFF0C0C0D)
                              : BentoTheme.creamAlpha(0.55),
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),

            _divider(),

            // Nombre — opcional, al final y sin caja para restar peso visual
            _sectionTitle('Nombre (opcional)'),
            const SizedBox(height: 12),
            TextField(
              controller: _labelCtrl,
              style: const TextStyle(color: BentoTheme.cream),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: _darkInputDecoration(
                hint: 'Ej: Despertar mañana',
                icon: Icons.label_outline,
                suffixIcon: _labelCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear,
                            size: 18, color: BentoTheme.creamAlpha(0.55)),
                        onPressed: () => setState(() => _labelCtrl.clear()),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _labelSuggestions
                  .map((s) => _chip(s,
                      active: _labelCtrl.text == s,
                      onTap: () => setState(() => _labelCtrl.text = s)))
                  .toList(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: BentoTheme.creamAlpha(0.12))),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: BentoTheme.accentAlarm,
                foregroundColor: const Color(0xFF0C0C0D),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF0C0C0D)))
                  : const Icon(Icons.check),
              label: Text(
                widget.alarm == null ? 'Crear alarma' : 'Guardar cambios',
                style: GoogleFonts.montserrat(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
