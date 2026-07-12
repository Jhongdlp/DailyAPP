import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/bento_theme.dart';

/// Cámara in-app a pantalla completa siguiendo el diseño oscuro Bento.
///
/// Se abre como un modal (route) y devuelve el [File] de la foto capturada
/// mediante `Navigator.pop(context, file)`, o `null` si el usuario cancela.
///
/// Uso:
/// ```dart
/// final file = await Navigator.of(context).push<File>(
///   MaterialPageRoute(
///     fullscreenDialog: true,
///     builder: (_) => CameraCaptureScreen(targetObject: alarm.targetObject),
///   ),
/// );
/// ```
class CameraCaptureScreen extends StatefulWidget {
  /// Objeto que el usuario debe fotografiar (se muestra como pista arriba).
  final String targetObject;

  const CameraCaptureScreen({super.key, required this.targetObject});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _initializing = true;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  Future<void> _setup() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _error = 'No se encontró ninguna cámara en el dispositivo.';
            _initializing = false;
          });
        }
        return;
      }
      _cameras = cameras;
      // Preferir la cámara trasera.
      _cameraIndex = cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (_cameraIndex < 0) _cameraIndex = 0;
      await _initController(_cameras[_cameraIndex]);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(e);
          _initializing = false;
        });
      }
    }
  }

  Future<void> _initController(CameraDescription camera) async {
    final previous = _controller;
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;
    try {
      await controller.initialize();
      await previous?.dispose();
      if (mounted) setState(() => _initializing = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(e);
          _initializing = false;
        });
      }
    }
  }

  String _friendlyError(Object e) {
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

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _capturing) return;
    setState(() => _initializing = true);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _initController(_cameras[_cameraIndex]);
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _capturing ||
        controller.value.isTakingPicture) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final shot = await controller.takePicture();
      if (mounted) Navigator.of(context).pop(File(shot.path));
    } catch (e) {
      if (mounted) {
        setState(() => _capturing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: BentoTheme.errorRed,
            content: Text(
              'No se pudo tomar la foto: ${_friendlyError(e)}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        final controller = _controller;
        if (controller == null) return;
        _controller = null;
        // El setState es imprescindible: sin él, el árbol sigue conteniendo un
        // CameraPreview que apunta a un controller ya liberado y la app revienta
        // en el siguiente frame (justo lo que pasaba al aparecer el prompt de
        // huella o el diálogo de permisos sobre la pantalla de la alarma).
        if (mounted) setState(() => _initializing = true);
        controller.dispose();
      case AppLifecycleState.resumed:
        if (_controller == null && _cameras.isNotEmpty && _error == null) {
          if (mounted) setState(() => _initializing = true);
          _initController(_cameras[_cameraIndex]);
        }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BentoTheme.darkBg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildPreview(),
          // Degradado superior/inferior para legibilidad de los controles.
          _buildScrim(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                const Spacer(),
                _buildBottomBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_error != null) {
      return _buildError();
    }
    final controller = _controller;
    if (_initializing || controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: BentoTheme.accentAlarm),
      );
    }
    // Cubrir toda la pantalla manteniendo el aspecto de la cámara.
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.previewSize?.height ?? 1,
        height: controller.value.previewSize?.width ?? 1,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.no_photography_outlined,
              color: BentoTheme.accentOrange, size: 64),
          const SizedBox(height: 20),
          Text(
            _error ?? 'Error de cámara',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: BentoTheme.cream, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: BentoTheme.accentAlarm,
              foregroundColor: const Color(0xFF0C0C0D),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Cerrar',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _buildScrim() {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.22, 0.72, 1.0],
            colors: [
              Colors.black.withValues(alpha: 0.55),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.65),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          _CircleButton(
            icon: Icons.close,
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.black.withValues(alpha: 0.35),
                border: Border.all(color: BentoTheme.creamAlpha(0.16)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.camera_alt,
                      color: BentoTheme.accentOrange, size: 20),
                  const SizedBox(width: 10),
                  Flexible(
                    child: RichText(
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: TextStyle(
                            color: BentoTheme.creamAlpha(0.75),
                            fontSize: 13,
                            fontFamily: 'Outfit'),
                        children: [
                          const TextSpan(text: 'Fotografía: '),
                          TextSpan(
                            text: widget.targetObject,
                            style: const TextStyle(
                                color: BentoTheme.cream,
                                fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final canShoot = _error == null &&
        !_initializing &&
        (_controller?.value.isInitialized ?? false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Row(
        children: [
          // Espaciador para equilibrar el botón de cambio de cámara.
          const SizedBox(width: 56),
          const Spacer(),
          _ShutterButton(
            enabled: canShoot && !_capturing,
            busy: _capturing,
            onTap: _capture,
          ),
          const Spacer(),
          SizedBox(
            width: 56,
            child: _cameras.length > 1
                ? _CircleButton(
                    icon: Icons.cameraswitch_outlined,
                    onTap: _switchCamera,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: CircleBorder(
        side: BorderSide(color: BentoTheme.creamAlpha(0.16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: BentoTheme.cream, size: 24),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  const _ShutterButton({
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled || busy ? 1 : 0.5,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: BentoTheme.creamAlpha(0.85), width: 4),
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: BentoTheme.accentAlarm,
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFF0C0C0D)),
                      ),
                    )
                  : const Icon(Icons.camera_alt,
                      color: Color(0xFF0C0C0D), size: 30),
            ),
          ),
        ),
      ),
    );
  }
}
