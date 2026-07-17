import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../network/local_ai_client.dart';

class VoiceService {
  final AudioRecorder _recorder = AudioRecorder();
  final LocalAIClient _aiClient;
  bool _isRecording = false;
  String? _currentPath;

  VoiceService(this._aiClient);

  bool get isRecording => _isRecording;

  /// Inicia la grabación de audio guardando en un archivo temporal
  Future<void> startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
        _currentPath = path;

        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );
        _isRecording = true;
      } else {
        throw Exception('Permiso de micrófono denegado');
      }
    } catch (e) {
      _isRecording = false;
      rethrow;
    }
  }

  /// Detiene la grabación y retorna el path del archivo de audio
  Future<String?> stopRecording() async {
    try {
      if (!_isRecording) return null;
      final path = await _recorder.stop();
      _isRecording = false;
      return path ?? _currentPath;
    } catch (e) {
      _isRecording = false;
      rethrow;
    }
  }

  /// Envía el archivo de audio a un servidor de Whisper local para su transcripción.
  /// Si el servidor local falla o está offline, cae a una simulación inteligente de voz para pruebas.
  Future<String> transcribe(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('El archivo de audio no existe en la ruta especificada.');
    }

    // Puerto y URL por defecto para un servidor de Whisper local (ej. Whisper.cpp o faster-whisper en el puerto 8000 o 11434 si soporta stt)
    final whisperUrl = Uri.parse('${_aiClient.baseUrl.replaceAll("11434", "8000")}/v1/audio/transcriptions');

    try {
      final request = http.MultipartRequest('POST', whisperUrl)
        ..files.add(await http.MultipartFile.fromPath('file', filePath))
        ..fields['model'] = 'whisper-1'
        ..fields['language'] = 'es';

      final response = await request.send().timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final json = jsonDecode(responseData);
        return json['text']?.toString().trim() ?? '';
      } else {
        throw Exception('El servidor Whisper retornó código ${response.statusCode}');
      }
    } catch (e) {
      // Fallback: Si no hay un servidor de Whisper corriendo, devolvemos una transcripción simulada
      // para facilitar las pruebas del usuario, informándole que está en modo simulación.
      return _generateSimulatedTranscription();
    }
  }

  /// Genera etiquetas inteligentes por IA basándose en el texto transcrito
  Future<List<String>> generateAutoTags(String text) async {
    if (text.trim().isEmpty) return [];

    final prompt = 'Analiza el siguiente texto de una nota de voz y genera de 2 a 4 etiquetas en formato de hashtag (ej: #ideas, #trabajo, #receta, #personal) que describan mejor el contenido. Responde ÚNICAMENTE con los hashtags separados por espacios. No añadas introducciones, explicaciones ni comentarios. Texto:\n"$text"';

    try {
      final response = await _aiClient.askText(
        prompt,
        systemPrompt: 'Eres un categorizador de notas ultra-minimalista. Solo respondes con hashtags separados por espacios.',
      );

      // Limpiar y separar los hashtags obtenidos
      final cleanResponse = response.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();
      final tags = cleanResponse
          .split(RegExp(r'\s+'))
          .where((tag) => tag.startsWith('#') && tag.length > 1)
          .map((tag) => tag.toLowerCase())
          .toList();
      return tags;
    } catch (_) {
      // Fallback de etiquetas estáticas simples si la IA local no responde
      return ['#voz', '#dictado'];
    }
  }

  String _generateSimulatedTranscription() {
    final simulations = [
      'Reunión de equipo mañana a las diez para revisar el estado del Bento Grid y el diseño de la pantalla de hábitos.',
      'Comprar verduras, leche, avena y huevos para el desayuno saludable de la semana.',
      'Idea de proyecto: desarrollar un sistema de notas relacionales estilo Notion combinando enlaces de grafos de conocimiento.',
      'Recordatorio: pagar la suscripción del servidor y actualizar los esquemas de base de datos de Supabase antes del lunes.',
    ];
    // Escoger una simulación aleatoria
    final index = DateTime.now().millisecondsSinceEpoch % simulations.length;
    return '[Transcripción Simulada (Sin servidor Whisper local)]: ${simulations[index]}';
  }
}
