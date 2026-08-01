import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/exercise_model.dart';
import '../../core/network/local_ai_client.dart';
import '../../core/providers/exercise_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/lock_task_service.dart';
import '../../core/services/synced_write.dart';
import '../../core/utils/error_snackbar.dart';
import 'widgets/exercise_log_form.dart';
import 'widgets/exercise_photo_capture_screen.dart';

/// Punto único de entrada al flujo "cámara → formulario", usado tanto desde
/// el botón propio de la pestaña Ejercicio como desde el diálogo que aparece
/// al marcar el hábito de ejercicio como hecho. [forDate]/[habitId] hacen que
/// fotos y sesión queden guardadas bajo la misma fecha y el mismo hábito sin
/// importar por dónde se entró.
Future<void> runExerciseCaptureFlow(
  BuildContext context,
  WidgetRef ref, {
  required DateTime forDate,
  String? habitId,
}) async {
  final granted = await LockTaskService.requestCameraPermission();
  if (!context.mounted) return;
  if (!granted) {
    showErrorSnackBar(context, message: 'Se necesita permiso de cámara para tomar fotos de progreso.');
    return;
  }

  final shots = await Navigator.of(context).push<List<File>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const ExercisePhotoCaptureScreen(),
    ),
  );

  if (shots != null && shots.isNotEmpty) {
    // Cada foto sube y se clasifica en segundo plano: no se espera aquí a
    // propósito, para que el formulario se abra de inmediato después.
    for (final file in shots) {
      unawaited(_uploadAndClassify(ref, file, forDate));
    }
  }

  if (!context.mounted) return;
  await showExerciseLogForm(context, ref, forDate: forDate, habitId: habitId);
}

Future<void> _uploadAndClassify(WidgetRef ref, File file, DateTime forDate) async {
  final notifier = ref.read(exerciseProvider.notifier);
  ExercisePhoto photo;
  try {
    photo = await notifier.addPhoto(id: newRowId(), file: file, loggedDate: forDate);
  } catch (_) {
    // Sin conexión no hay dónde subir la foto: se pierde el intento de esta
    // toma. Limitación documentada de v1 (requiere conexión para progreso).
    return;
  }

  try {
    notifier.setPhotoClassificationLocal(photo.id, PhotoClassification.classifying);
    final settings = ref.read(settingsProvider);
    final aiClient = LocalAIClient(baseUrl: settings.localAiUrl, visionModelName: settings.visionModel);
    final bytes = await file.readAsBytes();
    final label = await aiClient.classifyExercisePhoto(base64Encode(bytes));
    final classification = switch (label) {
      'cara' => PhotoClassification.cara,
      'cuerpo' => PhotoClassification.cuerpo,
      _ => PhotoClassification.unknown,
    };
    await notifier.updatePhotoClassification(photo.id, classification);
  } catch (_) {
    await notifier.updatePhotoClassification(photo.id, PhotoClassification.failed);
  }
}
