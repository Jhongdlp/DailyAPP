import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/providers/focus_stats_provider.dart';
import '../../../core/providers/notes_provider.dart';
import '../../../core/services/alarm_service.dart';
import '../../../core/services/cache_service.dart';

enum PomodoroPhase { focus, shortBreak, longBreak }

extension PomodoroPhaseX on PomodoroPhase {
  bool get isFocus => this == PomodoroPhase.focus;
  bool get isBreak => this != PomodoroPhase.focus;

  String get label => switch (this) {
        PomodoroPhase.focus => 'ENFOQUE',
        PomodoroPhase.shortBreak => 'DESCANSO',
        PomodoroPhase.longBreak => 'DESCANSO LARGO',
      };
}

/// Una interrupción anotada sin salir de la sesión. Sacarla de la cabeza y
/// dejarla escrita es justo lo que evita que rompa el enfoque.
class Distraction {
  final String text;
  final DateTime capturedAt;

  const Distraction({required this.text, required this.capturedAt});
}

/// Ajustes que sobreviven a cerrar la app. Se guardan aparte del estado vivo
/// del temporizador: las duraciones son preferencia, el tiempo restante no.
class PomodoroPrefs {
  final int workDuration;
  final int breakDuration;
  final int longBreakDuration;
  final int sessionsBeforeLongBreak;

  /// Encadenar el descanso automáticamente al terminar el enfoque. Por defecto
  /// sí: la fricción aquí solo sirve para saltarse el descanso.
  final bool autoStartBreaks;

  /// Encadenar el enfoque automáticamente al terminar el descanso. Por defecto
  /// no: volver a enfocarse debería ser una decisión consciente.
  final bool autoStartFocus;

  /// Qué se muestra durante el descanso (0 frase, 1 imagen, 2 respiración,
  /// 3 tareas). Durante el enfoque no se muestra nada de esto a propósito.
  final int breakPanelMode;

  const PomodoroPrefs({
    this.workDuration = 25,
    this.breakDuration = 5,
    this.longBreakDuration = 15,
    this.sessionsBeforeLongBreak = 4,
    this.autoStartBreaks = true,
    this.autoStartFocus = false,
    this.breakPanelMode = 0,
  });

  PomodoroPrefs copyWith({
    int? workDuration,
    int? breakDuration,
    int? longBreakDuration,
    int? sessionsBeforeLongBreak,
    bool? autoStartBreaks,
    bool? autoStartFocus,
    int? breakPanelMode,
  }) {
    return PomodoroPrefs(
      workDuration: workDuration ?? this.workDuration,
      breakDuration: breakDuration ?? this.breakDuration,
      longBreakDuration: longBreakDuration ?? this.longBreakDuration,
      sessionsBeforeLongBreak:
          sessionsBeforeLongBreak ?? this.sessionsBeforeLongBreak,
      autoStartBreaks: autoStartBreaks ?? this.autoStartBreaks,
      autoStartFocus: autoStartFocus ?? this.autoStartFocus,
      breakPanelMode: breakPanelMode ?? this.breakPanelMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'work': workDuration,
        'break': breakDuration,
        'long_break': longBreakDuration,
        'sessions_before_long': sessionsBeforeLongBreak,
        'auto_breaks': autoStartBreaks,
        'auto_focus': autoStartFocus,
        'break_panel': breakPanelMode,
      };

  factory PomodoroPrefs.fromJson(Map<String, dynamic> json) => PomodoroPrefs(
        workDuration: (json['work'] as num?)?.toInt() ?? 25,
        breakDuration: (json['break'] as num?)?.toInt() ?? 5,
        longBreakDuration: (json['long_break'] as num?)?.toInt() ?? 15,
        sessionsBeforeLongBreak:
            (json['sessions_before_long'] as num?)?.toInt() ?? 4,
        autoStartBreaks: json['auto_breaks'] as bool? ?? true,
        autoStartFocus: json['auto_focus'] as bool? ?? false,
        breakPanelMode: (json['break_panel'] as num?)?.toInt() ?? 0,
      );
}

class PomodoroState {
  final PomodoroPrefs prefs;
  final PomodoroPhase phase;
  final bool isActive;

  /// Enfoques completados en la tanda actual, de 0 a
  /// [PomodoroPrefs.sessionsBeforeLongBreak]. Se reinicia tras el descanso largo,
  /// que es lo que hace que los puntos de ciclo se lean sin aritmética modular.
  final int cycleInSet;

  /// Enfoques completados desde que se abrió la pantalla.
  final int completedFocusSessions;

  final int timeLeft; // segundos
  final DateTime? targetEndTime;

  /// Segundos añadidos a mano al bloque en curso. Cuentan como parte de su
  /// duración, para que alargar no haga retroceder el anillo de progreso.
  final int extraSeconds;

  /// Cuándo arrancó el bloque actual, para saber cuánto se enfocó de verdad si
  /// se abandona a medias.
  final DateTime? phaseStartedAt;

  final String? focusedTaskId;
  final String? focusedTaskTitle;

  final List<Distraction> distractions;
  final int carouselIndex;

  const PomodoroState({
    this.prefs = const PomodoroPrefs(),
    this.phase = PomodoroPhase.focus,
    this.isActive = false,
    this.cycleInSet = 0,
    this.completedFocusSessions = 0,
    this.timeLeft = 25 * 60,
    this.targetEndTime,
    this.extraSeconds = 0,
    this.phaseStartedAt,
    this.focusedTaskId,
    this.focusedTaskTitle,
    this.distractions = const [],
    this.carouselIndex = 0,
  });

  int get phaseDurationSeconds =>
      switch (phase) {
        PomodoroPhase.focus => prefs.workDuration * 60,
        PomodoroPhase.shortBreak => prefs.breakDuration * 60,
        PomodoroPhase.longBreak => prefs.longBreakDuration * 60,
      } +
      extraSeconds;

  /// Segundos ya transcurridos del bloque. [timeLeft] es siempre la verdad
  /// sobre lo que queda (las pausas lo congelan, no lo pierden), así que basta
  /// restarlo: no hace falta acumular tramos entre pausas.
  int get elapsedSeconds =>
      (phaseDurationSeconds - timeLeft).clamp(0, phaseDurationSeconds);

  /// 0 al empezar el bloque, 1 al terminarlo. El anillo avanza en lugar de
  /// vaciarse: ver crecer lo hecho motiva más que ver menguar lo que queda.
  double get progress {
    final total = phaseDurationSeconds;
    if (total <= 0) return 0;
    return (elapsedSeconds / total).clamp(0.0, 1.0);
  }

  /// Hora a la que termina el bloque en curso, para el "termina a las 15:42".
  DateTime? get endsAt => isActive ? targetEndTime : null;

  PomodoroState copyWith({
    PomodoroPrefs? prefs,
    PomodoroPhase? phase,
    bool? isActive,
    int? cycleInSet,
    int? completedFocusSessions,
    int? timeLeft,
    DateTime? targetEndTime,
    bool clearTargetEndTime = false,
    int? extraSeconds,
    DateTime? phaseStartedAt,
    bool clearPhaseStartedAt = false,
    String? focusedTaskId,
    String? focusedTaskTitle,
    bool clearFocusedTask = false,
    List<Distraction>? distractions,
    int? carouselIndex,
  }) {
    return PomodoroState(
      prefs: prefs ?? this.prefs,
      phase: phase ?? this.phase,
      isActive: isActive ?? this.isActive,
      cycleInSet: cycleInSet ?? this.cycleInSet,
      completedFocusSessions:
          completedFocusSessions ?? this.completedFocusSessions,
      timeLeft: timeLeft ?? this.timeLeft,
      targetEndTime:
          clearTargetEndTime ? null : (targetEndTime ?? this.targetEndTime),
      extraSeconds: extraSeconds ?? this.extraSeconds,
      phaseStartedAt:
          clearPhaseStartedAt ? null : (phaseStartedAt ?? this.phaseStartedAt),
      focusedTaskId: clearFocusedTask ? null : (focusedTaskId ?? this.focusedTaskId),
      focusedTaskTitle:
          clearFocusedTask ? null : (focusedTaskTitle ?? this.focusedTaskTitle),
      distractions: distractions ?? this.distractions,
      carouselIndex: carouselIndex ?? this.carouselIndex,
    );
  }
}

class PomodoroNotifier extends Notifier<PomodoroState> {
  static const _prefsCacheKey = 'pomodoro_prefs';

  /// Bloque 700000–799999. Estaba en 500000, el mismo id exacto que
  /// `NightPlanningService`: como los servicios cancelan **recalculando** ids y
  /// no leyendo la cola, cada aviso nocturno programado borraba la notificación
  /// de fin de pomodoro y viceversa. Este es el siguiente bloque libre tras
  /// `WeeklyReviewService` (600000–699999).
  static const _notificationId = 700000;

  Timer? _timer;
  Timer? _carouselTimer;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  PomodoroState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _carouselTimer?.cancel();
    });

    _loadPrefs();
    return const PomodoroState();
  }

  Future<void> _loadPrefs() async {
    try {
      final cached = await CacheService.read(_prefsCacheKey);
      if (cached is Map<String, dynamic>) {
        final prefs = PomodoroPrefs.fromJson(cached);
        // Solo se aplica si el temporizador está parado y virgen: reescribir la
        // duración a mitad de una sesión movería el objetivo bajo los pies.
        if (!state.isActive && state.phaseStartedAt == null) {
          state = state.copyWith(
            prefs: prefs,
            timeLeft: prefs.workDuration * 60,
          );
        }
      }
    } catch (_) {
      // Caché corrupto: se usan los valores por defecto
    }
  }

  Future<void> _persistPrefs() =>
      CacheService.save(_prefsCacheKey, state.prefs.toJson());

  // ── Configuración ──────────────────────────────────────────────────────

  void configure({
    required int workDuration,
    required int breakDuration,
    required int longBreakDuration,
    required bool autoStartBreaks,
    required bool autoStartFocus,
    required int breakPanelMode,
    String? focusedTaskId,
    String? focusedTaskTitle,
  }) {
    _timer?.cancel();
    _carouselTimer?.cancel();
    unawaited(_cancelNotification());

    state = PomodoroState(
      prefs: state.prefs.copyWith(
        workDuration: workDuration,
        breakDuration: breakDuration,
        longBreakDuration: longBreakDuration,
        autoStartBreaks: autoStartBreaks,
        autoStartFocus: autoStartFocus,
        breakPanelMode: breakPanelMode,
      ),
      timeLeft: workDuration * 60,
      focusedTaskId: focusedTaskId,
      focusedTaskTitle: focusedTaskTitle,
    );
    unawaited(_persistPrefs());
  }

  void setBreakPanelMode(int mode) {
    state = state.copyWith(prefs: state.prefs.copyWith(breakPanelMode: mode));
    unawaited(_persistPrefs());
    if (mode == 1 && state.isActive) {
      _startCarouselTimer();
    } else {
      _carouselTimer?.cancel();
    }
  }

  void setAutoStart({bool? breaks, bool? focus}) {
    state = state.copyWith(
      prefs: state.prefs.copyWith(autoStartBreaks: breaks, autoStartFocus: focus),
    );
    unawaited(_persistPrefs());
  }

  void setFocusedTask(String? id, String? title) {
    state = id == null
        ? state.copyWith(clearFocusedTask: true)
        : state.copyWith(focusedTaskId: id, focusedTaskTitle: title);
  }

  /// Alarga el bloque en curso sin romperlo. Es la válvula de escape para "voy
  /// a medio párrafo" al sonar el timbre.
  void extendPhase(int minutes) {
    final extra = minutes * 60;
    if (state.isActive && state.targetEndTime != null) {
      final newTarget = state.targetEndTime!.add(Duration(seconds: extra));
      state = state.copyWith(
        targetEndTime: newTarget,
        timeLeft: state.timeLeft + extra,
        extraSeconds: state.extraSeconds + extra,
      );
      unawaited(_scheduleNotification(newTarget));
    } else {
      state = state.copyWith(
        timeLeft: state.timeLeft + extra,
        extraSeconds: state.extraSeconds + extra,
      );
    }
    HapticFeedback.selectionClick();
  }

  // ── Control del temporizador ───────────────────────────────────────────

  void start() {
    if (state.isActive || state.timeLeft <= 0) return;

    final targetEnd = DateTime.now().add(Duration(seconds: state.timeLeft));
    state = state.copyWith(
      isActive: true,
      targetEndTime: targetEnd,
      phaseStartedAt: state.phaseStartedAt ?? DateTime.now(),
    );

    unawaited(_scheduleNotification(targetEnd));
    _startTimer();

    if (state.phase.isBreak && state.prefs.breakPanelMode == 1) {
      _startCarouselTimer();
    }
  }

  void pause() {
    if (!state.isActive) return;
    _timer?.cancel();
    _carouselTimer?.cancel();
    unawaited(_cancelNotification());

    // `timeLeft` ya guarda lo que quedaba: soltar el objetivo congela el bloque
    // sin perder lo transcurrido.
    state = state.copyWith(isActive: false, clearTargetEndTime: true);
  }

  void toggle() => state.isActive ? pause() : start();

  /// Termina la sesión entera. Registra lo enfocado hasta ahora aunque el
  /// bloque quedara a medias: media hora de enfoque real cuenta.
  void stop() {
    _timer?.cancel();
    _carouselTimer?.cancel();
    unawaited(_cancelNotification());

    _registerFocusIfAny(completed: false);

    state = state.copyWith(
      isActive: false,
      timeLeft: _baseMinutesFor(state.phase) * 60,
      extraSeconds: 0,
      clearTargetEndTime: true,
      clearPhaseStartedAt: true,
    );
  }

  int _baseMinutesFor(PomodoroPhase phase) => switch (phase) {
        PomodoroPhase.focus => state.prefs.workDuration,
        PomodoroPhase.shortBreak => state.prefs.breakDuration,
        PomodoroPhase.longBreak => state.prefs.longBreakDuration,
      };

  /// Cierra el bloque como si el reloj hubiera llegado a cero. Lo usa el
  /// temporizador, y es el único camino por el que un enfoque cuenta como
  /// pomodoro completo.
  @visibleForTesting
  void completePhase() => _advancePhase(completed: true);

  /// Salta al siguiente bloque a mano. Cuenta como bloque no terminado.
  void skip() {
    _timer?.cancel();
    _carouselTimer?.cancel();
    unawaited(_cancelNotification());
    _advancePhase(completed: false);
  }

  /// Reengancha el reloj tras volver del segundo plano, donde los `Timer` no
  /// corren: la verdad siempre es [PomodoroState.targetEndTime], no el tick.
  void syncWithBackground() {
    if (!state.isActive || state.targetEndTime == null) return;

    final diff = state.targetEndTime!.difference(DateTime.now()).inSeconds;
    if (diff <= 0) {
      _timer?.cancel();
      _advancePhase(completed: true);
    } else {
      state = state.copyWith(timeLeft: diff);
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final target = state.targetEndTime;
      if (target == null) {
        timer.cancel();
        return;
      }

      final diff = target.difference(DateTime.now()).inSeconds;
      if (diff <= 0) {
        timer.cancel();
        _advancePhase(completed: true);
      } else if (diff != state.timeLeft) {
        state = state.copyWith(timeLeft: diff);
      }
    });
  }

  void _startCarouselTimer() {
    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      state = state.copyWith(carouselIndex: state.carouselIndex + 1);
    });
  }

  /// Contabiliza el enfoque del bloque actual, si lo hubo. Solo se llama al
  /// salir de una fase de enfoque, nunca dos veces por el mismo bloque.
  void _registerFocusIfAny({required bool completed}) {
    if (!state.phase.isFocus) return;
    final startedAt = state.phaseStartedAt;
    if (startedAt == null) return;

    final seconds =
        completed ? state.phaseDurationSeconds : state.elapsedSeconds;
    if (seconds <= 0) return;

    ref.read(focusStatsProvider.notifier).registerFocusSession(
          startedAt: startedAt,
          seconds: seconds,
          completed: completed,
          taskId: state.focusedTaskId,
        );
  }

  void _advancePhase({required bool completed}) {
    final wasFocus = state.phase.isFocus;
    _registerFocusIfAny(completed: completed);

    if (completed) HapticFeedback.heavyImpact();

    PomodoroPhase nextPhase;
    var nextCycleInSet = state.cycleInSet;
    var nextCompleted = state.completedFocusSessions;

    if (wasFocus) {
      if (completed) {
        nextCycleInSet += 1;
        nextCompleted += 1;
      }
      nextPhase = nextCycleInSet >= state.prefs.sessionsBeforeLongBreak
          ? PomodoroPhase.longBreak
          : PomodoroPhase.shortBreak;
    } else {
      // El descanso largo cierra la tanda y devuelve los puntos a cero.
      if (state.phase == PomodoroPhase.longBreak) nextCycleInSet = 0;
      nextPhase = PomodoroPhase.focus;
    }

    state = state.copyWith(
      phase: nextPhase,
      isActive: false,
      cycleInSet: nextCycleInSet,
      completedFocusSessions: nextCompleted,
      timeLeft: _baseMinutesFor(nextPhase) * 60,
      extraSeconds: 0,
      clearTargetEndTime: true,
      clearPhaseStartedAt: true,
    );

    final shouldAutoStart = nextPhase.isBreak
        ? state.prefs.autoStartBreaks
        : state.prefs.autoStartFocus;
    if (shouldAutoStart) start();
  }

  // ── Bandeja de distracciones ───────────────────────────────────────────

  void captureDistraction(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    HapticFeedback.selectionClick();
    state = state.copyWith(
      distractions: [
        ...state.distractions,
        Distraction(text: trimmed, capturedAt: DateTime.now()),
      ],
    );
  }

  void removeDistraction(int index) {
    if (index < 0 || index >= state.distractions.length) return;
    final updated = [...state.distractions]..removeAt(index);
    state = state.copyWith(distractions: updated);
  }

  void clearDistractions() {
    state = state.copyWith(distractions: const []);
  }

  /// Vuelca la bandeja a una nota única y la vacía. Devuelve `false` si no
  /// había nada que guardar.
  Future<bool> saveDistractionsAsNote() async {
    if (state.distractions.isEmpty) return false;

    final now = DateTime.now();
    final stamp = '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/${now.year}';
    final body = state.distractions
        .map((d) =>
            '- [ ] ${d.text}  _(${d.capturedAt.hour.toString().padLeft(2, '0')}:'
            '${d.capturedAt.minute.toString().padLeft(2, '0')})_')
        .join('\n');

    await ref.read(notesProvider.notifier).addNote(
          'Distracciones · $stamp',
          'Capturado durante una sesión de enfoque:\n\n$body',
        );

    clearDistractions();
    return true;
  }

  // ── Notificaciones ─────────────────────────────────────────────────────

  Future<void> _scheduleNotification(DateTime targetEnd) async {
    if (kIsWeb) return;
    try {
      final when = tz.TZDateTime.from(targetEnd, tz.local);
      final String title;
      final String body;

      if (state.phase.isFocus) {
        title = '🍅 ¡Enfoque terminado!';
        final nextIsLong =
            state.cycleInSet + 1 >= state.prefs.sessionsBeforeLongBreak;
        body = nextIsLong
            ? '¡Tanda completa! Toca un descanso largo de ${state.prefs.longBreakDuration} min.'
            : 'Bien hecho. Descansa ${state.prefs.breakDuration} min antes del siguiente.';
      } else {
        title = '🍀 ¡Descanso terminado!';
        body = state.focusedTaskTitle == null
            ? 'Se acabó el descanso. ¡Volvamos a enfocarnos!'
            : 'Se acabó el descanso. Toca seguir con «${state.focusedTaskTitle}».';
      }

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          AlarmService.pomodoroChannelId,
          'Temporizador Pomodoro',
          channelDescription:
              'Aviso de finalización de fase de enfoque o descanso',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: AlarmService.notificationIcon,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await AlarmService.zonedScheduleWithFallback(
        id: _notificationId,
        title: title,
        body: body,
        when: when,
        details: details,
        payload: 'pomodoro:complete',
      );
    } catch (e) {
      debugPrint('Error programando notificación Pomodoro: $e');
    }
  }

  Future<void> _cancelNotification() async {
    if (kIsWeb) return;
    try {
      await _notificationsPlugin.cancel(_notificationId);
    } catch (e) {
      debugPrint('Error cancelando notificación Pomodoro: $e');
    }
  }
}

final pomodoroProvider =
    NotifierProvider<PomodoroNotifier, PomodoroState>(PomodoroNotifier.new);
