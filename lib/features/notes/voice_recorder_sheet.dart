import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/providers/voice_provider.dart';

class VoiceRecorderSheet extends ConsumerStatefulWidget {
  final Function(String text, List<String> tags) onTranscribed;

  const VoiceRecorderSheet({
    super.key,
    required this.onTranscribed,
  });

  @override
  ConsumerState<VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

class _VoiceRecorderSheetState extends ConsumerState<VoiceRecorderSheet> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  Timer? _timer;
  int _seconds = 0;
  bool _isProcessing = false;
  String _statusMessage = 'Escuchando...';
  final List<double> _mockWaves = [15, 30, 45, 20, 60, 40, 15, 55, 35, 10, 50, 25, 45, 30, 15];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    // Iniciar grabación automáticamente al abrir la hoja
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startRecordingFlow();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startRecordingFlow() async {
    final voiceService = ref.read(voiceServiceProvider);
    try {
      await voiceService.startRecording();
      _startTimer();
      setState(() {
        _statusMessage = 'Grabando nota de voz...';
      });
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al iniciar micrófono: $e'),
            backgroundColor: BentoTheme.errorRed,
          ),
        );
      }
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _seconds++;
        });
      }
    });
  }

  String _formatTime(int sec) {
    final minutes = (sec ~/ 60).toString().padLeft(2, '0');
    final seconds = (sec % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _stopAndTranscribeFlow() async {
    _timer?.cancel();
    final voiceService = ref.read(voiceServiceProvider);
    
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Transcribiendo audio con Whisper...';
    });

    try {
      final path = await voiceService.stopRecording();
      if (path != null) {
        final text = await voiceService.transcribe(path);
        
        if (mounted) {
          setState(() {
            _statusMessage = 'Generando etiquetas inteligentes...';
          });
        }

        final tags = await voiceService.generateAutoTags(text);

        if (mounted) {
          widget.onTranscribed(text, tags);
          Navigator.pop(context);
        }
      } else {
        throw Exception('No se pudo recuperar el archivo de audio.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Error en transcripción';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: BentoTheme.errorRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BentoTheme.darkCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        top: 14,
        left: 24,
        right: 24,
        bottom: 24 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tirador
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: BentoTheme.creamAlpha(0.12),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          Text(
            'DIARIO POR VOZ',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              fontSize: 12,
              letterSpacing: 1.5,
              fontWeight: FontWeight.bold,
              color: BentoTheme.accentBrain,
            ),
          ),
          const SizedBox(height: 18),

          // Icono Grabador / Spinner
          Center(
            child: _isProcessing
                ? SizedBox(
                    width: 70,
                    height: 70,
                    child: CircularProgressIndicator(
                      color: BentoTheme.accentBrain,
                      strokeWidth: 4,
                    ),
                  )
                : ScaleTransition(
                    scale: Tween<double>(begin: 0.95, end: 1.08).animate(
                      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
                    ),
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: BentoTheme.accentBrain.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: BentoTheme.accentBrain.withValues(alpha: 0.35),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.mic,
                        size: 32,
                        color: BentoTheme.accentBrain,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 20),

          // Temporizador
          if (!_isProcessing)
            Center(
              child: Text(
                _formatTime(_seconds),
                style: GoogleFonts.montserrat(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: BentoTheme.cream,
                  letterSpacing: 1,
                ),
              ),
            ),
          const SizedBox(height: 12),

          // Mensaje de Estado
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: BentoTheme.creamAlpha(0.6),
            ),
          ),
          const SizedBox(height: 24),

          // Ondas de Audio de Simulación (Pulsantes mientras graba)
          if (!_isProcessing)
            SizedBox(
              height: 40,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: _mockWaves.map((height) {
                  return AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final factor = 0.4 + (_pulseController.value * 0.6);
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        width: 3.5,
                        height: height * factor,
                        decoration: BoxDecoration(
                          color: BentoTheme.accentBrain.withValues(
                            alpha: 0.3 + (_pulseController.value * 0.4),
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 28),

          // Botones de control
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_isProcessing) ...[
                // Cancelar
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: BentoTheme.creamSecondary,
                    side: BorderSide(color: BentoTheme.creamAlpha(0.18)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  onPressed: () async {
                    await ref.read(voiceServiceProvider).stopRecording();
                    if (mounted) Navigator.pop(context);
                  },
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 16),
                // Guardar y transcribir
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BentoTheme.accentBrain,
                    foregroundColor: const Color(0xFF0C0C0D),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  ),
                  onPressed: _stopAndTranscribeFlow,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stop, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Terminar',
                        style: GoogleFonts.montserrat(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
