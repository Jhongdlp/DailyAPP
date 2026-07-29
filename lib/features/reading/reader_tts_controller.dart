import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Lee el libro en voz alta párrafo a párrafo.
///
/// El avance se hace con un bucle que espera a que termine cada `speak`
/// (`awaitSpeakCompletion`) en vez de con el handler de completado del plugin:
/// así la secuencia es lineal y parar es simplemente dejar de iterar, sin
/// carreras entre el callback y una parada del usuario.
class ReaderTtsController extends ChangeNotifier {
  /// Texto plano de cada párrafo del libro. Es un callback porque el índice se
  /// construye después de abrir el libro, cuando este controlador ya existe.
  final List<String> Function() paragraphs;

  /// Se llama al empezar cada párrafo para que el lector lo traiga a pantalla.
  final void Function(int paragraphIndex) onParagraph;

  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;
  bool _active = false;
  int? _current;
  String? _error;

  ReaderTtsController({required this.paragraphs, required this.onParagraph});

  /// La voz del sistema no está en escritorio de serie; ahí se oculta la
  /// función en vez de fallar al pulsarla.
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  bool get isSpeaking => _active;
  int? get currentParagraph => _current;
  String? get error => _error;

  Future<void> _ensureInitialized(double rate, String? language) async {
    if (!_initialized) {
      // Sin esto `speak` vuelve de inmediato y el bucle recitaría el libro
      // entero de golpe.
      await _tts.awaitSpeakCompletion(true);
      _initialized = true;
    }
    await _tts.setSpeechRate(rate);
    if (language != null) {
      try {
        await _tts.setLanguage(language);
      } catch (_) {
        // Idioma no instalado en el dispositivo: se usa el del sistema
      }
    }
  }

  /// Idiomas de voz disponibles en el dispositivo (`es-ES`, `en-US`…).
  Future<List<String>> availableLanguages() async {
    try {
      final languages = await _tts.getLanguages;
      return [
        for (final language in languages as List) language.toString(),
      ]..sort();
    } catch (_) {
      return const [];
    }
  }

  Future<void> start({
    required int fromParagraph,
    required double rate,
    String? language,
  }) async {
    if (_active) return;
    _error = null;

    try {
      await _ensureInitialized(rate, language);
    } catch (e) {
      _error = 'No se pudo iniciar la voz: $e';
      notifyListeners();
      return;
    }

    _active = true;
    _current = fromParagraph;
    notifyListeners();
    unawaited(_loop());
  }

  Future<void> _loop() async {
    var index = _current ?? 0;

    while (_active) {
      final texts = paragraphs();
      if (index < 0 || index >= texts.length) break;

      final text = texts[index].trim();
      if (text.isEmpty) {
        index++;
        continue;
      }

      _current = index;
      onParagraph(index);
      notifyListeners();

      try {
        await _tts.speak(text);
      } catch (e) {
        _error = 'Error de la voz: $e';
        break;
      }

      // El usuario pudo parar mientras se hablaba: no avanzar en ese caso.
      if (!_active) return;
      index++;
    }

    await stop();
  }

  Future<void> stop() async {
    if (!_active && _current == null) return;
    _active = false;
    _current = null;
    try {
      await _tts.stop();
    } catch (_) {}
    notifyListeners();
  }

  /// Cambia la velocidad en caliente. Se aplica al párrafo siguiente porque el
  /// motor no puede reajustar uno ya en curso.
  Future<void> setRate(double rate) async {
    try {
      await _tts.setSpeechRate(rate);
    } catch (_) {}
  }

  @override
  void dispose() {
    _active = false;
    _tts.stop();
    super.dispose();
  }
}
