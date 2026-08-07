import 'dart:async';

import 'package:camera/camera.dart';

/// Utilidades compartidas por las pantallas de cámara (alarma y ejercicio).
///
/// Existen dos motivos para centralizar esto:
///
/// 1. **`availableCameras()` es caro.** En Android abre el `CameraManager` de
///    CameraX y consulta las características de cada lente; en gama media son
///    fácilmente 300-800 ms la primera vez. El resultado no cambia durante la
///    vida del proceso, así que se cachea y se precalienta al arrancar la app:
///    cuando el usuario abre la cámara, ese coste ya está pagado.
///
/// 2. **El orden de apertura/cierre importa.** El dispositivo físico solo lo
///    puede tener abierto un `CameraController` a la vez. Si se inicializa el
///    nuevo antes de liberar el anterior, la nueva sesión se queda esperando al
///    hardware y `initialize()` no vuelve nunca: preview en blanco eterno al
///    cambiar a la cámara frontal.
class CameraService {
  CameraService._();

  static List<CameraDescription>? _cache;
  static Future<List<CameraDescription>>? _inFlight;

  /// Lista de cámaras del dispositivo, cacheada tras la primera consulta.
  ///
  /// Las llamadas concurrentes comparten el mismo future en lugar de disparar
  /// varias enumeraciones a la vez.
  static Future<List<CameraDescription>> cameras() {
    final cached = _cache;
    if (cached != null) return Future.value(cached);
    return _inFlight ??= availableCameras().then((list) {
      _cache = list;
      _inFlight = null;
      return list;
    }).catchError((Object e) {
      // Un fallo no se cachea: puede ser un permiso que el usuario conceda
      // después, y la siguiente apertura debe volver a intentarlo.
      _inFlight = null;
      throw e;
    });
  }

  /// Lanza la enumeración en segundo plano sin bloquear el arranque.
  static void prewarm() {
    unawaited(cameras().catchError((_) => const <CameraDescription>[]));
  }

  /// Índice de la cámara trasera (o 0 si el dispositivo no reporta ninguna).
  static int backCameraIndex(List<CameraDescription> cameras) {
    final index = cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
    );
    return index < 0 ? 0 : index;
  }

  /// Cierra `previous` y abre `camera`, en ese orden, con tope de tiempo.
  ///
  /// Devuelve el controller ya inicializado y con el flash apagado. Lanza
  /// [TimeoutException] si el hardware no responde en [timeout] — sin esto la
  /// UI se queda cargando para siempre en vez de poder mostrar un error.
  static Future<CameraController> open(
    CameraDescription camera, {
    CameraController? previous,
    ResolutionPreset resolution = ResolutionPreset.medium,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await disposeQuietly(previous);

    final controller = CameraController(
      camera,
      resolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize().timeout(timeout);
    } catch (e) {
      await disposeQuietly(controller);
      rethrow;
    }
    // La cámara frontal no tiene flash físico: CameraX (Android) simula uno
    // encendiendo la pantalla en blanco si el modo queda en auto/always (el
    // valor por defecto al inicializar). Sin esto, cambiar a selfie deja la
    // pantalla completamente blanca.
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}
    return controller;
  }

  /// `dispose()` tolerante: liberar un controller que nunca llegó a
  /// inicializarse (o que ya se liberó) puede lanzar, y en ese punto el error
  /// no aporta nada.
  static Future<void> disposeQuietly(CameraController? controller) async {
    if (controller == null) return;
    try {
      await controller.dispose();
    } catch (_) {}
  }

  /// Mensaje de error legible para el usuario.
  static String friendlyError(Object e) {
    if (e is TimeoutException) {
      return 'La cámara tardó demasiado en responder. Vuelve a intentarlo.';
    }
    if (e is CameraException) {
      if (e.code == 'CameraAccessDenied' ||
          e.code == 'CameraAccessDeniedWithoutPrompt' ||
          e.code == 'CameraAccessRestricted') {
        return 'Necesito permiso para usar la cámara. Actívalo en los ajustes del sistema.';
      }
      return e.description ?? 'No se pudo abrir la cámara.';
    }
    return 'No se pudo abrir la cámara.';
  }
}
