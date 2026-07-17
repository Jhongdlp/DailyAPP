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
import '../../core/widgets/rpg_celebration.dart';
import '../../core/services/alarm_service.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/lock_task_service.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/utils/error_snackbar.dart';
import 'widgets/camera_capture_screen.dart';

class AlarmDismissScreen extends ConsumerStatefulWidget {
  final String alarmId;

  const AlarmDismissScreen({super.key, required this.alarmId});

  @override
  ConsumerState<AlarmDismissScreen> createState() => _AlarmDismissScreenState();
}

class _AlarmDismissScreenState extends ConsumerState<AlarmDismissScreen> {
  AlarmModel? _alarm;
  bool _loading = true;
  bool _verifying = false;
  bool? _result;
  File? _photo;
  int _attempts = 0;
  bool _cameraDenied = false;

  @override
  void initState() {
    super.initState();
    // Pinta la alarma encima del bloqueo para poder fotografiar sin desbloquear.
    LockTaskService.showOverLockscreen(true);
    _loadAlarm();
    _prepareCameraThenLock();
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

  Future<void> _takePhoto() async {
    if (_cameraDenied) {
      await _prepareCameraThenLock();
      if (!mounted || _cameraDenied) return;
    }
    final picked = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CameraCaptureScreen(targetObject: _alarm!.targetObject),
      ),
    );
    if (picked == null || !mounted) return;

    setState(() {
      _photo = picked;
      _verifying = true;
      _result = null;
      _attempts++;
    });

    try {
      final bytes = await _photo!.readAsBytes();
      final settings = ref.read(settingsProvider);
      final aiClient = LocalAIClient(
        baseUrl: settings.localAiUrl,
        visionModelName: settings.visionModel,
      );

      final ok =
          await aiClient.verifyAlarmPhoto(base64Encode(bytes), _alarm!.targetObject);

      if (mounted) setState(() => _result = ok);

      if (ok) {
        await _logDismissal(validated: true);
        final idInt = _alarm!.id.hashCode.abs() % 100000;
        await Alarm.stop(idInt);
        
        // Otorgar recompensa RPG por levantarse a tiempo
        final result = ref.read(rpgProvider.notifier).gainXpAndGold(30, 15);
        if (mounted) {
          RpgCelebration.show(
            context,
            xp: result['xpGained'] as int,
            gold: result['goldGained'] as int,
            levelUp: result['levelUp'] as bool,
            newLevel: result['newLevel'] as int?,
          );
        }

        await AlarmService.scheduleAlarm(_alarm!, from: DateTime.now().add(const Duration(minutes: 1)));
        await Future.delayed(const Duration(seconds: 2));
        // Solo aquí (foto validada) liberamos la pantalla y salimos.
        await LockTaskService.disable();
        await LockTaskService.showOverLockscreen(false);
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _verifying = false);
        showErrorSnackBar(context, message: 'Error de conexión con la IA: $e');
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

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

  @override
  Widget build(BuildContext context) {
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

    final isSuccess = _result == true;
    final isFail = _result == false && !_verifying;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor:
            isSuccess ? BentoTheme.successGreen : BentoTheme.darkBg,
        body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hora
              Text(
                alarm.formattedTime,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 80,
                  fontWeight: FontWeight.w900,
                  color: BentoTheme.cream,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                alarm.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 20,
                    color: BentoTheme.creamAlpha(0.7),
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 48),

              if (isSuccess) ...[
                const Icon(Icons.check_circle_outline,
                    color: Colors.white, size: 80),
                const SizedBox(height: 16),
                const Text(
                  '¡Alarma desactivada!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Cerrando...',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ] else ...[
                // Vista previa de foto
                if (_photo != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SizedBox(
                      height: 200,
                      child: Image.file(_photo!, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Instrucción
                Container(
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
                ),

                if (_cameraDenied) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: BentoTheme.errorRed.withValues(alpha: 0.85),
                    ),
                    child: const Column(
                      children: [
                        Text(
                          'Sin permiso de cámara no puedo validar la foto.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
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
                  ),
                ],

                if (isFail) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: BentoTheme.errorRed.withValues(alpha: 0.85),
                    ),
                    child: Text(
                      'No detecté "${alarm.targetObject}". Intento #$_attempts — inténtalo de nuevo.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                if (_verifying)
                  Column(
                    children: [
                      CircularProgressIndicator(color: BentoTheme.accentAlarm),
                      const SizedBox(height: 12),
                      Text('Verificando con IA...',
                          style:
                              TextStyle(color: BentoTheme.creamAlpha(0.7), fontSize: 14)),
                    ],
                  )
                else
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
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),);
  }
}
