import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/task_model.dart';
import '../../../core/providers/appearance_provider.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/theme/editorial_theme.dart';
import '../timeline_scale.dart';
import 'timeline_task_card.dart';

/// Franja del día donde la mayoría rinde mejor en trabajo cognitivo. Se pinta
/// como una banda tenue para empujar (sin obligar) a poner ahí lo importante,
/// en vez de dejarlo para cuando ya no queda voluntad.
const _peakStartHour = 8;
const _peakEndHour = 12;

const _gutterWidth = 52.0;
const _laneGap = 4.0;

/// Alto que se reserva al panel del borrador mientras se escribe el título.
/// Un bloque de 15 min mide ~18px: escribir dentro sería imposible, así que
/// mientras se edita el panel crece y luego el bloque queda con su alto real.
const _draftEditorHeight = 92.0;

/// Duraciones de un toque. Cubren el 90% de lo que uno planea; el resto se
/// ajusta estirando el bloque o desde el formulario.
const _durationPresets = <int>[15, 30, 45, 60, 90, 120];

enum _DragMode { move, resize }

class _BlockDrag {
  final Task task;
  final _DragMode mode;
  final int originalStart;
  final int originalEnd;
  int start;
  int end;
  double currentOffset = 0.0;

  _BlockDrag({
    required this.task,
    required this.mode,
    required this.originalStart,
    required this.originalEnd,
  })  : start = originalStart,
        end = originalEnd;
}

/// Timeline de un día con creación directa.
///
/// Hay dos gestos y el barato es el que se usa siempre: **un toque** sobre una
/// franja vacía crea un bloque de 30 min a esa hora y abre el título en línea.
/// Mantener y arrastrar sigue existiendo para quien quiera marcar la duración
/// exacta de una vez, pero ya no es obligatorio: obligar a mantener el dedo
/// para la acción más frecuente de la pantalla es exactamente el tipo de peaje
/// que hace que se deje de planear.
///
/// La duración también se puede cambiar con un toque desde el propio panel del
/// borrador, así que nunca hace falta arrastrar nada.
/// La piel no se duplica: se parametriza.
///
/// El timeline es geometría —escala de minutos a píxeles, colisiones entre
/// bloques, arrastre con imán al cuarto de hora— y esa geometría es idéntica en
/// los dos lenguajes. Lo único que cambia son colores y tipografía. Duplicar el
/// archivo habría dejado dos copias de la parte delicada para no repetir la
/// fácil, así que los tokens viven en [_TimelineSkin] y los métodos de pintura
/// son uno solo.
class DayTimeline extends ConsumerStatefulWidget {
  final DateTime day;
  final List<Task> tasks;

  /// Permite que los bloques de hábito lean su estado del propio hábito en vez
  /// de `task.completed`, para no tener dos verdades que sincronizar.
  final bool Function(Task task)? isCompleted;

  final Future<void> Function(String title, DateTime start, DateTime end) onCreate;
  final void Function(Task task, DateTime start, DateTime end) onReschedule;
  final void Function(Task task) onTapBlock;
  final void Function(Task task) onToggleBlock;

  const DayTimeline({
    super.key,
    required this.day,
    required this.tasks,
    required this.onCreate,
    required this.onReschedule,
    required this.onTapBlock,
    required this.onToggleBlock,
    this.isCompleted,
  });

  @override
  ConsumerState<DayTimeline> createState() => _DayTimelineState();
}

class _DayTimelineState extends ConsumerState<DayTimeline> {
  /// Se resuelve una vez por build y lo leen todos los métodos de pintura.
  late _TimelineSkin _skin;

  final _scrollController = ScrollController();
  final _draftController = TextEditingController();
  final _draftFocus = FocusNode();

  bool _nightExpanded = false;

  /// Rango en construcción, en minutos del día. Vive durante el arrastre y
  /// sigue vivo mientras se escribe el título.
  int? _draftStart;
  int? _draftEnd;
  bool _draftEditing = false;
  bool _submittingDraft = false;

  /// Se marca cuando el gesto de crear vino de un arrastre. Si el usuario
  /// eligió la duración con el dedo, no se le sobreescribe con un preset.
  bool _draftFromDrag = false;

  _BlockDrag? _blockDrag;

  bool _didInitialScroll = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _draftController.dispose();
    _draftFocus.dispose();
    super.dispose();
  }

  bool _isCompleted(Task t) => widget.isCompleted?.call(t) ?? t.completed;

  bool get _isToday {
    final now = DateTime.now();
    return DateTime(widget.day.year, widget.day.month, widget.day.day) ==
        DateTime(now.year, now.month, now.day);
  }

  TimelineScale get _scale {
    // No se pliega la madrugada si hay algo planeado ahí: comprimir un bloque
    // real a unos pocos píxeles sería peor que el scroll que ahorramos.
    final hasEarly = widget.tasks.any((t) => minutesOfDay(t.startAt) < _nightBoundaryHour * 60);
    final collapse = (_nightExpanded || hasEarly) ? 0 : _nightBoundaryHour;
    return TimelineScale(collapseUntilHour: collapse);
  }

  static const _nightBoundaryHour = 6;

  DateTime _dateAt(int minutes) {
    final d = widget.day;
    // Un minuto 1440 es la medianoche del día siguiente, no la del mismo día.
    return DateTime(d.year, d.month, d.day).add(Duration(minutes: minutes));
  }

  void _scrollToRelevantHour(TimelineScale scale) {
    if (_didInitialScroll || !_scrollController.hasClients) return;
    _didInitialScroll = true;

    // Hoy: la hora actual. Otro día: el primer bloque, o el inicio de la
    // jornada si está vacío. Abrir un día siempre en 00:00 obliga a scrollear
    // antes de poder hacer nada.
    final int anchorMinutes;
    if (_isToday) {
      anchorMinutes = minutesOfDay(DateTime.now());
    } else if (widget.tasks.isNotEmpty) {
      anchorMinutes = widget.tasks.map((t) => minutesOfDay(t.startAt)).reduce((a, b) => a < b ? a : b);
    } else {
      anchorMinutes = _peakStartHour * 60;
    }

    final target = (scale.yForMinutes(anchorMinutes) - 120).clamp(0.0, scale.totalHeight);
    _scrollController.jumpTo(target.clamp(0.0, _scrollController.position.maxScrollExtent));
  }

  // ---------------------------------------------------------------- crear

  /// Toque simple sobre hueco: crea el bloque de golpe. Es el camino corto y
  /// el que se usa el 90% de las veces.
  void _onCanvasTap(TapUpDetails details, TimelineScale scale) {
    // Con un borrador abierto, el toque fuera vale como "ya está": si hay
    // título se guarda, y si no, se descarta. Pedir confirmación explícita
    // para tirar un borrador vacío sería ruido.
    if (_draftEditing) {
      if (_draftController.text.trim().isEmpty) {
        _cancelDraft();
      } else {
        _submitDraft();
      }
      return;
    }
    HapticFeedback.selectionClick();
    final m = TimelineScale.snap(scale.minutesForY(details.localPosition.dy));
    _openDraft(m, (m + 30).clamp(0, TimelineScale.minutesPerDay), fromDrag: false);
  }

  void _openDraft(int start, int end, {required bool fromDrag}) {
    setState(() {
      _draftStart = start;
      _draftEnd = end;
      _draftEditing = true;
      _draftFromDrag = fromDrag;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _draftFocus.requestFocus();
      _ensureDraftVisible();
    });
  }

  /// Sube o baja el scroll lo justo para que el panel del borrador no quede
  /// detrás del teclado ni fuera de pantalla.
  void _ensureDraftVisible() {
    if (!_scrollController.hasClients || _draftStart == null) return;
    final scale = _scale;
    final top = scale.yForMinutes(_draftStart!);
    final offset = _scrollController.offset;
    final viewport = _scrollController.position.viewportDimension;
    // Se deja margen arriba para ver de qué hora viene y abajo para el panel.
    const marginTop = 80.0;
    final marginBottom = _draftEditorHeight + 40;
    double? target;
    if (top - marginTop < offset) {
      target = top - marginTop;
    } else if (top + marginBottom > offset + viewport) {
      target = top + marginBottom - viewport;
    }
    if (target == null) return;
    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _onCreateStart(LongPressStartDetails details, TimelineScale scale) {
    if (_draftEditing) return;
    HapticFeedback.selectionClick();
    final m = TimelineScale.snap(scale.minutesForY(details.localPosition.dy));
    setState(() {
      _draftStart = m;
      _draftEnd = (m + 30).clamp(0, TimelineScale.minutesPerDay);
      _draftFromDrag = true;
    });
  }

  void _onCreateUpdate(LongPressMoveUpdateDetails details, TimelineScale scale) {
    if (_draftStart == null || _draftEditing) return;
    final anchor = _draftStart!;
    final m = TimelineScale.snap(scale.minutesForY(details.localPosition.dy));
    // Arrastrar hacia arriba también vale: el ancla es donde empezaste, no
    // necesariamente el inicio del bloque.
    final start = m < anchor ? m : anchor;
    var end = m < anchor ? anchor : m;
    if (end - start < TimelineScale.snapMinutes) end = start + TimelineScale.snapMinutes;
    if (start != _draftStart || end != _draftEnd) {
      HapticFeedback.selectionClick();
      setState(() {
        _draftStart = start;
        _draftEnd = end;
      });
    }
  }

  void _onCreateEnd() {
    if (_draftStart == null || _draftEditing) return;
    _openDraft(_draftStart!, _draftEnd!, fromDrag: true);
  }

  void _setDraftDuration(int minutes) {
    final start = _draftStart;
    if (start == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _draftEnd = (start + minutes).clamp(start + TimelineScale.snapMinutes, TimelineScale.minutesPerDay);
      _draftFromDrag = false;
    });
  }

  void _cancelDraft() {
    _draftController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _draftStart = null;
      _draftEnd = null;
      _draftEditing = false;
      _draftFromDrag = false;
    });
  }

  Future<void> _submitDraft() async {
    if (_submittingDraft) return;
    final title = _draftController.text.trim();
    if (title.isEmpty || _draftStart == null || _draftEnd == null) {
      _cancelDraft();
      return;
    }
    _submittingDraft = true;
    final start = _dateAt(_draftStart!);
    final end = _dateAt(_draftEnd!);
    HapticFeedback.lightImpact();
    _cancelDraft();
    try {
      await widget.onCreate(title, start, end);
    } finally {
      _submittingDraft = false;
    }
  }

  // ------------------------------------------------------- mover / estirar

  void _onBlockDragStart(Task task, _DragMode mode) {
    HapticFeedback.mediumImpact();
    setState(() {
      _blockDrag = _BlockDrag(
        task: task,
        mode: mode,
        originalStart: minutesOfDay(task.startAt),
        originalEnd: endMinutesOf(task),
      );
    });
  }

  void _onBlockDragUpdate(double deltaY, TimelineScale scale) {
    final drag = _blockDrag;
    if (drag == null) return;

    setState(() {
      drag.currentOffset = deltaY;
    });

    // El delta se convierte a minutos pasando por la escala, no con una regla
    // de tres: dentro de la banda plegada un píxel vale muchos más minutos.
    //
    // Ojo con la semántica del delta: al mover, `onLongPressMoveUpdate` da el
    // desplazamiento ACUMULADO desde el origen del gesto, así que la base es
    // la posición original. Al estirar, `onVerticalDragUpdate` da el
    // incremental, y la base es la posición actual.
    final duration = drag.originalEnd - drag.originalStart;

    if (drag.mode == _DragMode.move) {
      final currentY = scale.yForMinutes(drag.originalStart) + deltaY;
      var newStart = TimelineScale.snap(scale.minutesForY(currentY));
      newStart = newStart.clamp(0, TimelineScale.minutesPerDay - duration);
      if (newStart != drag.start) {
        HapticFeedback.selectionClick();
        setState(() {
          drag.start = newStart;
          drag.end = newStart + duration;
        });
      }
    } else {
      final currentY = scale.yForMinutes(drag.end) + deltaY;
      var newEnd = TimelineScale.snap(scale.minutesForY(currentY));
      newEnd = newEnd.clamp(drag.start + TimelineScale.snapMinutes, TimelineScale.minutesPerDay);
      if (newEnd != drag.end) {
        HapticFeedback.selectionClick();
        setState(() => drag.end = newEnd);
      }
    }
  }

  void _onBlockDragEnd() {
    final drag = _blockDrag;
    setState(() => _blockDrag = null);
    if (drag == null) return;
    if (drag.start == drag.originalStart && drag.end == drag.originalEnd) return;
    HapticFeedback.lightImpact();
    widget.onReschedule(drag.task, _dateAt(drag.start), _dateAt(drag.end));
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    _skin = ref.watch(designLanguageProvider).isEditorial
        ? _TimelineSkin.editorial()
        : _TimelineSkin.neu();

    final scale = _scale;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToRelevantHour(scale));

    return LayoutBuilder(
      builder: (context, constraints) {
        final laneAreaWidth = constraints.maxWidth - _gutterWidth - 12;
        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.only(bottom: 160),
          child: SizedBox(
            height: scale.totalHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Capa de gestos al fondo: los bloques, al estar encima, se
                // quedan con sus propios toques antes de llegar aquí.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => _onCanvasTap(d, scale),
                    onLongPressStart: (d) => _onCreateStart(d, scale),
                    onLongPressMoveUpdate: (d) => _onCreateUpdate(d, scale),
                    onLongPressEnd: (_) => _onCreateEnd(),
                  ),
                ),
                ..._buildPeakBand(scale, laneAreaWidth),
                ..._buildGrid(scale),
                ..._buildBlocks(scale, laneAreaWidth),
                ..._buildNowLine(scale),
                // Con el borrador abierto, cualquier toque fuera lo cierra —
                // incluso sobre otro bloque. Sin esta capa, tocar un bloque
                // vecino abría su formulario y el borrador se perdía sin que
                // nadie hubiera pedido tirarlo.
                if (_draftEditing)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) => _onCanvasTap(d, scale),
                    ),
                  ),
                if (_draftStart != null) _buildDraft(scale, laneAreaWidth),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildPeakBand(TimelineScale scale, double laneAreaWidth) {
    final top = scale.yForMinutes(_peakStartHour * 60);
    final bottom = scale.yForMinutes(_peakEndHour * 60);
    return [
      Positioned(
        top: top,
        left: _gutterWidth - 6,
        width: laneAreaWidth + 6,
        height: bottom - top,
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              color: _skin.peakFill,
              borderRadius: BorderRadius.circular(14),
              border: Border(left: BorderSide(color: _skin.peakEdge, width: 2)),
            ),
            alignment: Alignment.topRight,
            padding: const EdgeInsets.only(top: 5, right: 9),
            child: Text('FRANJA DE FOCO', style: _skin.peakLabel),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildGrid(TimelineScale scale) {
    final widgets = <Widget>[];
    final nowHour = DateTime.now().hour;

    if (scale.isCollapsing) {
      widgets.add(Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: scale.collapsedHeight,
        child: GestureDetector(
          onTap: () => setState(() => _nightExpanded = true),
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _skin.pillFill,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.expand_more_rounded, size: 13, color: _skin.pillInk),
                    const SizedBox(width: 4),
                    Text('00:00 – 06:00', style: _skin.pillLabel),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Container(height: 1, color: _skin.hourLine(true))),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ));
    }

    final firstHour = scale.isCollapsing ? _nightBoundaryHour : 0;
    for (var hour = firstHour; hour < 24; hour++) {
      // Las horas ya pasadas se apagan: el ojo debe aterrizar en lo que queda
      // por delante, no en lo que ya no se puede cambiar.
      final isPast = _isToday && hour < nowHour;
      final isCurrent = _isToday && hour == nowHour;

      widgets.add(Positioned(
        top: scale.yForMinutes(hour * 60) - 7,
        left: 0,
        right: 12,
        child: IgnorePointer(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: _gutterWidth - 10,
                child: Text(
                  '${hour.toString().padLeft(2, '0')}:00',
                  textAlign: TextAlign.right,
                  style: _skin.hourLabel(isCurrent: isCurrent, isPast: isPast),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Container(height: 1, color: _skin.hourLine(isPast))),
            ],
          ),
        ),
      ));

      // Marca de la media hora: da resolución para leer dónde cae un bloque
      // sin llenar la pantalla de líneas.
      if (!scale.isCollapsing || hour >= _nightBoundaryHour) {
        widgets.add(Positioned(
          top: scale.yForMinutes(hour * 60 + 30),
          left: _gutterWidth,
          right: 12,
          child: IgnorePointer(
            child: Container(height: 1, color: _skin.halfHourLine(isPast)),
          ),
        ));
      }
    }

    if (scale.isCollapsing == false && _nightExpanded) {
      widgets.add(Positioned(
        top: 2,
        right: 12,
        child: GestureDetector(
          onTap: () => setState(() => _nightExpanded = false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _skin.pillFill,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.unfold_less_rounded, size: 13, color: _skin.pillInk),
                const SizedBox(width: 4),
                Text('plegar madrugada', style: _skin.pillLabel),
              ],
            ),
          ),
        ),
      ));
    }

    return widgets;
  }

  List<Widget> _buildNowLine(TimelineScale scale) {
    if (!_isToday) return const [];
    final now = DateTime.now();
    return [
      Positioned(
        top: scale.yForTime(now) - 9,
        left: 0,
        right: 12,
        child: IgnorePointer(
          child: Row(
            children: [
              // La hora exacta en la canaleta: saber "son las 14:35" sin salir
              // del timeline es lo que hace que la línea signifique algo.
              Container(
                width: _gutterWidth - 10,
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: _skin.nowMark,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(_fmt(minutesOfDay(now)), style: _skin.nowLabel),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: _skin.nowMark, shape: BoxShape.circle),
              ),
              Expanded(
                child: Container(
                  height: 1.5,
                  decoration: BoxDecoration(
                    color: _skin.nowRule,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------- draft

  Widget _buildDraft(TimelineScale scale, double laneAreaWidth) {
    final start = _draftStart!;
    final end = _draftEnd!;
    final rawTop = scale.yForMinutes(start);
    final rawHeight = scale.heightForRange(start, end);

    if (!_draftEditing) {
      // Fase de arrastre: solo la silueta con el rango, sin nada que leer.
      return Positioned(
        top: rawTop,
        left: _gutterWidth,
        width: laneAreaWidth,
        height: rawHeight,
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              color: _skin.draftGhostFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _skin.draftEdge, width: 1.5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            alignment: Alignment.topLeft,
            child: Text(
              '${_fmt(start)} – ${_fmt(end)}  ·  ${_durationLabel(end - start)}',
              style: _skin.draftRange,
            ),
          ),
        ),
      );
    }

    // Editando: el panel se ancla al inicio del bloque pero se le da alto
    // propio, y se frena para no salirse por abajo del lienzo.
    final top = rawTop.clamp(0.0, (scale.totalHeight - _draftEditorHeight).clamp(0.0, double.infinity));

    return Positioned(
      top: top,
      left: _gutterWidth,
      width: laneAreaWidth,
      height: _draftEditorHeight,
      child: Container(
        decoration: BoxDecoration(
          color: _skin.draftFill,
          borderRadius: BorderRadius.circular(14),
          border: _skin.draftBorder,
          boxShadow: _skin.draftShadow,
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('${_fmt(start)} – ${_fmt(end)}', style: _skin.draftRange),
                const Spacer(),
                _draftIconButton(Icons.close_rounded, _skin.draftDismiss, _cancelDraft),
                const SizedBox(width: 2),
                _draftIconButton(Icons.check_rounded, _skin.draftConfirm, _submitDraft),
              ],
            ),
            Expanded(
              child: Center(
                child: TextField(
                  controller: _draftController,
                  focusNode: _draftFocus,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _submitDraft(),
                  cursorColor: _skin.draftInk,
                  style: _skin.draftField,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    hintText: '¿Qué vas a hacer?',
                    hintStyle: _skin.draftHint,
                  ),
                ),
              ),
            ),
            // Duración de un toque. Es la alternativa a estirar el bloque, y
            // el motivo por el que ya no hace falta arrastrar para nada.
            SizedBox(
              height: 24,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _durationPresets.length,
                separatorBuilder: (_, _) => const SizedBox(width: 5),
                itemBuilder: (context, i) {
                  final minutes = _durationPresets[i];
                  final selected = !_draftFromDrag && (end - start) == minutes;
                  return GestureDetector(
                    onTap: () => _setDraftDuration(minutes),
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      decoration: BoxDecoration(
                        color: selected ? _skin.chipOnFill : _skin.chipOffFill,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        _durationLabel(minutes),
                        style: selected ? _skin.chipOnLabel : _skin.chipOffLabel,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _draftIconButton(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  List<Widget> _buildBlocks(TimelineScale scale, double laneAreaWidth) {
    final drag = _blockDrag;
    final laid = layoutBlocks(widget.tasks);
    final nowMinutes = _isToday ? minutesOfDay(DateTime.now()) : -1;

    return [
      for (final block in laid)
        ...() {
          final isDragging = drag?.task.id == block.task.id;
          final start = isDragging ? drag!.start : block.startMinutes;
          final end = isDragging ? drag!.end : block.endMinutes;

          final laneWidth = (laneAreaWidth - _laneGap * (block.laneCount - 1)) / block.laneCount;
          final left = _gutterWidth + block.lane * (laneWidth + _laneGap);
          final height = scale.heightForRange(start, end);
          final completed = _isCompleted(block.task);

          final widgets = <Widget>[];

          // Vista previa del bloque ajustado en la cuadrícula (dónde va a caer)
          if (isDragging && drag!.mode == _DragMode.move) {
            widgets.add(
              Positioned(
                top: scale.yForMinutes(drag.start),
                left: left,
                width: laneWidth,
                height: height,
                child: Opacity(
                  opacity: 0.35,
                  child: TimelineTaskCard(
                    task: block.task,
                    height: height,
                    completed: completed,
                    isPast: nowMinutes >= 0 && drag.end <= nowMinutes && !completed,
                    isNow: nowMinutes >= drag.start && nowMinutes < drag.end,
                    timeLabel: '${_fmt(drag.start)} – ${_fmt(drag.end)}',
                    onTap: () {},
                    onToggleComplete: () {},
                  ),
                ),
              ),
            );
          }

          // El bloque que el usuario está arrastrando físicamente (sigue el dedo con suavidad)
          final dragTop = isDragging && drag!.mode == _DragMode.move
              ? scale.yForMinutes(drag.originalStart) + drag.currentOffset
              : scale.yForMinutes(start);
          final dragHeight = isDragging && drag!.mode == _DragMode.move
              ? scale.heightForRange(drag.originalStart, drag.originalEnd)
              : height;

          widgets.add(
            Positioned(
              top: dragTop,
              left: left,
              width: laneWidth,
              height: dragHeight,
              child: _DraggableBlock(
                skin: _skin,
                key: ValueKey(block.task.id),
                task: block.task,
                height: dragHeight,
                completed: completed,
                isDragging: isDragging,
                // Un bloque ya pasado y sin marcar se muestra apagado: no es un
                // error, pero tampoco merece el mismo peso visual que lo que
                // queda por hacer.
                isPast: nowMinutes >= 0 && end <= nowMinutes && !completed,
                isNow: nowMinutes >= start && nowMinutes < end,
                timeLabel: isDragging
                    ? '${_fmt(drag!.start)} – ${_fmt(drag.end)}'
                    : '${_fmt(start)} – ${_fmt(end)}',
                onTap: () => widget.onTapBlock(block.task),
                onToggle: () => widget.onToggleBlock(block.task),
                onMoveStart: () => _onBlockDragStart(block.task, _DragMode.move),
                onResizeStart: () => _onBlockDragStart(block.task, _DragMode.resize),
                onDragUpdate: (dy) => _onBlockDragUpdate(dy, scale),
                onDragEnd: _onBlockDragEnd,
              ),
            ),
          );

          return widgets;
        }(),
    ];
  }
}

String _fmt(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

String _durationLabel(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h $m';
}

/// Envuelve la tarjeta con los gestos de mover y estirar.
///
/// Mover exige pulsación larga primero (para no arrastrar bloques sin querer
/// al scrollear); estirar usa el tirador de abajo, que es un objetivo
/// explícito y no necesita pulsación previa.
class _DraggableBlock extends StatelessWidget {
  final _TimelineSkin skin;
  final Task task;
  final double height;
  final bool completed;
  final bool isDragging;
  final bool isPast;
  final bool isNow;
  final String timeLabel;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onMoveStart;
  final VoidCallback onResizeStart;
  final void Function(double deltaY) onDragUpdate;
  final VoidCallback onDragEnd;

  const _DraggableBlock({
    super.key,
    required this.skin,
    required this.task,
    required this.height,
    required this.completed,
    required this.isDragging,
    required this.isPast,
    required this.isNow,
    required this.timeLabel,
    required this.onTap,
    required this.onToggle,
    required this.onMoveStart,
    required this.onResizeStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final card = TimelineTaskCard(
      task: task,
      height: height,
      completed: completed,
      isPast: isPast,
      isNow: isNow,
      timeLabel: timeLabel,
      onTap: onTap,
      onToggleComplete: onToggle,
    );

    return AnimatedScale(
      scale: isDragging ? 1.03 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: isDragging ? skin.dragShadow : const [],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onLongPressStart: (_) => onMoveStart(),
                onLongPressMoveUpdate: (d) => onDragUpdate(d.offsetFromOrigin.dy),
                onLongPressEnd: (_) => onDragEnd(),
                onLongPressCancel: onDragEnd,
                child: card,
              ),
            ),
            // Tirador de duración. Solo aparece si el bloque tiene alto para
            // mostrarlo sin taparse a sí mismo.
            if (height >= 40)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 16,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (_) => onResizeStart(),
                  onVerticalDragUpdate: (d) => onDragUpdate(d.delta.dy),
                  onVerticalDragEnd: (_) => onDragEnd(),
                  onVerticalDragCancel: onDragEnd,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: isDragging ? 34 : 24,
                      height: 3,
                      decoration: BoxDecoration(
                        color: skin.grip(isDragging),
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}


/// Los tokens que separan una piel de la otra.
///
/// El timeline pinta seis cosas: la franja de foco, la rejilla de horas, la
/// línea del ahora, el borrador (en sus dos fases), los chips de duración y el
/// bloque mientras se arrastra. La geometría de las seis es común; esto es lo
/// único que cambia.
///
/// Que sea una clase y no un puñado de `if` repartidos tiene una consecuencia
/// práctica: al añadir un elemento al timeline hay que darle su token aquí, y
/// entonces es imposible olvidarse de la otra piel.
class _TimelineSkin {
  const _TimelineSkin({
    required this.peakFill,
    required this.peakEdge,
    required this.peakLabel,
    required this.pillFill,
    required this.pillInk,
    required this.pillLabel,
    required this.nowMark,
    required this.nowRule,
    required this.nowLabel,
    required this.draftGhostFill,
    required this.draftEdge,
    required this.draftFill,
    required this.draftBorder,
    required this.draftShadow,
    required this.draftRange,
    required this.draftField,
    required this.draftHint,
    required this.draftInk,
    required this.draftConfirm,
    required this.draftDismiss,
    required this.chipOnFill,
    required this.chipOffFill,
    required this.chipOnLabel,
    required this.chipOffLabel,
    required this.dragShadow,
    required this.hourLine,
    required this.halfHourLine,
    required this.hourLabel,
    required this.grip,
  });

  final Color peakFill;
  final Color peakEdge;
  final TextStyle peakLabel;

  final Color pillFill;
  final Color pillInk;
  final TextStyle pillLabel;

  final Color nowMark;
  final Color nowRule;
  final TextStyle nowLabel;

  final Color draftGhostFill;
  final Color draftEdge;
  final Color draftFill;
  final BoxBorder? draftBorder;
  final List<BoxShadow> draftShadow;
  final TextStyle draftRange;
  final TextStyle draftField;
  final TextStyle draftHint;
  final Color draftInk;
  final Color draftConfirm;
  final Color draftDismiss;

  final Color chipOnFill;
  final Color chipOffFill;
  final TextStyle chipOnLabel;
  final TextStyle chipOffLabel;

  final List<BoxShadow> dragShadow;

  /// Los cuatro tokens que dependen del estado de la fila que se pinta.
  final Color Function(bool isPast) hourLine;
  final Color Function(bool isPast) halfHourLine;
  final TextStyle Function({required bool isCurrent, required bool isPast}) hourLabel;
  final Color Function(bool isDragging) grip;

  /// Relieve: el acento lima manda y el ahora es rojo.
  factory _TimelineSkin.neu() {
    final accent = BentoTheme.accentLime;
    return _TimelineSkin(
      peakFill: accent.withValues(alpha: 0.05),
      peakEdge: accent.withValues(alpha: 0.28),
      peakLabel: GoogleFonts.montserrat(
        fontSize: 8.5,
        letterSpacing: 1.3,
        fontWeight: FontWeight.w700,
        color: accent.withValues(alpha: 0.4),
      ),
      pillFill: BentoTheme.creamAlpha(0.06),
      pillInk: BentoTheme.creamAlpha(0.45),
      pillLabel: GoogleFonts.montserrat(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: BentoTheme.creamAlpha(0.45),
      ),
      nowMark: BentoTheme.errorRed,
      nowRule: BentoTheme.errorRed.withValues(alpha: 0.75),
      nowLabel: GoogleFonts.montserrat(
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        color: Colors.white,
      ),
      draftGhostFill: accent.withValues(alpha: 0.16),
      draftEdge: accent.withValues(alpha: 0.8),
      draftFill: Color.alphaBlend(accent.withValues(alpha: 0.10), BentoTheme.neuSurface),
      draftBorder: Border.all(color: accent.withValues(alpha: 0.75), width: 1.5),
      draftShadow: BentoTheme.neuFloating(elevation: 14),
      draftRange: GoogleFonts.montserrat(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
        color: accent,
      ),
      draftField: GoogleFonts.montserrat(
        color: BentoTheme.cream,
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
      draftHint: GoogleFonts.montserrat(
        color: BentoTheme.creamAlpha(0.35),
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      draftInk: BentoTheme.cream,
      draftConfirm: accent,
      draftDismiss: BentoTheme.creamAlpha(0.45),
      chipOnFill: accent,
      chipOffFill: BentoTheme.creamAlpha(0.07),
      chipOnLabel: GoogleFonts.montserrat(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF0C0C0D),
      ),
      chipOffLabel: GoogleFonts.montserrat(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: BentoTheme.creamAlpha(0.6),
      ),
      dragShadow: BentoTheme.neuFloating(elevation: 18),
      hourLine: (isPast) => BentoTheme.creamAlpha(isPast ? 0.04 : 0.08),
      halfHourLine: (isPast) => BentoTheme.creamAlpha(isPast ? 0.015 : 0.03),
      hourLabel: ({required isCurrent, required isPast}) => GoogleFonts.montserrat(
        fontSize: 10,
        fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
        letterSpacing: 0.1,
        color: isCurrent
            ? BentoTheme.accentLime
            : BentoTheme.creamAlpha(isCurrent ? 0.85 : (isPast ? 0.18 : 0.42)),
      ),
      grip: (isDragging) => BentoTheme.creamAlpha(isDragging ? 0.55 : 0.16),
    );
  }

  /// Editorial: cero acento de marca, y **la línea del ahora es papel**.
  ///
  /// El rojo se descartó aquí a propósito. En este sistema el rojo significa
  /// "esto destruye" —borrar una nota, eliminar una alarma— y gastarlo en algo
  /// que ocurre continuamente y no es un error lo devaluaría. Además la línea
  /// del ahora no necesita color: es la ÚNICA línea blanca sobre un lienzo
  /// donde las horas son filetes al 8%, así que no se puede confundir con nada.
  ///
  /// La franja de foco pierde el relleno y se queda en un filete izquierdo. Un
  /// bloque teñido de seis horas de alto compite con las tarjetas que viven
  /// dentro de él, que es justo lo que hay que leer.
  factory _TimelineSkin.editorial() {
    return _TimelineSkin(
      peakFill: Colors.transparent,
      peakEdge: EditorialTheme.paperAlpha(0.18),
      peakLabel: EditorialTheme.label(8.5, color: EditorialTheme.paperAlpha(0.3)),
      pillFill: EditorialTheme.surfaceHigh,
      pillInk: EditorialTheme.muted,
      pillLabel: EditorialTheme.text(10.5, weight: FontWeight.w500, color: EditorialTheme.muted),
      nowMark: EditorialTheme.paper,
      nowRule: EditorialTheme.paperAlpha(0.85),
      nowLabel: EditorialTheme.text(9.5, weight: FontWeight.w700, color: EditorialTheme.ink),
      draftGhostFill: EditorialTheme.paperAlpha(0.14),
      draftEdge: EditorialTheme.paperAlpha(0.7),
      draftFill: EditorialTheme.paper,
      // Sin borde ni sombra: sobre el lienzo oscuro, una lámina blanca ya se
      // separa sola. Añadirle elevación sería pintar dos veces lo mismo.
      draftBorder: null,
      draftShadow: const [],
      draftRange: EditorialTheme.text(11, weight: FontWeight.w700, color: EditorialTheme.grayText),
      draftField: EditorialTheme.text(14.5, weight: FontWeight.w600, color: EditorialTheme.ink),
      draftHint: EditorialTheme.text(14.5, color: EditorialTheme.grayText),
      draftInk: EditorialTheme.ink,
      draftConfirm: EditorialTheme.ink,
      draftDismiss: EditorialTheme.grayText,
      chipOnFill: EditorialTheme.ink,
      chipOffFill: EditorialTheme.gray,
      chipOnLabel: EditorialTheme.text(10.5, weight: FontWeight.w600, color: EditorialTheme.paper),
      chipOffLabel: EditorialTheme.text(10.5, weight: FontWeight.w600, color: EditorialTheme.grayText),
      dragShadow: const [],
      hourLine: (isPast) => EditorialTheme.paperAlpha(isPast ? 0.05 : 0.10),
      halfHourLine: (isPast) => EditorialTheme.paperAlpha(isPast ? 0.02 : 0.04),
      hourLabel: ({required isCurrent, required isPast}) => EditorialTheme.text(
        10.5,
        weight: isCurrent ? FontWeight.w700 : FontWeight.w500,
        color: isCurrent
            ? EditorialTheme.paper
            : EditorialTheme.paperAlpha(isPast ? 0.22 : 0.45),
      ),
      grip: (isDragging) => EditorialTheme.paperAlpha(isDragging ? 0.7 : 0.22),
    );
  }
}
