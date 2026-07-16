import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:alarm/alarm.dart';
import 'core/theme/bento_theme.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/appearance_provider.dart';
import 'core/providers/alarms_provider.dart';
import 'core/providers/habits_provider.dart';
import 'core/services/alarm_service.dart';
import 'core/services/lock_task_service.dart';
import 'core/services/note_reminder_service.dart';
import 'core/services/habit_reminder_service.dart';
import 'features/alarm/alarm_dismiss_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/update/update_checker.dart';

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

class _SistemDailyAppState extends ConsumerState<SistemDailyApp>
    with WidgetsBindingObserver {
  bool _initializing = true;
  String? _pendingAlarmId;
  String? _activeDismissAlarmId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Con el tema en "sistema", el brillo del SO es una entrada más del color.
  /// MaterialApp lo resuelve solo, pero BentoTheme.darkMode es un flag propio:
  /// sin este aviso la app se quedaría con la paleta del brillo anterior.
  @override
  void didChangePlatformBrightness() {
    if (ref.read(appearanceProvider).mode == ThemeMode.system) {
      setState(() {});
    }
  }

  void _handleNotificationTap(NotificationResponse response) {
    final alarmId = response.payload;
    if (alarmId == null) return;

    // La notificación de prueba del diagnóstico no abre nada.
    if (alarmId.startsWith('test:')) return;

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
    final settings = ref.read(settingsProvider);

    // Inicializar Supabase primero para que esté listo antes de cualquier
    // lectura de providers que dependan de él (p.ej. alarmsProvider más abajo)
    // y para que el DashboardScreen pueda empezar a cargar datos lo antes posible.
    try {
      await Supabase.initialize(
        url: settings.supabaseUrl,
        anonKey: settings.supabaseAnonKey,
        debug: false,
      );
    } catch (e) {
      // Ya inicializado o error de red; se reintenta implícitamente en cada
      // llamada a Supabase.instance dentro de los providers.
    }

    // Inicializar notificaciones y alarmas
    try {
      await AlarmService.initialize(onNotificationTap: _handleNotificationTap);

      // Verificar si hay alguna alarma sonando actualmente al iniciar
      final activeAlarms = await Alarm.getAlarms();
      int? ringingAlarmId;
      final ringingFlags = await Future.wait(
        activeAlarms.map((s) => Alarm.isRinging(s.id)),
      );
      for (int i = 0; i < activeAlarms.length; i++) {
        if (ringingFlags[i]) {
          ringingAlarmId = activeAlarms[i].id;
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
            !alarmId.startsWith('test:') &&
            !alarmId.startsWith(NoteReminderService.payloadPrefix) &&
            !alarmId.startsWith(HabitReminderService.payloadPrefix)) {
          _pendingAlarmId = alarmId;
        }
      }

      // El manifiesto declara showWhenLocked/turnScreenOn para que el
      // full-screen intent de la alarma se pinte sobre el bloqueo en arranque
      // en frío. Si no hay ninguna alarma sonando, lo revertimos: la app no
      // debería quedar accesible desde la pantalla de bloqueo.
      if (_pendingAlarmId == null) {
        await LockTaskService.showOverLockscreen(false);
      }
    } catch (e) {
      // No bloquear inicio si falla la inicialización
      debugPrint('main: inicialización de alarmas falló: $e');
    }

    setState(() {
      _initializing = false;
    });

    // Si el permiso de notificaciones quedó denegado (Android deja de mostrar
    // el diálogo tras denegarlo), avisar y ofrecer abrir los ajustes.
    _warnIfNotificationsDisabled();

    // Buscar actualizaciones en segundo plano (solo si hay sesión activa).
    // Silencioso: solo muestra diálogo si hay una versión nueva.
    if (Supabase.instance.client.auth.currentSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = navigatorKey.currentContext;
        if (context != null) UpdateChecker.check(context, silent: true);
      });
    }

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

  Future<void> _warnIfNotificationsDisabled() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final enabled = await AlarmService.areNotificationsEnabled();
    if (enabled) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Notificaciones desactivadas'),
          content: const Text(
            'Sin este permiso las alarmas no pueden sonar ni abrir la pantalla '
            'para tomar la foto. Actívalo en los ajustes del sistema.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Ahora no'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                LockTaskService.openNotificationSettings();
              },
              child: const Text('Abrir ajustes'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Sincronizar la fuente de verdad de los getters de color ANTES de
    // construir cualquier widget que los lea: primero la apariencia elegida
    // (paleta + material), luego el modo ya resuelto.
    final appearance = ref.watch(appearanceProvider);
    BentoTheme.applyAppearance(appearance.resolved, appearance.material);

    final themeMode = appearance.mode;
    // El brillo se lee del dispatcher y no de MediaQuery: este build está por
    // encima de MaterialApp, así que aquí todavía no hay MediaQuery que leer.
    final isDark = appearance
        .isDarkFor(View.of(context).platformDispatcher.platformBrightness);
    BentoTheme.darkMode.value = isDark;

    if (_initializing) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: BentoTheme.lightTheme,
        darkTheme: BentoTheme.darkTheme,
        themeMode: themeMode,
        navigatorKey: navigatorKey,
        home: BentoBackground(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.widgets_outlined,
                    size: 64, color: BentoTheme.cream),
                const SizedBox(height: 16),
                CircularProgressIndicator(color: BentoTheme.cream),
              ],
            ),
          ),
        ),
      );
    }

    final session = Supabase.instance.client.auth.currentSession;
    final homeWidget = session != null ? const DashboardScreen() : const AuthScreen();

    return MaterialApp(
      title: 'SistemDaily',
      debugShowCheckedModeBanner: false,
      theme: BentoTheme.lightTheme,
      darkTheme: BentoTheme.darkTheme,
      themeMode: themeMode,
      navigatorKey: navigatorKey,
      // La Key atada a la apariencia remonta el árbol al cambiar de modo, de
      // paleta o de material: muchos widgets son const y leen colores
      // estáticos de BentoTheme, así que sin remount se quedarían pintados con
      // la paleta anterior. `isDark` entra aparte porque en modo sistema la
      // firma no cambia aunque el SO sí lo haga.
      home: KeyedSubtree(
        key: ValueKey(Object.hash(appearance.signature, isDark)),
        child: homeWidget,
      ),
    );
  }
}

