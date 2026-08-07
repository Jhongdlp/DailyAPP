import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Preview de cámara que llena el espacio disponible sin deformar la imagen
/// (equivalente a `BoxFit.cover`), recortando lo que sobre.
///
/// `previewSize` viene en orientación del sensor (apaisada) en Android, por eso
/// se invierten los ejes. Cuando el plugin todavía no lo reporta se usa
/// `value.aspectRatio` como respaldo: la versión anterior caía a un `SizedBox`
/// de 1x1 que, estirado por el `FittedBox`, pintaba un rectángulo plano — parte
/// de la "pantalla en blanco" que se veía al cambiar de cámara.
class CameraCoverPreview extends StatelessWidget {
  final CameraController controller;

  const CameraCoverPreview({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final preview = controller.value.previewSize;
    final width = preview?.height ?? 3;
    final height = preview?.width ?? 4;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: width,
          height: height,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}
