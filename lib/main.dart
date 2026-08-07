import 'dart:async';

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
import 'core/providers/connectivity_provider.dart';
import 'core/providers/habits_provider.dart';
import 'core/providers/night_planning_provider.dart';
import 'core/providers/sleep_provider.dart';
import 'core/services/alarm_service.dart';
import 'core/services/camera_service.dart';
import 'core/services/lock_task_service.dart';
import 'core/services/note_reminder_service.dart';
import 'core/services/habit_reminder_service.dart';
import 'core/services/task_reminder_service.dart';
import 'core/services/night_planning_service.dart';
import 'core/models/alarm_model.dart';
import 'core/services/sleep_service.dart';
import 'core/services/wake_check_service.dart';
import 'core/services/quick_capture_sync.dart';
import 'core/services/weekly_review_service.dart';
import 'features/analytics/weekly_review_screen.dart';
import 'features/agenda/night_planning/night_planning_screen.dart';
import 'features/alarm/alarm_dismiss_screen.dart';
import 'features/alarm/sleep/sleep_dashboard_screen.dart';
import 'features/alarm/sleep/wake_check_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/quick_capture/quick_capture_app.dart';
import 'features/auth/auth_screen.dart';
import 'features/update/update_checker.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  // Enumerar las cámaras tarda cientos de ms en Android; hacerlo aquí en
  // segundo plano hace que la pantalla de captura abra sin esa espera.
  CameraService.prewarm();

  runApp(
    const ProviderScope(
      child: SistemDailyApp(),
    ),
  );
}

/// Entry point del modal de captura rápida (tile del desplegable, widget de
/// escritorio y atajos del icono).
///
/// Tiene que estar declarado en esta librería porque el engine busca el
/// entrypoint por nombre dentro de la librería principal de la app; en otro
/// fichero, `QuickCaptureActivity` no lo encontraría. La implementación vive en
/// `features/quick_capture/` — aquí solo está la puerta.
@pragma('vm:entry-point')
void quickCaptureMain() => runQuickCapture();

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

  /// La comprobación "¿sigues despierto?" sonaba antes de que hubiera
  /// navigator; se abre en cuanto lo haya.
  bool _pendingWakeCheck = false;
  bool _wakeCheckOpen = false;

  /// Id nativo de la comprobación que sonaba antes de haber navigator.
  int? _pendingWakeCheckId;

  /// ¿Este id nativo es el de una verificación de vigilia?
  ///
  /// Se deriva de las alarmas y no del estado de sueño a propósito: en arranque
  /// en frío el provider aún está leyendo la caché, así que consultarle daría
  /// `null` y la comprobación se quedaría sonando sin pantalla que la pare.
  bool _isWakeCheckId(int nativeId, List<AlarmModel> alarms) =>
      alarms.any((a) => WakeCheckService.nativeIdFor(a.id) == nativeId);

  void _openWakeCheck(int nativeId) {
    if (_wakeCheckOpen) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _pendingWakeCheck = true;
      _pendingWakeCheckId = nativeId;
      return;
    }
    _wakeCheckOpen = true;
    _pendingWakeCheck = false;
    navigator
        .push(MaterialPageRoute(
            builder: (_) => WakeCheckScreen(nativeId: nativeId)))
        .then((_) => _wakeCheckOpen = false);
  }

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Volver a primer plano es justo cuando puede haber capturas nuevas: el
    // modal del desplegable se abre y se cierra sin pasar por esta app.
    if (state == AppLifecycleState.resumed && !_initializing) {
      _drainQuickCaptures();
      // Volver a primer plano también suele significar que hay red otra vez
      // (el móvil sale del bolsillo, el wifi engancha): buen momento para
      // subir las escrituras que se quedaron pendientes.
      ref.read(syncStatusProvider.notifier).sync();
    }
  }

  /// Sube a Supabase lo que el modal de captura rápida dejó en la cola local.
  ///
  /// Se avisa solo cuando algo se guardó de verdad: sin confirmación, anotar
  /// desde el desplegable sería un acto de fe (el modal se cierra al instante y
  /// la app ni estaba abierta).
  Future<void> _drainQuickCaptures() async {
    try {
      final result = await QuickCaptureSync.drain(ref);
      if (result.saved == 0 || !mounted) return;

      final context = navigatorKey.currentContext;
      if (context == null) return;

      final n = result.saved;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            n == 1 ? 'Captura rápida guardada' : '$n capturas rápidas guardadas',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // La cola no se vacía si falla, así que se reintenta al siguiente resume.
      debugPrint('main: no pude drenar la captura rápida: $e');
    }
  }

  void _handleNotificationTap(NotificationResponse response) {
    final alarmId = response.payload;
    if (alarmId == null) return;

    // La notificación de prueba del diagnóstico no abre nada.
    if (alarmId.startsWith('test:')) return;

    // El aviso nocturno abre el ritual directamente: si obligara a pasar por
    // la Agenda y buscar el botón, la mitad de las noches no se haría.
    if (alarmId == NightPlanningService.payload) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const NightPlanningScreen()),
      );
      return;
    }

    // El aviso semanal abre el ritual de revisión por la misma razón: si
    // obligara a buscar la pantalla, se haría la primera semana y ya.
    if (alarmId == WeeklyReviewService.payload) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const WeeklyReviewScreen()),
      );
      return;
    }

    // La rutina de sueño: tanto el aviso como su acción y las insistencias
    // marcan el inicio del ciclo. `confirmBedtime` es idempotente, así que da
    // igual por cuál de las tres llegue el usuario.
    if (alarmId.startsWith(SleepService.payloadPrefix)) {
      if (alarmId != SleepService.windDownPayload) {
        ref.read(sleepProvider.notifier).confirmBedtime();
      }
      // Desde el botón de la notificación no se abre nada: la gracia es poder
      // confirmar sin volver a encender la pantalla entera.
      if (response.actionId == null) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const SleepDashboardScreen()),
        );
      }
      return;
    }

    // Los recordatorios de notas/hábitos/agenda usan un prefijo propio
    if (alarmId.startsWith(NoteReminderService.payloadPrefix) ||
        alarmId.startsWith(HabitReminderService.payloadPrefix) ||
        alarmId.startsWith(TaskReminderService.payloadPrefix)) {
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
          // La verificación de vigilia se comprueba primero: su id nativo no
          // corresponde a ninguna alarma del usuario, así que la búsqueda de
          // abajo no la encontraría y se quedaría sonando sin pantalla.
          if (_isWakeCheckId(ringingAlarmId, alarms)) {
            _pendingWakeCheck = true;
            _pendingWakeCheckId = ringingAlarmId;
          } else {
            final alarm = alarms.where((a) => a.id.hashCode.abs() % 100000 == ringingAlarmId).firstOrNull;
            if (alarm != null) {
              _pendingAlarmId = alarm.id;
              unawaited(ref.read(sleepProvider.notifier).registerRing(alarm));
            }
          }
        } catch (_) {}
      }

      // Escuchar cuando una alarma comience a sonar en primer plano o segundo plano
      Alarm.ringing.listen((alarmSet) async {
        try {
          final alarms = await ref.read(alarmsProvider.future);
          for (final alarmSettings in alarmSet.alarms) {
            if (_isWakeCheckId(alarmSettings.id, alarms)) {
              _openWakeCheck(alarmSettings.id);
              continue;
            }
            final alarm = alarms.where((a) => a.id.hashCode.abs() % 100000 == alarmSettings.id).firstOrNull;
            if (alarm != null) {
              // Antes del guard de pantalla: aunque el dismiss ya esté abierto,
              // la hora del primer timbrazo es lo que luego mide el snooze.
              unawaited(ref.read(sleepProvider.notifier).registerRing(alarm));
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
            alarmId != NightPlanningService.payload &&
            alarmId != WeeklyReviewService.payload &&
            !alarmId.startsWith(NoteReminderService.payloadPrefix) &&
            !alarmId.startsWith(HabitReminderService.payloadPrefix) &&
            !alarmId.startsWith(TaskReminderService.payloadPrefix)) {
          _pendingAlarmId = alarmId;
        }
        // Arranque en frío desde el aviso nocturno: se abre el ritual una vez
        // montado el árbol de navegación.
        if (alarmId == NightPlanningService.payload) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            navigatorKey.currentState?.push(
              MaterialPageRoute(builder: (_) => const NightPlanningScreen()),
            );
          });
        }
        if (alarmId == WeeklyReviewService.payload) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            navigatorKey.currentState?.push(
              MaterialPageRoute(builder: (_) => const WeeklyReviewScreen()),
            );
          });
        }
      }

      // Leer el provider lo construye, y su `build` reprograma el aviso
      // nocturno. Hace falta en cada arranque: una notificación diaria se
      // pierde si el sistema mata la app o se reinicia el teléfono.
      ref.read(nightPlanningProvider);

      // Lo mismo con el aviso semanal de revisión, por el mismo motivo.
      unawaited(WeeklyReviewService.schedule());

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

    // Todo lo anotado desde el desplegable, el widget o los atajos del icono
    // está esperando en una cola local: este es el momento de subirlo.
    _drainQuickCaptures();

    // Y lo mismo con las escrituras que quedaron sin confirmar de la sesión
    // anterior. Leer el provider aquí, además, arranca la escucha de
    // conectividad que dispara el resto de drenajes.
    ref.read(syncStatusProvider.notifier).sync();

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

    // Lo mismo para la comprobación de vigilia que sonó antes de que la app
    // tuviera navigator.
    if (_pendingWakeCheck && _pendingWakeCheckId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openWakeCheck(_pendingWakeCheckId!),
      );
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

