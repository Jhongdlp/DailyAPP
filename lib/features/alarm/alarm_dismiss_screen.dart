import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:alarm/alarm.dart';
import '../../core/models/alarm_model.dart';
import '../../core/network/local_ai_client.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/alarm_service.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/utils/error_snackbar.dart';

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
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadAlarm();
  }

  Future<void> _loadAlarm() async {
    try {
      final data = await Supabase.instance.client
          .from('alarms')
          .select()
          .eq('id', widget.alarmId)
          .single();
      if (mounted) {
        setState(() {
          _alarm = AlarmModel.fromJson(data);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _takePhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 50,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) return;

    setState(() {
      _photo = File(picked.path);
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
        await AlarmService.scheduleAlarm(_alarm!, from: DateTime.now().add(const Duration(minutes: 1)));
        await Future.delayed(const Duration(seconds: 2));
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
      return const Scaffold(
        backgroundColor: BentoTheme.primaryDark,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final alarm = _alarm;
    if (alarm == null) {
      return Scaffold(
        backgroundColor: BentoTheme.primaryDark,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Alarma no encontrada',
                  style: TextStyle(color: Colors.white, fontSize: 18)),
              const SizedBox(height: 16),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context),
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
            isSuccess ? BentoTheme.successGreen : BentoTheme.primaryDark,
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
                style: const TextStyle(
                  fontSize: 80,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                alarm.label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20,
                    color: Colors.white70,
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
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.camera_alt, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Para desactivar, fotografía:',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                            const SizedBox(height: 2),
                            Text(
                              alarm.targetObject,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

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
                  const Column(
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 12),
                      Text('Verificando con IA...',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _takePhoto,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: BentoTheme.primaryDark,
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
