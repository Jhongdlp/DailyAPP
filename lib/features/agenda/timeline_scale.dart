import '../../core/models/task_model.dart';

/// Conversión entre hora del día y posición vertical en el timeline.
///
/// Vive aparte y sin dependencias de Flutter porque es exactamente la parte
/// que estaba mal: antes los minutos se usaban directamente como píxeles
/// mientras la rejilla dibujaba una línea cada 64px, así que un bloque de las
/// 23:00 aparecía hora y media más arriba de donde debía.
///
/// Además pliega la madrugada: las horas de [collapseUntilHour] hacia atrás
/// se comprimen en una sola banda de [collapsedHeight] píxeles, porque
/// scrollear seis horas vacías cada vez que abres el día es fricción pura.
class TimelineScale {
  final double hourHeight;

  /// Hora a la que termina la banda plegada. 0 = sin plegado.
  final int collapseUntilHour;

  /// Alto total de la banda plegada, en píxeles.
  final double collapsedHeight;

  const TimelineScale({
    this.hourHeight = 72.0,
    this.collapseUntilHour = 0,
    this.collapsedHeight = 44.0,
  });

  static const minutesPerDay = 24 * 60;

  /// Granularidad de los gestos. 15 min es lo bastante fino para ser útil y
  /// lo bastante grueso para no exigir puntería.
  static const snapMinutes = 15;

  int get _boundary => collapseUntilHour * 60;

  bool get isCollapsing => collapseUntilHour > 0;

  double get totalHeight => yForMinutes(minutesPerDay);

  /// Píxeles desde el inicio del timeline para el minuto [m] del día.
  double yForMinutes(int m) {
    final clamped = m.clamp(0, minutesPerDay);
    if (!isCollapsing) return clamped * hourHeight / 60;
    if (clamped <= _boundary) {
      // Dentro de la banda plegada se reparte proporcionalmente, para que un
      // bloque a las 3am siga cayendo a media banda y no en su borde.
      return _boundary == 0 ? 0 : clamped / _boundary * collapsedHeight;
    }
    return collapsedHeight + (clamped - _boundary) * hourHeight / 60;
  }

  double yForTime(DateTime d) => yForMinutes(d.hour * 60 + d.minute);

  /// Inversa de [yForMinutes].
  int minutesForY(double y) {
    if (y <= 0) return 0;
    if (!isCollapsing) {
      return (y * 60 / hourHeight).round().clamp(0, minutesPerDay);
    }
    if (y <= collapsedHeight) {
      return (y / collapsedHeight * _boundary).round().clamp(0, minutesPerDay);
    }
    return (_boundary + (y - collapsedHeight) * 60 / hourHeight)
        .round()
        .clamp(0, minutesPerDay);
  }

  /// Alto en píxeles de un bloque que va de [startMinutes] a [endMinutes].
  /// Se calcula como diferencia de posiciones y no como `duración × escala`,
  /// para que un bloque que cruza la banda plegada siga cuadrando con la
  /// rejilla.
  double heightForRange(int startMinutes, int endMinutes) {
    final h = yForMinutes(endMinutes) - yForMinutes(startMinutes);
    return h < minBlockHeight ? minBlockHeight : h;
  }

  static const minBlockHeight = 26.0;

  static int snap(int minutes) =>
      ((minutes / snapMinutes).round() * snapMinutes).clamp(0, minutesPerDay);
}

/// Minutos desde medianoche de una hora local.
int minutesOfDay(DateTime d) => d.hour * 60 + d.minute;

/// Minuto de fin de un bloque dentro de su día. Un bloque sin fin ocupa el
/// mínimo visible; uno que cruza medianoche se corta a las 24:00 para no
/// desbordar el día que se está mirando.
int endMinutesOf(Task task, {int fallbackDuration = 40}) {
  final start = minutesOfDay(task.startAt);
  if (task.endAt == null) return (start + fallbackDuration).clamp(0, TimelineScale.minutesPerDay);
  final crossesMidnight = task.endAt!.day != task.startAt.day ||
      task.endAt!.month != task.startAt.month ||
      task.endAt!.year != task.startAt.year;
  if (crossesMidnight) return TimelineScale.minutesPerDay;
  return minutesOfDay(task.endAt!).clamp(start, TimelineScale.minutesPerDay);
}

/// Un bloque con su carril asignado, para repartir el ancho entre los que se
/// solapan en vez de dejar que se tapen unos a otros.
class LaidOutBlock {
  final Task task;
  final int startMinutes;
  final int endMinutes;

  /// Carril que ocupa, de 0 a [laneCount] - 1.
  final int lane;

  /// Carriles del grupo al que pertenece.
  final int laneCount;

  const LaidOutBlock({
    required this.task,
    required this.startMinutes,
    required this.endMinutes,
    required this.lane,
    required this.laneCount,
  });
}

/// Reparte los bloques en carriles: los que se cruzan en el tiempo quedan lado
/// a lado, los que no ocupan todo el ancho.
///
/// Agrupa por "clusters" conectados (A solapa con B y B con C ⇒ los tres
/// comparten reparto aunque A y C no se toquen), que es lo que hace que las
/// columnas se vean parejas en vez de saltar de ancho a media pantalla.
List<LaidOutBlock> layoutBlocks(List<Task> tasks) {
  if (tasks.isEmpty) return const [];

  final entries = tasks
      .map((t) => (
            task: t,
            start: minutesOfDay(t.startAt),
            end: endMinutesOf(t),
          ))
      .toList()
    ..sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : b.end.compareTo(a.end);
    });

  final result = <LaidOutBlock>[];
  var cluster = <({Task task, int start, int end})>[];
  var clusterEnd = -1;

  void flushCluster() {
    if (cluster.isEmpty) return;
    // Asignación voraz: cada bloque va al primer carril libre.
    final laneEnds = <int>[];
    final lanes = <int>[];
    for (final e in cluster) {
      var lane = laneEnds.indexWhere((end) => end <= e.start);
      if (lane == -1) {
        laneEnds.add(e.end);
        lane = laneEnds.length - 1;
      } else {
        laneEnds[lane] = e.end;
      }
      lanes.add(lane);
    }
    final count = laneEnds.length;
    for (var i = 0; i < cluster.length; i++) {
      result.add(LaidOutBlock(
        task: cluster[i].task,
        startMinutes: cluster[i].start,
        endMinutes: cluster[i].end,
        lane: lanes[i],
        laneCount: count,
      ));
    }
    cluster = [];
    clusterEnd = -1;
  }

  for (final e in entries) {
    if (cluster.isNotEmpty && e.start >= clusterEnd) flushCluster();
    cluster.add(e);
    if (e.end > clusterEnd) clusterEnd = e.end;
  }
  flushCluster();

  return result;
}
