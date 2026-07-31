import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../core/services/alarm_service.dart';

class PomodoroState {
  final bool isActive;
  final int workDuration; // en minutos
  final int breakDuration; // en minutos
  final int longBreakDuration; // en minutos
  final int cycleCount; // ciclos completados de foco
  final int timeLeft; // en segundos
  final bool isFocusPhase;
  final bool isLongBreak;
  final int rightPanelMode; // 0: frase, 1: carrusel, 2: tareas, 3: respiración
  final DateTime? targetEndTime;
  final int carouselIndex;

  const PomodoroState({
    required this.isActive,
    required this.workDuration,
    required this.breakDuration,
    required this.longBreakDuration,
    required this.cycleCount,
    required this.timeLeft,
    required this.isFocusPhase,
    required this.isLongBreak,
    required this.rightPanelMode,
    this.targetEndTime,
    required this.carouselIndex,
  });

  PomodoroState copyWith({
    bool? isActive,
    int? workDuration,
    int? breakDuration,
    int? longBreakDuration,
    int? cycleCount,
    int? timeLeft,
    bool? isFocusPhase,
    bool? isLongBreak,
    int? rightPanelMode,
    DateTime? targetEndTime,
    bool clearTargetEndTime = false,
    int? carouselIndex,
  }) {
    return PomodoroState(
      isActive: isActive ?? this.isActive,
      workDuration: workDuration ?? this.workDuration,
      breakDuration: breakDuration ?? this.breakDuration,
      longBreakDuration: longBreakDuration ?? this.longBreakDuration,
      cycleCount: cycleCount ?? this.cycleCount,
      timeLeft: timeLeft ?? this.timeLeft,
      isFocusPhase: isFocusPhase ?? this.isFocusPhase,
      isLongBreak: isLongBreak ?? this.isLongBreak,
      rightPanelMode: rightPanelMode ?? this.rightPanelMode,
      targetEndTime: clearTargetEndTime ? null : (targetEndTime ?? this.targetEndTime),
      carouselIndex: carouselIndex ?? this.carouselIndex,
    );
  }
}

class PomodoroNotifier extends Notifier<PomodoroState> {
  Timer? _timer;
  Timer? _carouselTimer;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  PomodoroState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _carouselTimer?.cancel();
    });

    return const PomodoroState(
      isActive: false,
      workDuration: 25,
      breakDuration: 5,
      longBreakDuration: 15,
      cycleCount: 0,
      timeLeft: 25 * 60,
      isFocusPhase: true,
      isLongBreak: false,
      rightPanelMode: 0,
      carouselIndex: 0,
    );
  }

  void configure({
    required int workDuration,
    required int breakDuration,
    required int longBreakDuration,
    required int rightPanelMode,
  }) {
    stop();
    state = state.copyWith(
      workDuration: workDuration,
      breakDuration: breakDuration,
      longBreakDuration: longBreakDuration,
      rightPanelMode: rightPanelMode,
      timeLeft: workDuration * 60,
      isFocusPhase: true,
      isLongBreak: false,
      cycleCount: 0,
    );
  }

  void setRightPanelMode(int mode) {
    state = state.copyWith(rightPanelMode: mode);
    if (mode == 1) {
      _startCarouselTimer();
    } else {
      _carouselTimer?.cancel();
    }
  }

  void start() {
    if (state.isActive) return;

    final targetEnd = DateTime.now().add(Duration(seconds: state.timeLeft));
    state = state.copyWith(
      isActive: true,
      targetEndTime: targetEnd,
    );

    _scheduleNotification(targetEnd);
    _startTimer();
    
    if (state.rightPanelMode == 1) {
      _startCarouselTimer();
    }
  }

  void pause() {
    if (!state.isActive) return;
    _timer?.cancel();
    _cancelNotification();
    state = state.copyWith(
      isActive: false,
      clearTargetEndTime: true,
    );
  }

  void stop() {
    _timer?.cancel();
    _cancelNotification();
    _carouselTimer?.cancel();
    int resetTime = state.workDuration * 60;
    if (!state.isFocusPhase) {
      resetTime = state.isLongBreak ? state.longBreakDuration * 60 : state.breakDuration * 60;
    }
    state = state.copyWith(
      isActive: false,
      timeLeft: resetTime,
      clearTargetEndTime: true,
    );
  }

  void skip() {
    _timer?.cancel();
    _cancelNotification();
    
    _transitionPhase();
  }

  void syncWithBackground() {
    if (!state.isActive || state.targetEndTime == null) return;
    
    final diff = state.targetEndTime!.difference(DateTime.now()).inSeconds;
    if (diff <= 0) {
      _timer?.cancel();
      _onPhaseCompleted();
    } else {
      state = state.copyWith(timeLeft: diff);
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.targetEndTime == null) {
        timer.cancel();
        return;
      }
      
      final diff = state.targetEndTime!.difference(DateTime.now()).inSeconds;
      if (diff <= 0) {
        timer.cancel();
        _onPhaseCompleted();
      } else {
        state = state.copyWith(timeLeft: diff);
      }
    });
  }

  void _startCarouselTimer() {
    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      state = state.copyWith(carouselIndex: (state.carouselIndex + 1) % 15);
    });
  }

  void _onPhaseCompleted() {
    _cancelNotification();
    _transitionPhase();
  }

  void _transitionPhase() {
    bool nextIsFocus = !state.isFocusPhase;
    int nextCycleCount = state.cycleCount;
    bool nextIsLongBreak = false;
    int nextTime = 0;

    if (state.isFocusPhase) {
      // Completamos una sesión de foco
      nextCycleCount += 1;
      nextIsFocus = false;

      // Cada 4 ciclos de foco completados, toca descanso largo
      if (nextCycleCount > 0 && nextCycleCount % 4 == 0) {
        nextIsLongBreak = true;
        nextTime = state.longBreakDuration * 60;
      } else {
        nextIsLongBreak = false;
        nextTime = state.breakDuration * 60;
      }
    } else {
      // Completamos un descanso (corto o largo), volvemos a foco
      nextIsFocus = true;
      nextIsLongBreak = false;
      nextTime = state.workDuration * 60;
    }

    state = state.copyWith(
      isActive: false,
      isFocusPhase: nextIsFocus,
      isLongBreak: nextIsLongBreak,
      cycleCount: nextCycleCount,
      timeLeft: nextTime,
      clearTargetEndTime: true,
    );

    // Auto-arrancar la siguiente fase automáticamente
    start();
  }

  Future<void> _scheduleNotification(DateTime targetEnd) async {
    if (kIsWeb) return;
    try {
      final when = tz.TZDateTime.from(targetEnd, tz.local);
      String title = '';
      String body = '';

      if (state.isFocusPhase) {
        title = '🍅 ¡Enfoque Terminado!';
        final nextIsLong = (state.cycleCount + 1) % 4 == 0;
        body = nextIsLong 
            ? '¡Ciclo completo! Es hora de tu descanso largo de ${state.longBreakDuration} min.' 
            : 'Foco completado. Tómate un descanso corto de ${state.breakDuration} min.';
      } else {
        title = '🍀 ¡Descanso Terminado!';
        body = 'Se acabó el descanso. ¡Volvamos a enfocarnos!';
      }

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          AlarmService.pomodoroChannelId,
          'Temporizador Pomodoro',
          channelDescription: 'Aviso de finalización de fase de enfoque o descanso',
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
        id: 500000,
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
      await _notificationsPlugin.cancel(500000);
    } catch (e) {
      debugPrint('Error cancelando notificación Pomodoro: $e');
    }
  }
}

final pomodoroProvider = NotifierProvider<PomodoroNotifier, PomodoroState>(() {
  return PomodoroNotifier();
});
