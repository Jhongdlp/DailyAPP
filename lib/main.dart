import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:alarm/alarm.dart';
import 'core/theme/bento_theme.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/alarms_provider.dart';
import 'core/providers/habits_provider.dart';
import 'core/services/alarm_service.dart';
import 'core/services/note_reminder_service.dart';
import 'core/services/habit_reminder_service.dart';
import 'features/alarm/alarm_dismiss_screen.dart';
import 'features/setup/setup_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/auth/auth_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');

  runApp(
    const ProviderScope(
      child: SistemDailyApp(),
    ),
  );
}

class SistemDailyApp extends ConsumerStatefulWidget {
  const SistemDailyApp({super.key});

  @override
  ConsumerState<SistemDailyApp> createState() => _SistemDailyAppState();
}

class _SistemDailyAppState extends ConsumerState<SistemDailyApp> {
  bool _initializing = true;
  bool _supabaseLoaded = false;
  String? _pendingAlarmId;
  String? _activeDismissAlarmId;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  void _handleNotificationTap(NotificationResponse response) {
    final alarmId = response.payload;
    if (alarmId == null) return;

    // Los recordatorios de notas/hábitos usan un prefijo propio
    if (alarmId.startsWith(NoteReminderService.payloadPrefix) ||
        alarmId.startsWith(HabitReminderService.payloadPrefix)) {
      if (alarmId.startsWith(HabitReminderService.payloadPrefix)) {
        final habitId = alarmId.substring(HabitReminderService.payloadPrefix.length);
        final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

        if (response.actionId == 'action_complete_habit') {
          ref.read(habitsProvider.notifier).toggleHabit(habitId, today);
        } else if (response.actionId == 'action_increment_progress') {
          final habits = ref.read(habitsProvider);
          final habit = habits.where((h) => h.id == habitId).firstOrNull;
          double increment = 1.0;
          if (habit != null) {
            final unit = habit.goalUnit?.toLowerCase() ?? '';
            if (unit == 'l') {
              increment = 0.25;
            } else if (unit == 'ml') {
              increment = 250.0;
            } else if (unit == 'pasos' || unit == 'steps') {
              increment = 1000.0;
            } else if (unit == 'min' || unit == 'minutos') {
              increment = 5.0;
            }
          }
          ref.read(habitsProvider.notifier).updateHabitProgress(habitId, today, increment);
        }
      }
      return;
    }

    if (navigatorKey.currentState != null) {
      if (_activeDismissAlarmId == alarmId) return;
      _activeDismissAlarmId = alarmId;
      navigatorKey.currentState!.push(MaterialPageRoute(
        builder: (_) => AlarmDismissScreen(alarmId: alarmId),
      )).then((_) {
        _activeDismissAlarmId = null;
      });
    } else {
      // App still initializing — open after build
      setState(() => _pendingAlarmId = alarmId);
    }
  }

  Future<void> _initializeApp() async {
    // Esperar a que settingsProvider cargue SharedPreferences
    await Future.delayed(const Duration(milliseconds: 500));

    final settings = ref.read(settingsProvider);

    // Inicializar notificaciones y alarmas
    try {
      await AlarmService.initialize(onNotificationTap: _handleNotificationTap);

      // Verificar si hay alguna alarma sonando actualmente al iniciar
      final activeAlarms = await Alarm.getAlarms();
      int? ringingAlarmId;
      for (final s in activeAlarms) {
        if (await Alarm.isRinging(s.id)) {
          ringingAlarmId = s.id;
          break;
        }
      }
      if (ringingAlarmId != null) {
        try {
          final alarms = await ref.read(alarmsProvider.future);
          final alarm = alarms.where((a) => a.id.hashCode.abs() % 100000 == ringingAlarmId).firstOrNull;
          if (alarm != null) {
            _pendingAlarmId = alarm.id;
          }
        } catch (_) {}
      }

      // Escuchar cuando una alarma comience a sonar en primer plano o segundo plano
      Alarm.ringing.listen((alarmSet) async {
        try {
          final alarms = await ref.read(alarmsProvider.future);
          for (final alarmSettings in alarmSet.alarms) {
            final alarm = alarms.where((a) => a.id.hashCode.abs() % 100000 == alarmSettings.id).firstOrNull;
            if (alarm != null) {
              if (_activeDismissAlarmId == alarm.id) return;
              if (navigatorKey.currentState != null) {
                _activeDismissAlarmId = alarm.id;
                navigatorKey.currentState!.push(MaterialPageRoute(
                  builder: (_) => AlarmDismissScreen(alarmId: alarm.id),
                )).then((_) {
                  _activeDismissAlarmId = null;
                });
              } else {
                _pendingAlarmId = alarm.id;
              }
            }
          }
        } catch (_) {}
      });

      // Verificar si la app fue abierta desde una notificación de recordatorio
      final launchDetails = await AlarmService.getLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        final alarmId = launchDetails?.notificationResponse?.payload;
        if (alarmId != null &&
            !alarmId.startsWith(NoteReminderService.payloadPrefix) &&
            !alarmId.startsWith(HabitReminderService.payloadPrefix)) {
          _pendingAlarmId = alarmId;
        }
      }
    } catch (_) {
      // No bloquear inicio si falla la inicialización
    }

    if (settings.isSupabaseConfigured) {
      try {
        await Supabase.initialize(
          url: settings.supabaseUrl,
          anonKey: settings.supabaseAnonKey,
          debug: false,
        );
        setState(() {
          _supabaseLoaded = true;
        });
      } catch (e) {
        setState(() {
          _supabaseLoaded = true;
        });
      }
    }

    setState(() {
      _initializing = false;
    });

    // Navegar a AlarmDismissScreen si había una notificación pendiente
    if (_pendingAlarmId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_activeDismissAlarmId == _pendingAlarmId) return;
        _activeDismissAlarmId = _pendingAlarmId;
        navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => AlarmDismissScreen(alarmId: _pendingAlarmId!),
        )).then((_) {
          _activeDismissAlarmId = null;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: BentoTheme.lightTheme,
        navigatorKey: navigatorKey,
        home: const BentoBackground(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.widgets_outlined,
                    size: 64, color: BentoTheme.primaryDark),
                SizedBox(height: 16),
                CircularProgressIndicator(color: BentoTheme.primaryDark),
              ],
            ),
          ),
        ),
      );
    }

    final settings = ref.watch(settingsProvider);
    final hasConfig = settings.isSupabaseConfigured || _supabaseLoaded;

    Widget homeWidget;
    if (!hasConfig) {
      homeWidget = const SetupScreen();
    } else {
      final session = Supabase.instance.client.auth.currentSession;
      homeWidget = session != null ? const DashboardScreen() : const AuthScreen();
    }

    return MaterialApp(
      title: 'SistemDaily',
      debugShowCheckedModeBanner: false,
      theme: BentoTheme.lightTheme,
      navigatorKey: navigatorKey,
      home: homeWidget,
    );
  }
}

