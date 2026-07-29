import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/task_model.dart';
import '../../../core/theme/bento_theme.dart';
import '../timeline_scale.dart';
import 'timeline_task_card.dart';

/// Franja del día donde la mayoría rinde mejor en trabajo cognitivo. Se pinta
/// como una banda tenue para empujar (sin obligar) a poner ahí lo importante,
/// en vez de dejarlo para cuando ya no queda voluntad.
const _peakStartHour = 8;
const _peakEndHour = 12;

const _gutterWidth = 48.0;
const _laneGap = 4.0;

enum _DragMode { move, resize }

class _BlockDrag {
  final Task task;
  final _DragMode mode;
  final int originalStart;
  final int originalEnd;
  int start;
  int end;

  _BlockDrag({
    required this.task,
    required this.mode,
    required this.originalStart,
    required this.originalEnd,
  })  : start = originalStart,
        end = originalEnd;
}

/// Timeline de un día con creación por arrastre.
///
/// El gesto principal es mantener y arrastrar sobre una franja vacía: eso crea
/// el bloque con las horas exactas y abre un campo de título en línea, sin
/// abrir ningún formulario. Es la diferencia entre un gesto y media docena de
/// taps, y es lo que hace viable planear un día entero de una sentada.
///
/// Se usa pulsación larga (no arrastre directo) a propósito: dentro de un
/// scroll vertical, un arrastre inmediato competiría con el scroll y el
/// resultado sería impredecible.
class DayTimeline extends StatefulWidget {
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
  State<DayTimeline> createState() => _DayTimelineState();
}

class _DayTimelineState extends State<DayTimeline> {
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

    final now = DateTime.now();
    final isToday = DateTime(widget.day.year, widget.day.month, widget.day.day) ==
        DateTime(now.year, now.month, now.day);

    // Hoy: la hora actual. Otro día: el primer bloque, o el inicio de la
    // jornada si está vacío. Abrir un día siempre en 00:00 obliga a scrollear
    // antes de poder hacer nada.
    final int anchorMinutes;
    if (isToday) {
      anchorMinutes = minutesOfDay(now);
    } else if (widget.tasks.isNotEmpty) {
      anchorMinutes = widget.tasks.map((t) => minutesOfDay(t.startAt)).reduce((a, b) => a < b ? a : b);
    } else {
      anchorMinutes = _peakStartHour * 60;
    }

    final target = (scale.yForMinutes(anchorMinutes) - 120).clamp(0.0, scale.totalHeight);
    _scrollController.jumpTo(target.clamp(0.0, _scrollController.position.maxScrollExtent));
  }

  // ---------------------------------------------------------------- crear

  void _onCreateStart(LongPressStartDetails details, TimelineScale scale) {
    if (_draftEditing) {
      _cancelDraft();
      return;
    }
    HapticFeedback.selectionClick();
    final m = TimelineScale.snap(scale.minutesForY(details.localPosition.dy));
    setState(() {
      _draftStart = m;
      _draftEnd = (m + 30).clamp(0, TimelineScale.minutesPerDay);
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
    if (_draftStart == null) return;
    setState(() => _draftEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _draftFocus.requestFocus());
  }

  void _cancelDraft() {
    _draftController.clear();
    setState(() {
      _draftStart = null;
      _draftEnd = null;
      _draftEditing = false;
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
    widget.onReschedule(drag.task, _dateAt(drag.start), _dateAt(drag.end));
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToRelevantHour(scale));

    return LayoutBuilder(
      builder: (context, constraints) {
        final laneAreaWidth = constraints.maxWidth - _gutterWidth;
        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.only(bottom: 140),
          child: SizedBox(
            height: scale.totalHeight,
            child: Stack(
              children: [
                // Capa de gestos al fondo: los bloques, al estar encima, se
                // quedan con sus propios toques antes de llegar aquí.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _draftEditing ? _cancelDraft : null,
                    onLongPressStart: (d) => _onCreateStart(d, scale),
                    onLongPressMoveUpdate: (d) => _onCreateUpdate(d, scale),
                    onLongPressEnd: (_) => _onCreateEnd(),
                  ),
                ),
                ..._buildPeakBand(scale, laneAreaWidth),
                ..._buildGrid(scale),
                if (_draftStart != null) _buildDraft(scale, laneAreaWidth),
                ..._buildBlocks(scale, laneAreaWidth),
                ..._buildNowLine(scale),
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
        left: _gutterWidth,
        width: laneAreaWidth,
        height: bottom - top,
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              color: BentoTheme.accentLime.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildGrid(TimelineScale scale) {
    final widgets = <Widget>[];

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
              const SizedBox(width: 8),
              Icon(Icons.expand_more, size: 15, color: BentoTheme.creamAlpha(0.35)),
              const SizedBox(width: 4),
              Text(
                '00:00 – 06:00',
                style: GoogleFonts.montserrat(fontSize: 11, fontWeight: FontWeight.w600, color: BentoTheme.creamAlpha(0.35)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Container(height: 1, color: BentoTheme.creamAlpha(0.06))),
            ],
          ),
        ),
      ));
    }

    final firstHour = scale.isCollapsing ? _nightBoundaryHour : 0;
    for (var hour = firstHour; hour < 24; hour++) {
      widgets.add(Positioned(
        top: scale.yForMinutes(hour * 60),
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 40,
                child: Text(
                  '${hour.toString().padLeft(2, '0')}:00',
                  style: GoogleFonts.montserrat(fontSize: 10, color: BentoTheme.creamAlpha(0.35)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 1, color: BentoTheme.creamAlpha(0.08))),
            ],
          ),
        ),
      ));
    }

    if (scale.isCollapsing == false && _nightExpanded) {
      widgets.add(Positioned(
        top: 0,
        right: 8,
        child: GestureDetector(
          onTap: () => setState(() => _nightExpanded = false),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.unfold_less, size: 16, color: BentoTheme.creamAlpha(0.4)),
          ),
        ),
      ));
    }

    return widgets;
  }

  List<Widget> _buildNowLine(TimelineScale scale) {
    final now = DateTime.now();
    final isToday = DateTime(widget.day.year, widget.day.month, widget.day.day) ==
        DateTime(now.year, now.month, now.day);
    if (!isToday) return const [];
    return [
      Positioned(
        top: scale.yForTime(now),
        left: _gutterWidth - 4,
        right: 0,
        child: IgnorePointer(
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: BentoTheme.errorRed, shape: BoxShape.circle),
              ),
              Expanded(child: Container(height: 1.5, color: BentoTheme.errorRed)),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildDraft(TimelineScale scale, double laneAreaWidth) {
    final start = _draftStart!;
    final end = _draftEnd!;
    final top = scale.yForMinutes(start);
    final height = scale.heightForRange(start, end);

    return Positioned(
      top: top,
      left: _gutterWidth,
      width: laneAreaWidth,
      height: _draftEditing ? (height < 52 ? 52 : height) : height,
      child: Container(
        decoration: BoxDecoration(
          color: BentoTheme.accentLime.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: BentoTheme.accentLime, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: _draftEditing
            ? Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _draftController,
                      focusNode: _draftFocus,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submitDraft(),
                      style: GoogleFonts.montserrat(
                        color: BentoTheme.cream,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '${_fmt(start)} – ${_fmt(end)}   ¿qué vas a hacer?',
                        hintStyle: GoogleFonts.montserrat(
                          color: BentoTheme.creamAlpha(0.45),
                          fontWeight: FontWeight.w500,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _cancelDraft,
                    child: Icon(Icons.close, size: 17, color: BentoTheme.creamAlpha(0.5)),
                  ),
                  const SizedBox(width: 2),
                  GestureDetector(
                    onTap: _submitDraft,
                    child: Icon(Icons.check, size: 19, color: BentoTheme.accentLime),
                  ),
                ],
              )
            : Align(
                alignment: Alignment.topLeft,
                child: Text(
                  '${_fmt(start)} – ${_fmt(end)}',
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: BentoTheme.accentLime,
                  ),
                ),
              ),
      ),
    );
  }

  List<Widget> _buildBlocks(TimelineScale scale, double laneAreaWidth) {
    final drag = _blockDrag;
    final laid = layoutBlocks(widget.tasks);

    return [
      for (final block in laid)
        () {
          final isDragging = drag?.task.id == block.task.id;
          final start = isDragging ? drag!.start : block.startMinutes;
          final end = isDragging ? drag!.end : block.endMinutes;

          final laneWidth = (laneAreaWidth - _laneGap * (block.laneCount - 1)) / block.laneCount;
          final left = _gutterWidth + block.lane * (laneWidth + _laneGap);
          final height = scale.heightForRange(start, end);

          return Positioned(
            top: scale.yForMinutes(start),
            left: left,
            width: laneWidth,
            height: height,
            child: _DraggableBlock(
              key: ValueKey(block.task.id),
              task: block.task,
              height: height,
              completed: _isCompleted(block.task),
              isDragging: isDragging,
              timeLabel: '${_fmt(start)} – ${_fmt(end)}',
              onTap: () => widget.onTapBlock(block.task),
              onToggle: () => widget.onToggleBlock(block.task),
              onMoveStart: () => _onBlockDragStart(block.task, _DragMode.move),
              onResizeStart: () => _onBlockDragStart(block.task, _DragMode.resize),
              onDragUpdate: (dy) => _onBlockDragUpdate(dy, scale),
              onDragEnd: _onBlockDragEnd,
            ),
          );
        }(),
    ];
  }
}

String _fmt(int minutes) {
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Envuelve la tarjeta con los gestos de mover y estirar.
///
/// Mover exige pulsación larga primero (para no arrastrar bloques sin querer
/// al scrollear); estirar usa el tirador de abajo, que es un objetivo
/// explícito y no necesita pulsación previa.
class _DraggableBlock extends StatelessWidget {
  final Task task;
  final double height;
  final bool completed;
  final bool isDragging;
  final String timeLabel;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onMoveStart;
  final VoidCallback onResizeStart;
  final void Function(double deltaY) onDragUpdate;
  final VoidCallback onDragEnd;

  const _DraggableBlock({
    super.key,
    required this.task,
    required this.height,
    required this.completed,
    required this.isDragging,
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
      timeLabel: timeLabel,
      onTap: onTap,
      onToggleComplete: onToggle,
    );

    return AnimatedScale(
      scale: isDragging ? 1.03 : 1.0,
      duration: const Duration(milliseconds: 120),
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
                  child: Container(
                    width: 26,
                    height: 3,
                    decoration: BoxDecoration(
                      color: BentoTheme.creamAlpha(isDragging ? 0.5 : 0.18),
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
