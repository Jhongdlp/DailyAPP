import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/bento_theme.dart';

const int kMaxExercisePhotos = 5;

/// Cámara in-app multi-disparo (hasta [kMaxExercisePhotos] fotos), para el
/// registro diario de progreso físico.
///
/// A diferencia de `CameraCaptureScreen` (alarmas, un solo disparo), aquí cada
/// captura se acumula en una tira de miniaturas y el usuario decide cuándo
/// terminar con "Listo". No se reutiliza esa pantalla porque su contrato de
/// "un `File` y se cierra" está en uso por `alarm_dismiss_screen.dart`.
///
/// Devuelve `List<File>` (posiblemente vacía si el usuario cancela sin tomar
/// ninguna foto) vía `Navigator.pop(context, files)`.
class ExercisePhotoCaptureScreen extends StatefulWidget {
  const ExercisePhotoCaptureScreen({super.key});

  @override
  State<ExercisePhotoCaptureScreen> createState() => _ExercisePhotoCaptureScreenState();
}

class _ExercisePhotoCaptureScreenState extends State<ExercisePhotoCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _initializing = true;
  bool _capturing = false;
  String? _error;
  final List<File> _shots = [];

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
      _cameraIndex = cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
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
      // La cámara frontal no tiene flash físico: CameraX (Android) simula uno
      // encendiendo la pantalla en blanco si el modo queda en auto/always
      // (el valor por defecto al inicializar). Sin esto, cambiar a selfie
      // deja la pantalla completamente blanca.
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}
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
        controller.value.isTakingPicture ||
        _shots.length >= kMaxExercisePhotos) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final shot = await controller.takePicture();
      if (mounted) {
        setState(() {
          _shots.add(File(shot.path));
          _capturing = false;
        });
      }
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

  void _removeShot(int index) {
    setState(() => _shots.removeAt(index));
  }

  void _finish() {
    Navigator.of(context).pop(_shots);
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
          _buildScrim(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                const Spacer(),
                if (_shots.isNotEmpty) _buildThumbnailStrip(),
                _buildBottomBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_error != null) return _buildError();
    final controller = _controller;
    if (_initializing || controller == null || !controller.value.isInitialized) {
      return Center(child: CircularProgressIndicator(color: BentoTheme.accentOrange));
    }
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
          Icon(Icons.no_photography_outlined, color: BentoTheme.accentOrange, size: 64),
          const SizedBox(height: 20),
          Text(
            _error ?? 'Error de cámara',
            textAlign: TextAlign.center,
            style: TextStyle(color: BentoTheme.cream, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(_shots),
            style: ElevatedButton.styleFrom(
              backgroundColor: BentoTheme.accentOrange,
              foregroundColor: const Color(0xFF0C0C0D),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Cerrar', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
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
          _CircleButton(icon: Icons.close, onTap: () => Navigator.of(context).pop(_shots)),
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
                  Icon(Icons.fitness_center, color: BentoTheme.accentOrange, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Foto de progreso ${_shots.length}/$kMaxExercisePhotos',
                    style: TextStyle(color: BentoTheme.cream, fontSize: 13, fontWeight: FontWeight.w700, fontFamily: 'Outfit'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailStrip() {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _shots.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_shots[index], width: 60, height: 60, fit: BoxFit.cover),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => _removeShot(index),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    final canShoot = _error == null &&
        !_initializing &&
        (_controller?.value.isInitialized ?? false) &&
        _shots.length < kMaxExercisePhotos;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: _shots.isNotEmpty
                ? TextButton(
                    onPressed: _finish,
                    child: Text(
                      'Listo',
                      style: TextStyle(color: BentoTheme.accentOrange, fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  )
                : null,
          ),
          const Spacer(),
          _ShutterButton(enabled: canShoot && !_capturing, busy: _capturing, onTap: _capture),
          const Spacer(),
          SizedBox(
            width: 72,
            child: _cameras.length > 1
                ? _CircleButton(icon: Icons.cameraswitch_outlined, onTap: _switchCamera)
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
      shape: CircleBorder(side: BorderSide(color: BentoTheme.creamAlpha(0.16))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(width: 48, height: 48, child: Icon(icon, color: BentoTheme.cream, size: 24)),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  const _ShutterButton({required this.enabled, required this.busy, required this.onTap});

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
              decoration: BoxDecoration(shape: BoxShape.circle, color: BentoTheme.accentOrange),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0C0C0D)),
                      ),
                    )
                  : const Icon(Icons.camera_alt, color: Color(0xFF0C0C0D), size: 30),
            ),
          ),
        ),
      ),
    );
  }
}
