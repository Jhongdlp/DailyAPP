import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/alarm_model.dart';
import '../../core/providers/alarms_provider.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/widgets/editorial_kit.dart';
import 'widgets/editorial_time_picker.dart';

/// Formulario de alarma en el sistema editorial.
///
/// La lógica de guardado es la misma que la de `alarm_form.dart`; lo que cambia
/// es el orden y el peso de las piezas.
///
/// La versión anterior separaba cada sección con una línea a todo el ancho y
/// las titulaba todas igual, así que la hora —lo que de verdad estás
/// eligiendo— tenía el mismo rango que el nombre opcional. Aquí la hora es una
/// **lámina propia** que ocupa el primer tercio de la pantalla, con la cuenta
/// atrás debajo como confirmación de lo que acabas de armar; el resto son
/// bloques de formulario sobre el lienzo, sin filetes que los partan.
///
/// El objeto a fotografiar sigue yendo antes que el nombre, y por la misma
/// razón de antes: es el único campo obligatorio y el que hace que la alarma
/// funcione como se supone.
class AlarmFormEditorial extends ConsumerStatefulWidget {
  const AlarmFormEditorial({super.key, this.alarm});

  final AlarmModel? alarm;

  @override
  ConsumerState<AlarmFormEditorial> createState() => _AlarmFormEditorialState();
}

class _AlarmFormEditorialState extends ConsumerState<AlarmFormEditorial> {
  late TimeOfDay _time;
  late Set<int> _days;
  late TextEditingController _label;
  late TextEditingController _object;
  bool _saving = false;

  static const _objectSuggestions = [
    'Taza de café',
    'Lavamanos del baño',
    'Cafetera',
    'Medicamento',
  ];

  static const _labelSuggestions = ['Despertar', 'Ir al gym', 'Estudiar'];

  static const _dayLetters = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
  static const _weekdays = {1, 2, 3, 4, 5};
  static const _weekend = {6, 7};
  static const _everyDay = {1, 2, 3, 4, 5, 6, 7};

  static final Color _destructive =
      EditorialTheme.accentAt(const Color(0xFFE5484D), 0.52);

  @override
  void initState() {
    super.initState();
    final a = widget.alarm;
    _time = a != null
        ? TimeOfDay(hour: a.hour, minute: a.minute)
        : const TimeOfDay(hour: 7, minute: 0);
    _days = a != null ? Set.of(a.daysOfWeek) : Set.of(_everyDay);
    _label = TextEditingController(text: a?.label ?? '');
    _object = TextEditingController(text: a?.targetObject ?? 'Taza de café');
  }

  @override
  void dispose() {
    _label.dispose();
    _object.dispose();
    super.dispose();
  }

  /// Cuánto falta con la hora y los días elegidos ahora mismo. Se calcula
  /// sobre una alarma de mentira porque `untilLabel` vive en el modelo y es
  /// exactamente la cuenta que hará la de verdad al guardarse.
  String get _untilPreview => AlarmModel(
        id: '',
        userId: '',
        enabled: true,
        hour: _time.hour,
        minute: _time.minute,
        targetObject: '',
        label: '',
        daysOfWeek: _days.toList(),
        createdAt: DateTime.now(),
      ).untilLabel ??
      'Elige al menos un día';

  bool _isPreset(Set<int> preset) =>
      _days.length == preset.length && _days.containsAll(preset);

  Future<void> _save() async {
    if (_object.text.trim().isEmpty) {
      showEditorialSnack(context, 'Escribe qué vas a fotografiar', tone: _destructive);
      return;
    }
    if (_days.isEmpty) {
      showEditorialSnack(context, 'Elige al menos un día', tone: _destructive);
      return;
    }

    setState(() => _saving = true);
    try {
      final notifier = ref.read(alarmsProvider.notifier);
      final days = _days.toList()..sort();
      final label = _label.text.trim().isEmpty ? 'Alarma' : _label.text.trim();
      final object = _object.text.trim();

      if (widget.alarm == null) {
        await notifier.addAlarm(AlarmModel(
          id: '',
          userId: '',
          enabled: true,
          hour: _time.hour,
          minute: _time.minute,
          targetObject: object,
          label: label,
          daysOfWeek: days,
          createdAt: DateTime.now(),
        ));
      } else {
        await notifier.updateAlarm(widget.alarm!.copyWith(
          hour: _time.hour,
          minute: _time.minute,
          targetObject: object,
          label: label,
          daysOfWeek: days,
        ));
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        showEditorialSnack(context, 'Error al guardar: $e', tone: _destructive);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    final ok = await confirmEditorial(
      context,
      title: 'ELIMINAR ALARMA',
      body: 'Se borra "${widget.alarm!.label}". No se puede deshacer.',
    );
    if (!ok) return;

    try {
      await ref.read(alarmsProvider.notifier).deleteAlarm(widget.alarm!.id);
      if (mounted) navigator.pop();
    } catch (e) {
      if (mounted) {
        showEditorialSnack(context, 'Error al eliminar: $e', tone: _destructive);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.alarm != null;

    return Scaffold(
      backgroundColor: EditorialTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _chrome(editing),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  EditorialTheme.margin,
                  4,
                  EditorialTheme.margin,
                  24,
                ),
                children: [
                  _timePanel(),
                  const SizedBox(height: 26),
                  _objectSection(),
                  const SizedBox(height: 26),
                  _daysSection(),
                  const SizedBox(height: 26),
                  _labelSection(),
                ],
              ),
            ),
            _footer(editing),
          ],
        ),
      ),
    );
  }

  Widget _chrome(bool editing) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(EditorialTheme.margin, 6, 14, 14),
      child: Row(
        children: [
          EditorialPressable(
            onTap: () => Navigator.of(context).pop(),
            scale: 0.88,
            child: Padding(
              padding: const EdgeInsets.only(right: 12, top: 6, bottom: 6),
              child: Icon(Icons.close, size: 21, color: EditorialTheme.paperAlpha(0.7)),
            ),
          ),
          Expanded(
            child: Text(
              editing ? 'EDITAR ALARMA' : 'NUEVA ALARMA',
              style: EditorialTheme.caps(
                27,
                color: EditorialTheme.paper,
                letterSpacing: -0.8,
                height: 1.0,
              ),
            ),
          ),
          if (editing)
            EditorialCircleButton(
              icon: Icons.delete_outline,
              tooltip: 'Eliminar alarma',
              size: 38,
              onTap: _delete,
            ),
        ],
      ),
    );
  }

  /// La hora, en su propia lámina. Es el foco de la pantalla y lo único que
  /// lleva superficie propia: todo lo demás se apoya en el lienzo.
  Widget _timePanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        children: [
          EditorialTimePicker(
            initialTime: _time,
            onChanged: (t) => setState(() => _time = t),
          ),
          const SizedBox(height: 12),
          Text(
            _untilPreview.toUpperCase(),
            textAlign: TextAlign.center,
            style: EditorialTheme.label(
              11,
              color: _days.isEmpty ? _destructive : EditorialTheme.grayText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _objectSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          'Objeto a fotografiar',
          'Para apagar la alarma tendrás que enseñárselo a la cámara. '
              'La IA comprueba que sea el correcto.',
        ),
        const SizedBox(height: 12),
        EditorialField(
          controller: _object,
          hint: 'Taza de café',
          onChanged: (_) => setState(() {}),
          prefix: Icon(Icons.camera_alt_outlined,
              size: 18, color: EditorialTheme.grayText),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final suggestion in _objectSuggestions)
              EditorialChoice(
                label: suggestion,
                compact: true,
                selected: _object.text.trim() == suggestion,
                onTap: () => setState(() => _object.text = suggestion),
              ),
          ],
        ),
      ],
    );
  }

  Widget _daysSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Repetir', null),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            EditorialChoice(
              label: 'Todos los días',
              compact: true,
              selected: _isPreset(_everyDay),
              onTap: () => setState(() => _days = Set.of(_everyDay)),
            ),
            EditorialChoice(
              label: 'Lun – Vie',
              compact: true,
              selected: _isPreset(_weekdays),
              onTap: () => setState(() => _days = Set.of(_weekdays)),
            ),
            EditorialChoice(
              label: 'Fin de semana',
              compact: true,
              selected: _isPreset(_weekend),
              onTap: () => setState(() => _days = Set.of(_weekend)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Las mismas fichas cuadradas que el formulario de hábito: siete
        // columnas iguales, la forma con la que toda la app dice "semana".
        Row(
          children: [
            for (var i = 0; i < 7; i++) ...[
              if (i > 0) const SizedBox(width: EditorialTheme.dayGap),
              Expanded(
                child: EditorialPressable(
                  onTap: () => setState(() {
                    final day = i + 1;
                    if (!_days.remove(day)) _days.add(day);
                  }),
                  scale: 0.9,
                  child: AnimatedContainer(
                    duration: EditorialTheme.motion,
                    curve: EditorialTheme.curve,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _days.contains(i + 1)
                          ? EditorialTheme.paper
                          : EditorialTheme.surfaceHigh,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      _dayLetters[i],
                      style: EditorialTheme.text(
                        14,
                        weight: FontWeight.w600,
                        color: _days.contains(i + 1)
                            ? EditorialTheme.ink
                            : EditorialTheme.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _labelSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Nombre', 'Opcional. Si lo dejas vacío se llama "Alarma".'),
        const SizedBox(height: 12),
        EditorialField(
          controller: _label,
          hint: 'Despertar mañana',
          onChanged: (_) => setState(() {}),
          prefix: Icon(Icons.label_outline, size: 18, color: EditorialTheme.grayText),
          suffix: _label.text.isEmpty
              ? null
              : EditorialPressable(
                  onTap: () => setState(_label.clear),
                  scale: 0.85,
                  child: Icon(Icons.close, size: 17, color: EditorialTheme.grayText),
                ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final suggestion in _labelSuggestions)
              EditorialChoice(
                label: suggestion,
                compact: true,
                selected: _label.text.trim() == suggestion,
                onTap: () => setState(() => _label.text = suggestion),
              ),
          ],
        ),
      ],
    );
  }

  /// Título de sección sobre el LIENZO, no sobre papel: por eso va en tinta
  /// clara y no en versalitas grises como [EditorialSectionLabel], que está
  /// calibrada para vivir dentro de una lámina.
  Widget _sectionTitle(String title, String? subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: EditorialTheme.label(11, color: EditorialTheme.muted),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: EditorialTheme.text(
              13.5,
              color: EditorialTheme.paperAlpha(0.55),
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _footer(bool editing) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        EditorialTheme.margin,
        12,
        EditorialTheme.margin,
        MediaQuery.viewPaddingOf(context).bottom + 12,
      ),
      child: EditorialPressable(
        onTap: _saving ? null : _save,
        scale: 0.97,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // Sobre el lienzo, el botón principal es papel: es la inversión
            // máxima disponible y por eso es lo que más pesa de la pantalla.
            color: _saving ? EditorialTheme.paperAlpha(0.4) : EditorialTheme.paper,
            borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
          ),
          child: _saving
              ? const SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: EditorialTheme.ink,
                  ),
                )
              : Text(
                  editing ? 'Guardar cambios' : 'Crear alarma',
                  style: EditorialTheme.text(
                    15.5,
                    weight: FontWeight.w600,
                    color: EditorialTheme.ink,
                  ),
                ),
        ),
      ),
    );
  }
}
