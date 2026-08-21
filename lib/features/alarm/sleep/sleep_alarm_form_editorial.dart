import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/alarm_model.dart';
import '../../../core/models/sleep_model.dart';
import '../../../core/providers/alarms_provider.dart';
import '../../../core/providers/sleep_provider.dart';
import '../../../core/theme/editorial_theme.dart';
import '../../../core/widgets/editorial_kit.dart';
import '../widgets/editorial_time_picker.dart';

/// Horario de sueño en el sistema editorial: acostarse y despertar como una
/// sola pieza, más los ajustes que no caben en una alarma normal.
///
/// La estructura de la versión anterior era correcta y se conserva —los dos
/// extremos arriba, la rueda debajo editando el que esté elegido— porque es la
/// que refleja cómo la gente piensa el horario ("de 11 a 7", no dos horas
/// sueltas). Lo que cambia:
///
///  - **Los extremos se eligen por inversión, no por borde de color.** Antes el
///    activo se marcaba con un filete naranja y un relleno translúcido, que a
///    contraluz apenas se distinguía del inactivo. Aquí el elegido es papel
///    pleno con tinta encima; el otro es una superficie apagada. No hay forma
///    de confundirlos.
///  - **Las siete secciones de ajustes dejan de estar separadas por líneas a
///    todo el ancho.** Un divisor cada dos elementos trocea la pantalla en
///    porciones iguales y ninguna manda; el aire y la etiqueta bastan.
class SleepAlarmFormEditorial extends ConsumerStatefulWidget {
  const SleepAlarmFormEditorial({super.key, this.alarm});

  /// Alarma de sueño existente, o `null` para crear una nueva.
  final AlarmModel? alarm;

  static Future<void> open(BuildContext context, {AlarmModel? alarm}) {
    return Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SleepAlarmFormEditorial(alarm: alarm)),
    );
  }

  @override
  ConsumerState<SleepAlarmFormEditorial> createState() =>
      _SleepAlarmFormEditorialState();
}

class _SleepAlarmFormEditorialState extends ConsumerState<SleepAlarmFormEditorial> {
  late TimeOfDay _bedtime;
  late TimeOfDay _wake;
  late Set<int> _days;
  late TextEditingController _object;
  late int _goalMinutes;
  late int _windDown;
  late bool _nag;
  late bool _wakeCheck;
  late int _wakeCheckInterval;
  late int _wakeCheckWindow;
  bool _saving = false;

  /// Qué extremo del rango está editando la rueda de abajo.
  bool _editingBedtime = true;

  static const _dayLetters = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
  static const _weekdays = {1, 2, 3, 4, 5};
  static const _weekend = {6, 7};
  static const _everyDay = {1, 2, 3, 4, 5, 6, 7};

  static const _objectSuggestions = [
    'Taza de café',
    'Lavamanos del baño',
    'Cafetera',
    'Cepillo de dientes',
  ];
  static const _goalOptions = [360, 390, 420, 450, 480, 510, 540];
  static const _windDownOptions = [0, 15, 30, 45, 60];
  static const _intervalOptions = [5, 10, 15, 20];
  static const _windowOptions = [20, 40, 60, 90];

  /// Por debajo de esto la ventana en la cama es tan corta que casi seguro es
  /// un error al poner las horas, no una decisión.
  static const int _shortWindowMinutes = 300;

  static final Color _destructive =
      EditorialTheme.accentAt(const Color(0xFFE5484D), 0.52);

  @override
  void initState() {
    super.initState();
    final alarm = widget.alarm;
    final schedule = ref.read(sleepProvider).schedule;

    _bedtime = alarm != null && alarm.isSleepAlarm
        ? TimeOfDay(hour: alarm.bedtimeHour!, minute: alarm.bedtimeMinute!)
        : TimeOfDay(hour: schedule.bedtimeHour, minute: schedule.bedtimeMinute);
    _wake = alarm != null
        ? TimeOfDay(hour: alarm.hour, minute: alarm.minute)
        : const TimeOfDay(hour: 7, minute: 0);
    _days = alarm != null ? Set.of(alarm.daysOfWeek) : Set.of(_everyDay);
    _object = TextEditingController(text: alarm?.targetObject ?? 'Taza de café');
    _goalMinutes = schedule.goalMinutes;
    _windDown = schedule.windDownMinutes;
    _nag = schedule.nagEnabled;
    _wakeCheck = schedule.wakeCheckEnabled;
    _wakeCheckInterval = schedule.wakeCheckIntervalMinutes;
    _wakeCheckWindow = schedule.wakeCheckWindowMinutes;
  }

  @override
  void dispose() {
    _object.dispose();
    super.dispose();
  }

  /// Minutos entre acostarse y despertar, cruzando medianoche.
  int get _windowMinutes {
    final start = _bedtime.hour * 60 + _bedtime.minute;
    final end = _wake.hour * 60 + _wake.minute;
    final diff = end - start;
    return diff <= 0 ? diff + 1440 : diff;
  }

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
      final alarms = ref.read(alarmsProvider.notifier);
      final days = _days.toList()..sort();
      final object = _object.text.trim();

      AlarmModel saved;
      if (widget.alarm == null) {
        saved = await alarms.addAlarm(AlarmModel(
          id: '',
          userId: '',
          enabled: true,
          hour: _wake.hour,
          minute: _wake.minute,
          targetObject: object,
          label: 'Horario de sueño',
          daysOfWeek: days,
          createdAt: DateTime.now(),
          bedtimeHour: _bedtime.hour,
          bedtimeMinute: _bedtime.minute,
        ));
      } else {
        saved = widget.alarm!.copyWith(
          hour: _wake.hour,
          minute: _wake.minute,
          targetObject: object,
          daysOfWeek: days,
          bedtimeHour: _bedtime.hour,
          bedtimeMinute: _bedtime.minute,
        );
        await alarms.updateAlarm(saved);
      }

      final sleep = ref.read(sleepProvider.notifier);
      // Primero los ajustes que sólo viven en el horario y luego el sync con la
      // alarma: así la reprogramación de avisos ya usa los valores nuevos.
      await sleep.saveSchedule(ref.read(sleepProvider).schedule.copyWith(
            goalMinutes: _goalMinutes,
            windDownMinutes: _windDown,
            nagEnabled: _nag,
            wakeCheckEnabled: _wakeCheck,
            wakeCheckIntervalMinutes: _wakeCheckInterval,
            wakeCheckWindowMinutes: _wakeCheckWindow,
          ));
      await sleep.syncFromAlarm(saved);

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
    final alarm = widget.alarm;
    if (alarm == null) return;

    final navigator = Navigator.of(context);
    final ok = await confirmEditorial(
      context,
      title: 'ELIMINAR HORARIO',
      body: 'Se borra la alarma y dejan de llegar los avisos de dormir. '
          'El historial de noches se conserva.',
    );
    if (!ok) return;

    await ref.read(alarmsProvider.notifier).deleteAlarm(alarm.id);
    await ref.read(sleepProvider.notifier).syncFromAlarm(null);
    if (mounted) navigator.pop();
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
                  _rangePanel(),
                  const SizedBox(height: 26),
                  _objectSection(),
                  const SizedBox(height: 26),
                  _daysSection(),
                  const SizedBox(height: 26),
                  _chipSection(
                    'Meta de sueño',
                    'Contra esto se calculan la deuda y la racha.',
                    [
                      for (final m in _goalOptions)
                        (label: formatSleepMinutes(m), value: m),
                    ],
                    _goalMinutes,
                    (v) => setState(() => _goalMinutes = v),
                  ),
                  const SizedBox(height: 26),
                  _chipSection(
                    'Aviso previo',
                    'Cuánto antes te avisa para bajar luces y soltar pantallas.',
                    [
                      for (final m in _windDownOptions)
                        (label: m == 0 ? 'Sin aviso' : '$m min antes', value: m),
                    ],
                    _windDown,
                    (v) => setState(() => _windDown = v),
                  ),
                  const SizedBox(height: 26),
                  _toggle(
                    'Insistir si lo ignoro',
                    'Repite el aviso a los 15, 30 y 45 min hasta que confirmes.',
                    _nag,
                    (v) => setState(() => _nag = v),
                  ),
                  const SizedBox(height: 20),
                  _toggle(
                    'Comprobar que sigo despierto',
                    'Un rato después de apagar la alarma vuelve a sonar hasta '
                        'que confirmes de un toque.',
                    _wakeCheck,
                    (v) => setState(() => _wakeCheck = v),
                  ),
                  if (_wakeCheck) ...[
                    const SizedBox(height: 22),
                    _chipSection(
                      'Cada cuánto comprueba',
                      null,
                      [
                        for (final m in _intervalOptions)
                          (label: '$m min', value: m),
                      ],
                      _wakeCheckInterval,
                      (v) => setState(() => _wakeCheckInterval = v),
                    ),
                    const SizedBox(height: 22),
                    _chipSection(
                      'Durante cuánto rato',
                      'Pasado ese tiempo desde que apagas la alarma, deja de vigilar.',
                      [
                        for (final m in _windowOptions)
                          (label: '$m min', value: m),
                      ],
                      _wakeCheckWindow,
                      (v) => setState(() => _wakeCheckWindow = v),
                    ),
                  ],
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
              editing ? 'EDITAR HORARIO' : 'NUEVO HORARIO',
              style: EditorialTheme.caps(
                26,
                color: EditorialTheme.paper,
                letterSpacing: -0.8,
                height: 1.0,
              ),
            ),
          ),
          if (editing)
            EditorialCircleButton(
              icon: Icons.delete_outline,
              tooltip: 'Eliminar horario',
              size: 38,
              onTap: _delete,
            ),
        ],
      ),
    );
  }

  Widget _rangePanel() {
    final window = _windowMinutes;
    final short = window < _shortWindowMinutes;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _endpoint(
                label: 'Me acuesto',
                icon: Icons.bedtime_outlined,
                time: _bedtime,
                active: _editingBedtime,
                onTap: () => setState(() => _editingBedtime = true),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 15, color: EditorialTheme.grayText),
              ),
              _endpoint(
                label: 'Suena',
                icon: Icons.wb_sunny_outlined,
                time: _wake,
                active: !_editingBedtime,
                onTap: () => setState(() => _editingBedtime = false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          EditorialTimePicker(
            // La clave fuerza reconstruir la rueda al cambiar de extremo: sin
            // ella seguiría mostrando la hora del otro.
            key: ValueKey(_editingBedtime),
            initialTime: _editingBedtime ? _bedtime : _wake,
            onChanged: (t) => setState(() {
              if (_editingBedtime) {
                _bedtime = t;
              } else {
                _wake = t;
              }
            }),
          ),
          const SizedBox(height: 12),
          Text(
            '${formatSleepMinutes(window)} EN LA CAMA'
            '${short ? '  ·  MUY POCO' : ''}',
            textAlign: TextAlign.center,
            style: EditorialTheme.label(
              11,
              color: short ? _destructive : EditorialTheme.grayText,
            ),
          ),
        ],
      ),
    );
  }

  /// Un extremo del rango. Vive DENTRO de la lámina blanca, así que su paleta
  /// está invertida respecto del resto de la pantalla: aquí el resalte es la
  /// tinta y el reposo es el gris.
  Widget _endpoint({
    required String label,
    required IconData icon,
    required TimeOfDay time,
    required bool active,
    required VoidCallback onTap,
  }) {
    final h12 = time.hour % 12 == 0 ? 12 : time.hour % 12;

    return Expanded(
      child: EditorialPressable(
        onTap: onTap,
        scale: 0.95,
        child: AnimatedContainer(
          duration: EditorialTheme.motion,
          curve: EditorialTheme.curve,
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
          decoration: BoxDecoration(
            color: active ? EditorialTheme.ink : EditorialTheme.gray,
            borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon,
                      size: 12,
                      color: active ? EditorialTheme.paperAlpha(0.7) : EditorialTheme.grayText),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EditorialTheme.label(
                        9.5,
                        color: active
                            ? EditorialTheme.paperAlpha(0.7)
                            : EditorialTheme.grayText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$h12:${time.minute.toString().padLeft(2, '0')}',
                    style: EditorialTheme.caps(
                      26,
                      color: active ? EditorialTheme.paper : EditorialTheme.ink,
                      letterSpacing: -1,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    time.period == DayPeriod.am ? 'AM' : 'PM',
                    style: EditorialTheme.text(
                      11.5,
                      weight: FontWeight.w600,
                      color: active
                          ? EditorialTheme.paperAlpha(0.65)
                          : EditorialTheme.grayText,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _objectSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          'Objeto a fotografiar',
          'Para apagar la alarma de la mañana tendrás que enseñárselo a la cámara.',
        ),
        const SizedBox(height: 12),
        EditorialField(
          controller: _object,
          hint: 'Taza de café',
          onChanged: (_) => setState(() {}),
          prefix: Icon(Icons.camera_alt_outlined, size: 18, color: EditorialTheme.grayText),
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
        _sectionTitle('Repetir', 'Los días marcados son los de despertar.'),
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

  /// Sección de opciones excluyentes. Genérica porque este formulario tiene
  /// cuatro idénticas y escribirlas a mano garantizaba que se desincronizaran.
  Widget _chipSection(
    String title,
    String? subtitle,
    List<({String label, int value})> options,
    int current,
    ValueChanged<int> onPick,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(title, subtitle),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              EditorialChoice(
                label: option.label,
                compact: true,
                selected: current == option.value,
                onTap: () => onPick(option.value),
              ),
          ],
        ),
      ],
    );
  }

  /// Interruptor sobre el lienzo. No usa [EditorialRow] porque esa pieza está
  /// pensada para vivir dentro de una lámina de papel, y aquí no hay ninguna.
  Widget _toggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _sectionTitle(title, subtitle)),
        const SizedBox(width: 12),
        Switch.adaptive(
          value: value,
          activeThumbColor: EditorialTheme.ink,
          activeTrackColor: EditorialTheme.paper,
          inactiveThumbColor: EditorialTheme.muted,
          inactiveTrackColor: EditorialTheme.surfaceHigh,
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
          onChanged: onChanged,
        ),
      ],
    );
  }

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
                  editing ? 'Guardar cambios' : 'Crear horario',
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
