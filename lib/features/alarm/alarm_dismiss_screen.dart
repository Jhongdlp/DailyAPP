import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:alarm/alarm.dart';
import '../../core/models/alarm_model.dart';
import '../../core/network/local_ai_client.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/rpg_provider.dart';
import '../../core/providers/sleep_provider.dart';
import '../../core/models/achievement_catalog.dart';
import '../../core/widgets/rpg_celebration.dart';
import '../../core/services/alarm_service.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/lock_task_service.dart';
import '../../core/providers/appearance_provider.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/widgets/editorial_kit.dart';
import 'challenge/challenge_screen.dart';
import 'sleep/sleep_check_in_screen.dart';
import 'widgets/camera_capture_screen.dart';

class AlarmDismissScreen extends ConsumerStatefulWidget {
  final String alarmId;

  const AlarmDismissScreen({super.key, required this.alarmId});

  @override
  ConsumerState<AlarmDismissScreen> createState() => _AlarmDismissScreenState();
}

class _AlarmDismissScreenState extends ConsumerState<AlarmDismissScreen> {
  /// Cuánto puede estar la alarma callada mientras enfocas o la IA analiza,
  /// antes de volver a sonar sola. Pausar no puede acabar siendo un apagado
  /// encubierto: sin este tope, abrir la cámara y dejar el móvil en la mesilla
  /// sería la forma más cómoda de saltarse la alarma.
  static const _maxSilence = Duration(minutes: 3);

  /// Tope de espera del modelo de visión por intento. Antes no había ninguno:
  /// si el servidor se quedaba pensando (o la wifi seguía dormida), la pantalla
  /// se quedaba con el "Verificando..." para siempre.
  static const _visionTimeout = Duration(seconds: 45);

  AlarmModel? _alarm;
  bool _loading = true;
  bool _verifying = false;
  PhotoVerdict? _verdict;
  String? _aiError;
  File? _photo;
  int _attempts = 0;
  bool _cameraDenied = false;

  /// `null` mientras se comprueba; `false` = el servidor no contesta y la
  /// única salida razonable es el reto mental.
  bool? _aiReachable;

  bool _silenced = false;
  Timer? _resumeTimer;

  int _elapsed = 0;
  Timer? _elapsedTimer;

  /// Invalida verificaciones en vuelo cuando se dispara otra foto.
  int _verifyToken = 0;

  LocalAIClient _client() {
    final settings = ref.read(settingsProvider);
    return LocalAIClient(
      baseUrl: settings.localAiUrl,
      visionModelName: settings.visionModel,
    );
  }

  @override
  void initState() {
    super.initState();
    // Pinta la alarma encima del bloqueo para poder fotografiar sin desbloquear.
    LockTaskService.showOverLockscreen(true);
    _loadAlarm();
    _prepareCameraThenLock();
    _warmUpAi();
  }

  /// Manda cargar el modelo de visión en cuanto se abre la pantalla.
  ///
  /// Es el mayor ahorro de tiempo de todo el flujo: Ollama descarga el modelo
  /// de memoria a los pocos minutos de inactividad, así que con una alarma
  /// diaria la primera foto pagaba SIEMPRE la carga entera de los 8B de pesos.
  /// Ahora esa carga ocurre mientras te levantas y caminas hasta el objeto.
  Future<void> _warmUpAi() async {
    final ok = await _client().warmUpVision();
    if (mounted) setState(() => _aiReachable = ok);
  }

  /// El permiso de cámara debe pedirse ANTES de fijar la pantalla: Android no
  /// muestra diálogos de permisos en modo lock task, así que si fijábamos
  /// primero (como hacía el código anterior) el diálogo nunca aparecía y la
  /// cámara se quedaba muerta con la pantalla bloqueada encima.
  Future<void> _prepareCameraThenLock() async {
    final granted = await LockTaskService.requestCameraPermission();
    if (!mounted) return;
    if (!granted) {
      setState(() => _cameraDenied = true);
      return; // Sin cámara no fijamos: dejaríamos al usuario atrapado.
    }
    // Fija la pantalla: desactiva Home y Recientes mientras la alarma suena.
    await LockTaskService.enable();
  }

  @override
  void dispose() {
    _resumeTimer?.cancel();
    _elapsedTimer?.cancel();
    // Si el widget muere con la alarma en pausa (sin haberla resuelto), se
    // devuelve el timbre: lo contrario dejaría la alarma apagada de tapadillo.
    final alarm = _alarm;
    if (_silenced && alarm != null) {
      unawaited(AlarmService.ringAgain(alarm));
    }
    // Salvaguarda: libera la pantalla si el widget se destruye por cualquier vía.
    LockTaskService.disable();
    LockTaskService.showOverLockscreen(false);
    super.dispose();
  }

  Future<void> _loadAlarm() async {
    try {
      final raw = await CacheService.read('alarms');
      AlarmModel? found;
      if (raw is List) {
        for (final e in raw) {
          final map = Map<String, dynamic>.from(e as Map);
          if (map['id'] == widget.alarmId) {
            found = AlarmModel.fromJson(map);
            break;
          }
        }
      }
      if (mounted) {
        setState(() {
          _alarm = found;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Pausa del timbre
  // ---------------------------------------------------------------------------

  /// Calla la alarma mientras se fotografía y se verifica.
  ///
  /// Con el timbre a volumen máximo pegado a la oreja acabas disparando la foto
  /// de cualquier manera, y una foto movida es justo lo que el modelo no sabe
  /// interpretar: la prisa por callarlo era parte del problema de validación.
  Future<void> _silence() async {
    final alarm = _alarm;
    if (alarm == null || _silenced) return;
    setState(() => _silenced = true);
    await AlarmService.silence(alarm.id);
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_maxSilence, () => unawaited(_resumeRinging()));
  }

  /// Devuelve el timbre. Contrapartida obligatoria de [_silence].
  Future<void> _resumeRinging() async {
    _resumeTimer?.cancel();
    _resumeTimer = null;
    final alarm = _alarm;
    if (alarm == null || !_silenced) return;
    if (mounted) {
      setState(() => _silenced = false);
    } else {
      _silenced = false;
    }
    await AlarmService.ringAgain(alarm);
  }

  void _startElapsed() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
  }

  void _stopElapsed() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Camino 1: foto validada por la IA
  // ---------------------------------------------------------------------------

  Future<void> _takePhoto() async {
    if (_cameraDenied) {
      await _prepareCameraThenLock();
      if (!mounted || _cameraDenied) return;
    }

    await _silence();
    if (!mounted) return;

    final picked = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CameraCaptureScreen(targetObject: _alarm!.targetObject),
      ),
    );
    if (!mounted) return;
    if (picked == null) {
      // Cancelaste la cámara: la alarma vuelve a sonar de inmediato.
      await _resumeRinging();
      return;
    }

    setState(() {
      _photo = picked;
      _verifying = true;
      _verdict = null;
      _aiError = null;
      _attempts++;
      _elapsed = 0;
    });
    _startElapsed();

    final token = ++_verifyToken;
    try {
      final bytes = await picked.readAsBytes();
      final verdict = await _client().verifyAlarmPhoto(
        base64Encode(bytes),
        _alarm!.targetObject,
        timeout: _visionTimeout,
      );
      if (!mounted || token != _verifyToken) return;
      _stopElapsed();
      setState(() {
        _verifying = false;
        _verdict = verdict;
        _aiReachable = true;
      });
      if (verdict == PhotoVerdict.yes) {
        await _completeDismissal();
      } else {
        await _resumeRinging();
      }
    } catch (e) {
      if (!mounted || token != _verifyToken) return;
      _stopElapsed();
      setState(() {
        _verifying = false;
        _aiError = e is AiUnavailableException
            ? e.message
            : 'No pude contactar con el servidor de IA.';
        _aiReachable = false;
      });
      await _resumeRinging();
    }
  }

  // ---------------------------------------------------------------------------
  // Camino 2: reto mental
  // ---------------------------------------------------------------------------

  /// Por qué se está ofreciendo el reto, para explicarlo dentro de la pantalla.
  String? get _challengeReason {
    if (_aiError != null) return 'La IA no respondió. Resuélvelo y apago la alarma.';
    if (_verdict == PhotoVerdict.unclear) {
      return 'La IA no fue concluyente con la foto. Resuelve esto en su lugar.';
    }
    if (_aiReachable == false) {
      return 'El servidor de IA no responde. Esta es tu salida.';
    }
    return null;
  }

  Future<void> _openChallenge() async {
    final solved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ChallengeScreen(reason: _challengeReason),
      ),
    );
    if (solved == true && mounted) {
      // Cuenta como intento: apagar por reto también es haberte levantado.
      if (_attempts == 0) _attempts = 1;
      await _completeDismissal();
    }
  }

  // ---------------------------------------------------------------------------
  // Final común
  // ---------------------------------------------------------------------------

  /// Apaga la alarma de verdad, registra la noche y sale. Lo comparten la foto
  /// validada y el reto resuelto: ambos demuestran lo mismo, que estás de pie.
  Future<void> _completeDismissal() async {
    final alarm = _alarm;
    if (alarm == null) return;

    // Antes que nada: matar el vigilante de la pausa, o la alarma volvería a
    // sonar dos minutos después de haberla apagado.
    _resumeTimer?.cancel();
    _resumeTimer = null;
    _silenced = false;
    _stopElapsed();
    _verifyToken++;

    if (mounted) setState(() => _verdict = PhotoVerdict.yes);

    await _logDismissal(validated: true);
    await Alarm.stop(AlarmService.nativeId(alarm.id));

    // Cierra la noche en el registro de sueño: el par lightsOut → wokeAt es
    // lo que da duración, eficiencia y minutos de snooze.
    // Pasar el alarmId arranca la verificación de vigilia: sin él, apagar
    // la alarma cerraría la mañana y volverse a la cama saldría gratis.
    final session = await ref.read(sleepProvider.notifier).registerWake(
          alarmId: alarm.id,
          dismissAttempts: _attempts,
        );

    // Otorgar recompensa RPG por levantarse a tiempo.
    // Madrugar (antes de las 8am) da bonus y cuenta para el logro Alondra.
    final early = DateTime.now().hour < 8;
    final result = ref.read(rpgProvider.notifier).gainXpAndGold(
      early ? 50 : 30,
      early ? 25 : 15,
      counterKeys: early
          ? const [RpgCounters.wakes, RpgCounters.earlyWakes]
          : const [RpgCounters.wakes],
    );
    if (mounted) {
      RpgCelebration.show(
        context,
        xp: result['xpGained'] as int,
        gold: result['goldGained'] as int,
        levelUp: result['levelUp'] as bool,
        newLevel: result['newLevel'] as int?,
      );
      AchievementToast.show(context, result['unlocked']);
    }

    await AlarmService.scheduleAlarm(alarm,
        from: DateTime.now().add(const Duration(minutes: 1)));
    await Future.delayed(const Duration(seconds: 2));
    // Solo aquí (alarma resuelta) liberamos la pantalla y salimos.
    await LockTaskService.disable();
    await LockTaskService.showOverLockscreen(false);

    // El check-in va DESPUÉS de soltar el modo pantalla fijada: si no,
    // quedaría atrapado en él y el usuario no podría salir.
    if (mounted && session?.timeInBed != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SleepCheckInScreen(nightKey: session!.nightKey),
        ),
      );
    }

    if (mounted) Navigator.pop(context);
  }

  /// Log histórico en Supabase. El registro que de verdad alimenta el panel de
  /// sueño es el local (`sleepProvider`); esto se conserva por si algún día
  /// las alarmas dejan de ser solo locales.
  Future<void> _logDismissal({required bool validated}) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      await Supabase.instance.client.from('alarm_logs').insert({
        'alarm_id': widget.alarmId,
        'user_id': user.id,
        'triggered_at': DateTime.now().toIso8601String(),
        'dismissed_at': DateTime.now().toIso8601String(),
        'validated': validated,
        'attempts': _attempts,
      });
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  //
  // Esta pantalla es la ÚNICA de la app con dos pieles dentro del mismo
  // archivo, y es deliberado. Encima hay ~380 líneas de lógica crítica —pausa
  // del timbre con su temporizador de vuelta, token de verificación, modo
  // pantalla fijada, cierre de la noche— donde un fallo significa que la
  // alarma no suena o no se puede apagar. Duplicar ese archivo para cambiar
  // tipografías garantizaba que las dos copias divergieran en la primera
  // corrección; aquí sólo se bifurca el `build`.
  //
  // Nota de diseño: el editorial de esta pantalla NO usa papel de fondo. A las
  // seis de la mañana, una lámina blanca a pantalla completa es un fogonazo.
  // Se queda el lienzo oscuro y el papel se reserva para el botón de la
  // cámara, que es lo único que hay que encontrar medio dormido.

  @override
  Widget build(BuildContext context) {
    if (ref.watch(designLanguageProvider).isEditorial) return _buildEditorial();
    if (_loading) {
      return Scaffold(
        backgroundColor: BentoTheme.darkBg,
        body: Center(child: CircularProgressIndicator(color: BentoTheme.cream)),
      );
    }

    final alarm = _alarm;
    if (alarm == null) {
      return Scaffold(
        backgroundColor: BentoTheme.darkBg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Alarma no encontrada',
                  style: TextStyle(color: BentoTheme.cream, fontSize: 18)),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BentoTheme.accentAlarm,
                    foregroundColor: const Color(0xFF0C0C0D),
                  ),
                  child: const Text('Cerrar')),
            ],
          ),
        ),
      );
    }

    final isSuccess = _verdict == PhotoVerdict.yes;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: isSuccess ? BentoTheme.successGreen : BentoTheme.darkBg,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.sizeOf(context).height - 48,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    alarm.formattedTime,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.w900,
                      color: BentoTheme.cream,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    alarm.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 20,
                        color: BentoTheme.creamAlpha(0.7),
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 28),
                  if (isSuccess)
                    _successBlock()
                  else ...[
                    if (_silenced) _pausedBanner(),
                    if (_photo != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SizedBox(
                          height: 160,
                          child: Image.file(_photo!, fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _targetCard(alarm),
                    if (_cameraDenied) ...[
                      const SizedBox(height: 12),
                      _cameraDeniedBlock(),
                    ],
                    if (!_verifying) ...[
                      if (_verdict == PhotoVerdict.no) ...[
                        const SizedBox(height: 12),
                        _warning(
                          'No detecté "${alarm.targetObject}". '
                          'Intento #$_attempts — inténtalo de nuevo.',
                        ),
                      ],
                      if (_verdict == PhotoVerdict.unclear) ...[
                        const SizedBox(height: 12),
                        _warning(
                          'La IA no dio un veredicto claro sobre la foto. '
                          'Repite la foto o resuelve un reto mental.',
                        ),
                      ],
                      if (_aiError != null) ...[
                        const SizedBox(height: 12),
                        _warning('$_aiError Puedes apagarla con un reto mental.'),
                      ],
                    ],
                    const SizedBox(height: 20),
                    if (_verifying) _verifyingBlock() else _actions(),
                    const SizedBox(height: 14),
                    _aiStatus(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _successBlock() {
    return Column(
      children: [
        const Icon(Icons.check_circle_outline, color: Colors.white, size: 80),
        const SizedBox(height: 16),
        const Text(
          '¡Alarma desactivada!',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        const Text(
          'Cerrando...',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      ],
    );
  }

  Widget _pausedBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: BentoTheme.accentOrange.withValues(alpha: 0.18),
          border: Border.all(color: BentoTheme.accentOrange.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.pause_circle_outline,
                color: BentoTheme.accentOrange, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Timbre en pausa mientras verificas. '
                'Vuelve solo en ${_maxSilence.inMinutes} min.',
                style: TextStyle(
                    color: BentoTheme.cream,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _targetCard(AlarmModel alarm) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: BentoTheme.creamAlpha(0.1),
        border: Border.all(color: BentoTheme.creamAlpha(0.14)),
      ),
      child: Row(
        children: [
          Icon(Icons.camera_alt, color: BentoTheme.accentOrange, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Para desactivar, fotografía:',
                    style: TextStyle(
                        color: BentoTheme.creamAlpha(0.7), fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  alarm.targetObject,
                  style: TextStyle(
                      color: BentoTheme.cream,
                      fontSize: 18,
                      fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cameraDeniedBlock() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: BentoTheme.errorRed.withValues(alpha: 0.85),
      ),
      child: const Column(
        children: [
          Text(
            'Sin permiso de cámara no puedo validar la foto. '
            'Puedes apagar la alarma con un reto mental.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          SizedBox(height: 8),
          TextButton(
            onPressed: LockTaskService.openAppSettings,
            child: Text(
              'Abrir ajustes',
              style: TextStyle(
                  color: Colors.white,
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _warning(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: BentoTheme.errorRed.withValues(alpha: 0.85),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }

  /// Mientras la IA mira la foto: contador visible y salida por el reto. Ver
  /// los segundos correr evita la sensación de cuelgue, y el botón garantiza
  /// que nunca dependas de que el servidor conteste.
  Widget _verifyingBlock() {
    return Column(
      children: [
        CircularProgressIndicator(color: BentoTheme.accentAlarm),
        const SizedBox(height: 12),
        Text('Verificando con IA... ${_elapsed}s',
            style:
                TextStyle(color: BentoTheme.creamAlpha(0.7), fontSize: 14)),
        const SizedBox(height: 4),
        Text('Máximo ${_visionTimeout.inSeconds}s',
            style:
                TextStyle(color: BentoTheme.creamAlpha(0.4), fontSize: 12)),
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: _openChallenge,
          icon: Icon(Icons.psychology_alt_outlined,
              size: 18, color: BentoTheme.accentAlarm),
          label: Text(
            'No esperar: resolver un reto',
            style: TextStyle(
                color: BentoTheme.accentAlarm,
                fontWeight: FontWeight.w800,
                fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _actions() {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: _takePhoto,
          style: ElevatedButton.styleFrom(
            backgroundColor: BentoTheme.accentAlarm,
            foregroundColor: const Color(0xFF0C0C0D),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          icon: const Icon(Icons.camera_alt, size: 26),
          label: Text(
            _photo == null ? 'Tomar Foto' : 'Intentar de Nuevo',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _openChallenge,
          style: OutlinedButton.styleFrom(
            foregroundColor: BentoTheme.cream,
            padding: const EdgeInsets.symmetric(vertical: 15),
            side: BorderSide(color: BentoTheme.creamAlpha(0.28)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          icon: const Icon(Icons.psychology_alt_outlined, size: 22),
          label: const Text(
            'Resolver un reto mental',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  /// Estado del servidor de IA, para saber a qué atenerte ANTES de gastar el
  /// esfuerzo de ir a fotografiar el objeto.
  Widget _aiStatus() {
    final (icon, text, color) = switch (_aiReachable) {
      null => (
          Icons.hourglass_empty,
          'Preparando el modelo de visión...',
          BentoTheme.creamAlpha(0.45),
        ),
      true => (
          Icons.bolt,
          'IA lista — la foto se valida rápido',
          BentoTheme.successGreen,
        ),
      false => (
          Icons.cloud_off,
          'IA sin conexión — usa el reto mental',
          BentoTheme.accentOrange,
        ),
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  // ─────────────────────── piel editorial ───────────────────────

  static final Color _edDanger =
      EditorialTheme.accentAt(const Color(0xFFE5484D), 0.62);

  Widget _buildEditorial() {
    if (_loading) {
      return const Scaffold(
        backgroundColor: EditorialTheme.canvas,
        body: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: EditorialTheme.paper),
          ),
        ),
      );
    }

    final alarm = _alarm;
    if (alarm == null) return _edNotFound();

    final success = _verdict == PhotoVerdict.yes;

    return PopScope(
      canPop: false,
      child: Scaffold(
        // Al acertar, el lienzo se invierte a papel: es el único momento en que
        // esta pantalla puede permitirse el fogonazo, porque ya estás de pie y
        // dura dos segundos.
        backgroundColor: success ? EditorialTheme.paper : EditorialTheme.canvas,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.sizeOf(context).height - 44,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: success
                    ? [_edSuccess()]
                    : [
                        _edClock(alarm),
                        const SizedBox(height: 26),
                        if (_silenced) ...[
                          _edNotice(
                            Icons.pause_circle_outline,
                            'Timbre en pausa mientras verificas. Vuelve solo '
                            'en ${_maxSilence.inMinutes} min.',
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_photo != null) ...[
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(EditorialTheme.radiusCard),
                            child: SizedBox(
                              height: 150,
                              width: double.infinity,
                              child: Image.file(_photo!, fit: BoxFit.cover),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _edTarget(alarm),
                        if (_cameraDenied) ...[
                          const SizedBox(height: 12),
                          _edAlert(
                            'Sin permiso de cámara no puedo validar la foto. '
                            'Puedes apagarla con un reto mental.',
                            action: (
                              'Abrir ajustes',
                              LockTaskService.openAppSettings,
                            ),
                          ),
                        ],
                        if (!_verifying) ...[
                          if (_verdict == PhotoVerdict.no) ...[
                            const SizedBox(height: 12),
                            _edAlert(
                              'No vi "${alarm.targetObject}". '
                              'Intento $_attempts — prueba otra vez.',
                            ),
                          ],
                          if (_verdict == PhotoVerdict.unclear) ...[
                            const SizedBox(height: 12),
                            _edAlert(
                              'La IA no dio un veredicto claro. Repite la foto '
                              'o resuelve un reto mental.',
                            ),
                          ],
                          if (_aiError != null) ...[
                            const SizedBox(height: 12),
                            _edAlert('$_aiError Puedes apagarla con un reto mental.'),
                          ],
                        ],
                        const SizedBox(height: 22),
                        if (_verifying) _edVerifying() else _edActions(),
                        const SizedBox(height: 16),
                        _edAiStatus(),
                      ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _edNotFound() {
    return Scaffold(
      backgroundColor: EditorialTheme.canvas,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(EditorialTheme.margin),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Alarma no encontrada',
                style: EditorialTheme.text(18,
                    weight: FontWeight.w600, color: EditorialTheme.paper),
              ),
              const SizedBox(height: 18),
              EditorialPressable(
                onTap: () => Navigator.of(context).pop(),
                scale: 0.95,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                  decoration: BoxDecoration(
                    color: EditorialTheme.paper,
                    borderRadius:
                        BorderRadius.circular(EditorialTheme.radiusChip),
                  ),
                  child: Text(
                    'Cerrar',
                    style: EditorialTheme.text(14,
                        weight: FontWeight.w600, color: EditorialTheme.ink),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// La hora, enorme. Es lo primero que se lee al abrir los ojos y lo único
  /// que justifica ese tamaño en toda la app.
  Widget _edClock(AlarmModel alarm) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            alarm.formattedTime,
            style: EditorialTheme.caps(
              84,
              color: EditorialTheme.paper,
              letterSpacing: -4,
              height: 0.9,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          alarm.label.toUpperCase(),
          textAlign: TextAlign.center,
          style: EditorialTheme.label(12, color: EditorialTheme.muted),
        ),
      ],
    );
  }

  Widget _edSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check, size: 72, color: EditorialTheme.ink),
        const SizedBox(height: 18),
        Text(
          'ARRIBA',
          textAlign: TextAlign.center,
          style: EditorialTheme.caps(
            46,
            color: EditorialTheme.ink,
            letterSpacing: -2,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Alarma apagada.',
          textAlign: TextAlign.center,
          style: EditorialTheme.text(16, color: EditorialTheme.grayText),
        ),
      ],
    );
  }

  /// Qué hay que fotografiar. Va en papel porque es la instrucción: si sólo se
  /// lee una cosa de la pantalla, tiene que ser esta.
  Widget _edTarget(AlarmModel alarm) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
      ),
      child: Row(
        children: [
          Icon(Icons.camera_alt_outlined, size: 26, color: EditorialTheme.ink),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PARA APAGARLA, FOTOGRAFÍA',
                  style: EditorialTheme.label(9.5, color: EditorialTheme.grayText),
                ),
                const SizedBox(height: 4),
                Text(
                  alarm.targetObject,
                  style: EditorialTheme.text(19,
                      weight: FontWeight.w600, color: EditorialTheme.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Aviso neutro: algo está pasando, pero no has hecho nada mal.
  Widget _edNotice(IconData icon, String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: EditorialTheme.surface,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: EditorialTheme.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: EditorialTheme.text(12.5,
                  color: EditorialTheme.paperAlpha(0.75), height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  /// Algo salió mal. El rojo se queda en el filete lateral y no inunda el
  /// bloque: un rectángulo rojo entero a las seis de la mañana se lee como una
  /// bronca, y el usuario no ha hecho nada malo — la foto no salió, nada más.
  Widget _edAlert(String message, {(String, VoidCallback)? action}) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: EditorialTheme.surface,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 4, child: ColoredBox(color: _edDanger)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: EditorialTheme.text(12.5,
                          color: EditorialTheme.paperAlpha(0.85), height: 1.4),
                    ),
                    if (action != null) ...[
                      const SizedBox(height: 8),
                      EditorialPressable(
                        onTap: action.$2,
                        scale: 0.94,
                        child: Text(
                          action.$1,
                          style: EditorialTheme.text(12.5,
                              weight: FontWeight.w700, color: EditorialTheme.paper)
                              .copyWith(decoration: TextDecoration.underline),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mientras la IA mira la foto. El contador visible evita que parezca colgado
  /// y el reto garantiza que nunca dependas de que el servidor conteste.
  Widget _edVerifying() {
    return Column(
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: EditorialTheme.paper),
        ),
        const SizedBox(height: 14),
        Text(
          'MIRANDO LA FOTO · ${_elapsed}s DE ${_visionTimeout.inSeconds}s',
          style: EditorialTheme.label(10.5, color: EditorialTheme.muted),
        ),
        const SizedBox(height: 16),
        EditorialPressable(
          onTap: _openChallenge,
          scale: 0.95,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'No esperar: resolver un reto',
              style: EditorialTheme.text(14,
                  weight: FontWeight.w600,
                  color: EditorialTheme.paperAlpha(0.75)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _edActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Papel pleno: la inversión máxima disponible sobre el lienzo. Es lo
        // único que hay que encontrar a tientas.
        EditorialPressable(
          onTap: _takePhoto,
          scale: 0.97,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: EditorialTheme.paper,
              borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.camera_alt, size: 24, color: EditorialTheme.ink),
                const SizedBox(width: 11),
                Text(
                  _photo == null ? 'Tomar foto' : 'Intentar otra vez',
                  style: EditorialTheme.text(17,
                      weight: FontWeight.w600, color: EditorialTheme.ink),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        EditorialPressable(
          onTap: _openChallenge,
          scale: 0.97,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: EditorialTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.psychology_alt_outlined,
                    size: 20, color: EditorialTheme.paperAlpha(0.8)),
                const SizedBox(width: 10),
                Text(
                  'Resolver un reto mental',
                  style: EditorialTheme.text(15,
                      weight: FontWeight.w600,
                      color: EditorialTheme.paperAlpha(0.85)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Estado del servidor de IA, para saber a qué atenerte ANTES de gastar el
  /// esfuerzo de ir hasta el objeto.
  Widget _edAiStatus() {
    final (icon, text) = switch (_aiReachable) {
      null => (Icons.hourglass_empty, 'PREPARANDO EL MODELO DE VISIÓN'),
      true => (Icons.bolt, 'IA LISTA — LA FOTO SE VALIDA RÁPIDO'),
      false => (Icons.cloud_off, 'IA SIN CONEXIÓN — USA EL RETO MENTAL'),
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 13, color: EditorialTheme.muted),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            style: EditorialTheme.label(9.5, color: EditorialTheme.muted),
          ),
        ),
      ],
    );
  }
}
