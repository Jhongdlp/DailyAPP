import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Resultado de mirar una foto con el modelo de visión.
///
/// Hace falta el tercer estado: si el modelo se corta a media frase, se va por
/// las ramas o el servidor devuelve basura, tratarlo como un "NO" acusaba al
/// usuario de no haber fotografiado el objeto cuando el fallo era nuestro.
enum PhotoVerdict { yes, no, unclear }

/// El servidor de IA no está disponible (caído, fuera de la red, o tardando
/// más de lo que se puede esperar con una alarma sonando).
class AiUnavailableException implements Exception {
  final String message;
  const AiUnavailableException(this.message);

  @override
  String toString() => message;
}

/// Cliente para la integración con el Servidor IA Local que ejecuta modelos Qwen.
/// Soporta procesamiento de texto y análisis visual con Qwen-VL.
class LocalAIClient {
  // Dirección IP por defecto para conectarse al host local desde Android Emulator (10.0.2.2)
  // o localhost para iOS y Web/Escritorio.
  static String defaultBaseUrl = 'http://10.0.2.2:11434'; // Ollama por defecto
  
  final String baseUrl;
  final String textModelName;
  final String visionModelName;
  final String embeddingModelName;

  LocalAIClient({
    this.baseUrl = 'http://10.0.2.2:11434', // Cambiar según el host (ej. IP de la red local)
    this.textModelName = 'qwen2.5:7b',
    this.visionModelName = 'qwen2-vl:7b',
    this.embeddingModelName = 'bge-m3:latest',
  });

  /// Verifica si el servidor local de IA está activo
  Future<bool> checkHealth() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/')).timeout(
        const Duration(seconds: 3),
      );
      return response.statusCode == 200;
    } catch (_) {
      try {
        // En algunos servidores de estilo OpenAI el endpoint base es diferente, intentamos v1/models
        final response = await http.get(Uri.parse('$baseUrl/v1/models')).timeout(
          const Duration(seconds: 3),
        );
        return response.statusCode == 200;
      } catch (_) {
        return false;
      }
    }
  }

  /// Envía una consulta de texto al modelo Qwen Local.
  /// [history] son los turnos previos de la conversación (`role`/`content`),
  /// que se envían antes del mensaje actual para dar memoria al modelo.
  Future<String> askText(
    String prompt, {
    String? systemPrompt,
    List<Map<String, String>> history = const [],
  }) async {
    try {
      // Intentar primero con el API de Ollama
      final url = Uri.parse('$baseUrl/api/chat');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': textModelName,
          'messages': [
            if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
            ...history,
            {'role': 'user', 'content': prompt}
          ],
          'stream': false,
          // Mantiene el modelo cargado en memoria del servidor para evitar
          // el retraso de recarga (varios segundos/minutos) en cada mensaje.
          'keep_alive': '30m',
          'options': {
            // Límite de tokens de salida para acotar el tiempo de respuesta.
            'num_predict': 500,
          },
        }),
      ).timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw Exception(
          'El servidor de IA tardó demasiado en responder (más de 90s).',
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['message']['content'].toString().trim();
      } else {
        // Si no es Ollama, intentamos API compatible con OpenAI
        return _askOpenAI(prompt, systemPrompt: systemPrompt, history: history);
      }
    } catch (e) {
      // Fallback a OpenAI API style por si falla la estructura Ollama
      try {
        return await _askOpenAI(prompt, systemPrompt: systemPrompt, history: history);
      } catch (err) {
        throw Exception('Error al conectar con el servidor local de IA: $err');
      }
    }
  }

  /// Cuánto mantiene Ollama el modelo de visión cargado tras usarlo.
  ///
  /// El valor por defecto del servidor son 5 minutos: con una alarma diaria,
  /// eso garantiza que TODAS las mañanas la primera foto pague la carga entera
  /// de los 8B de pesos desde disco antes de mirar siquiera la imagen.
  static const visionKeepAlive = '30m';

  static const _jsonHeaders = {'Content-Type': 'application/json'};

  String _alarmPhotoPrompt(String targetObject) =>
      'Analiza esta imagen y responde únicamente "SÍ" si contiene "$targetObject" (o un equivalente directo/sinónimo, tolerando pequeños errores de escritura o variaciones de nombre como "abamanos" por "lavamanos") de forma clara, o "NO" si no lo contiene. No añadas explicaciones ni más texto.';

  /// Deja el modelo de visión cargado en memoria del servidor.
  ///
  /// Se lanza en cuanto se abre la pantalla de la alarma, para que la carga del
  /// modelo ocurra mientras el usuario se levanta y camina hasta el objeto en
  /// lugar de después de disparar la foto. Devuelve `false` si el servidor no
  /// contesta, que es la señal para ofrecer directamente el reto mental.
  ///
  /// Una petición con `messages` vacío es la forma documentada de pedirle a
  /// Ollama que cargue un modelo sin generar nada.
  Future<bool> warmUpVision({
    Duration timeout = const Duration(seconds: 90),
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/chat'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'model': visionModelName,
              'messages': const [],
              'stream': false,
              'keep_alive': visionKeepAlive,
            }),
          )
          .timeout(timeout);
      return response.statusCode == 200;
    } catch (_) {
      // Puede ser un servidor estilo OpenAI, que no tiene precarga: basta con
      // saber que está vivo.
      try {
        final response = await http
            .get(Uri.parse('$baseUrl/v1/models'))
            .timeout(const Duration(seconds: 8));
        return response.statusCode == 200;
      } catch (_) {
        return false;
      }
    }
  }

  /// Envía una imagen (en Base64) al modelo de visión y decide si contiene
  /// [targetObject].
  ///
  /// Lanza [AiUnavailableException] si el servidor no responde dentro de
  /// [timeout]: con una alarma sonando, quedarse esperando indefinidamente (lo
  /// que hacía la versión anterior, sin ningún tope) es el peor final posible.
  Future<PhotoVerdict> verifyAlarmPhoto(
    String base64Image,
    String targetObject, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final prompt = _alarmPhotoPrompt(targetObject);
    final url = Uri.parse('$baseUrl/api/chat');

    Map<String, dynamic> payload({required bool withThinkFlag}) => {
          'model': visionModelName,
          'messages': [
            {
              'role': 'user',
              'content': prompt,
              'images': [base64Image]
            }
          ],
          'stream': false,
          'keep_alive': visionKeepAlive,
          // qwen3-vl razona por defecto: escupía cientos de tokens de <think>
          // antes del "SÍ"/"NO" final. Eso, y no el análisis de la imagen, es
          // lo que hacía eterna la espera.
          if (withThinkFlag) 'think': false,
          'options': {
            'temperature': 0,
            // Red de seguridad por si el servidor ignora `think`: la respuesta
            // útil son 1-2 tokens, esto solo acota el peor caso.
            'num_predict': 200,
          },
        };

    http.Response response;
    try {
      response = await http
          .post(url,
              headers: _jsonHeaders,
              body: jsonEncode(payload(withThinkFlag: true)))
          .timeout(timeout);
      // Ollama antiguo (o un modelo sin razonamiento) rechaza el campo `think`.
      if (response.statusCode == 400) {
        response = await http
            .post(url,
                headers: _jsonHeaders,
                body: jsonEncode(payload(withThinkFlag: false)))
            .timeout(timeout);
      }
    } on TimeoutException {
      // Deliberadamente NO se reintenta con el endpoint OpenAI: sería pagar el
      // timeout dos veces seguidas con la alarma sonando.
      throw AiUnavailableException(
        'El servidor de IA no respondió en ${timeout.inSeconds}s.',
      );
    } catch (_) {
      // Fallo de conexión o estructura: puede que no sea Ollama.
      return _verifyAlarmPhotoOpenAI(base64Image, targetObject, timeout);
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return readVerdict(data['message']?['content']?.toString() ?? '');
    }
    return _verifyAlarmPhotoOpenAI(base64Image, targetObject, timeout);
  }

  /// Clasifica una foto de progreso físico como "cara" o "cuerpo" con Qwen-VL.
  /// Se usa en background tras subir la foto: nunca bloquea el flujo de
  /// captura, así que un resultado 'unknown' (respuesta ambigua) es preferible
  /// a lanzar y dejar la foto sin clasificar para siempre.
  Future<String> classifyExercisePhoto(String base64Image) async {
    const prompt = 'Analiza esta imagen de una persona haciendo seguimiento de su progreso físico. '
        'Responde únicamente con una palabra: "CARA" si la imagen es principalmente un retrato/selfie de rostro, '
        '"CUERPO" si es una foto de cuerpo completo o torso para ver progreso físico, '
        'u "OTRO" si no aplica ninguna de las dos. No añadas explicaciones ni más texto.';

    try {
      final url = Uri.parse('$baseUrl/api/chat');
      final response = await http
          .post(
            url,
            headers: _jsonHeaders,
            body: jsonEncode({
              'model': visionModelName,
              'messages': [
                {
                  'role': 'user',
                  'content': prompt,
                  'images': [base64Image]
                }
              ],
              'stream': false,
              'keep_alive': visionKeepAlive,
              'think': false,
              'options': {'temperature': 0, 'num_predict': 200},
            }),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['message']['content'].toString();
        return _extractClassificationLabel(result);
      } else {
        return _classifyExercisePhotoOpenAI(base64Image);
      }
    } catch (e) {
      try {
        return await _classifyExercisePhotoOpenAI(base64Image);
      } catch (err) {
        throw Exception('Error al clasificar imagen con Qwen-VL local: $err');
      }
    }
  }

  /// Método auxiliar de clasificación para servidores tipo OpenAI
  Future<String> _classifyExercisePhotoOpenAI(String base64Image) async {
    const prompt = 'Analiza esta imagen de una persona haciendo seguimiento de su progreso físico. '
        'Responde únicamente con una palabra: "CARA" si la imagen es principalmente un retrato/selfie de rostro, '
        '"CUERPO" si es una foto de cuerpo completo o torso para ver progreso físico, '
        'u "OTRO" si no aplica ninguna de las dos. No añadas explicaciones ni más texto.';
    final url = Uri.parse('$baseUrl/v1/chat/completions');
    final response = await http
        .post(
          url,
          headers: _jsonHeaders,
          body: jsonEncode({
            'model': visionModelName,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': prompt},
                  {
                    'type': 'image_url',
                    'image_url': {'url': 'data:image/jpeg;base64,$base64Image'}
                  }
                ]
              }
            ],
            'max_tokens': 200,
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final result = data['choices'][0]['message']['content'].toString();
      return _extractClassificationLabel(result);
    } else {
      throw Exception('Servidor local OpenAI vision retornó código de error: ${response.statusCode}');
    }
  }

  /// Extrae 'cara'/'cuerpo'/'unknown' de la respuesta cruda del modelo, con el
  /// mismo strip de `<think>` y tokenización usados en [readVerdict].
  String _extractClassificationLabel(String rawContent) {
    final clean = rawContent.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim().toUpperCase();
    final tokens = clean.split(RegExp('[\\s,.\\-!?;():"\'«»]+'));

    if (clean == 'CARA' || tokens.contains('CARA')) return 'cara';
    if (clean == 'CUERPO' || tokens.contains('CUERPO')) return 'cuerpo';
    return 'unknown';
  }

  /// Envía una consulta de texto y retorna la respuesta como stream de tokens
  /// (API de Ollama con stream:true, formato NDJSON — una línea JSON por chunk).
  /// Si el streaming falla antes de emitir algo, cae al modo no-streaming
  /// ([askText]) y emite la respuesta completa de una vez.
  Stream<String> askTextStream(
    String prompt, {
    String? systemPrompt,
    List<Map<String, String>> history = const [],
  }) async* {
    var emitted = false;
    try {
      await for (final token
          in _streamOllama(prompt, systemPrompt: systemPrompt, history: history)) {
        emitted = true;
        yield token;
      }
    } catch (e) {
      if (emitted) rethrow;
      // Fallback: respuesta completa sin streaming (incluye fallback OpenAI)
      yield await askText(prompt, systemPrompt: systemPrompt, history: history);
    }
  }

  Stream<String> _streamOllama(
    String prompt, {
    String? systemPrompt,
    List<Map<String, String>> history = const [],
  }) async* {
    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse('$baseUrl/api/chat'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'model': textModelName,
          'messages': [
            if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
            ...history,
            {'role': 'user', 'content': prompt}
          ],
          'stream': true,
          'keep_alive': '30m',
          'options': {'num_predict': 600},
        });

      final response = await client.send(request).timeout(
            const Duration(seconds: 30),
            onTimeout: () =>
                throw Exception('El servidor de IA no respondió (30s).'),
          );

      if (response.statusCode != 200) {
        throw Exception('Servidor retornó código: ${response.statusCode}');
      }

      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final data = jsonDecode(line);
        final content = data['message']?['content'];
        if (content is String && content.isNotEmpty) yield content;
        if (data['done'] == true) break;
      }
    } finally {
      client.close();
    }
  }

  /// Genera el embedding de un texto con el modelo de embeddings local (bge-m3).
  /// Retorna un vector de 1024 dimensiones.
  Future<List<double>> embed(String text) async {
    final vectors = await embedBatch([text]);
    return vectors.first;
  }

  /// Genera embeddings para varios textos en una sola llamada.
  /// Intenta primero el API de Ollama (/api/embed) y cae a estilo OpenAI
  /// (/v1/embeddings) si el servidor no lo soporta.
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (texts.isEmpty) return [];
    try {
      final url = Uri.parse('$baseUrl/api/embed');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'model': embeddingModelName,
              'input': texts,
              // Mantener el modelo de embeddings cargado en memoria del servidor
              'keep_alive': '30m',
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final embeddings = data['embeddings'] as List;
        return embeddings
            .map((e) => (e as List).map((v) => (v as num).toDouble()).toList())
            .toList();
      }
      return _embedBatchOpenAI(texts);
    } catch (_) {
      try {
        return await _embedBatchOpenAI(texts);
      } catch (err) {
        throw Exception('Error al generar embeddings con el servidor local: $err');
      }
    }
  }

  /// Método auxiliar de embeddings para servidores tipo OpenAI (LM Studio, vLLM)
  Future<List<List<double>>> _embedBatchOpenAI(List<String> texts) async {
    final url = Uri.parse('$baseUrl/v1/embeddings');
    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'model': embeddingModelName, 'input': texts}),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final items = data['data'] as List;
      return items
          .map((e) => ((e as Map)['embedding'] as List)
              .map((v) => (v as num).toDouble())
              .toList())
          .toList();
    }
    throw Exception('Servidor de embeddings retornó código: ${response.statusCode}');
  }

  /// Método auxiliar para servidores tipo OpenAI (LM Studio, LocalAI, vLLM)
  Future<String> _askOpenAI(
    String prompt, {
    String? systemPrompt,
    List<Map<String, String>> history = const [],
  }) async {
    final url = Uri.parse('$baseUrl/v1/chat/completions');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': textModelName,
        'messages': [
          if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
          ...history,
          {'role': 'user', 'content': prompt}
        ],
        'max_tokens': 500,
      }),
    ).timeout(
      const Duration(seconds: 90),
      onTimeout: () => throw Exception(
        'El servidor de IA tardó demasiado en responder (más de 90s).',
      ),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices'][0]['message']['content'].toString().trim();
    } else {
      throw Exception('Servidor local retornó código de error: ${response.statusCode}');
    }
  }

  /// Método auxiliar de validación de imágenes para servidores tipo OpenAI
  Future<PhotoVerdict> _verifyAlarmPhotoOpenAI(
    String base64Image,
    String targetObject,
    Duration timeout,
  ) async {
    final url = Uri.parse('$baseUrl/v1/chat/completions');
    final http.Response response;
    try {
      response = await http
          .post(
            url,
            headers: _jsonHeaders,
            body: jsonEncode({
              'model': visionModelName,
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {'type': 'text', 'text': _alarmPhotoPrompt(targetObject)},
                    {
                      'type': 'image_url',
                      'image_url': {'url': 'data:image/jpeg;base64,$base64Image'}
                    }
                  ]
                }
              ],
              'temperature': 0,
              'max_tokens': 200,
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw AiUnavailableException(
        'El servidor de IA no respondió en ${timeout.inSeconds}s.',
      );
    } catch (e) {
      throw AiUnavailableException('No pude contactar con el servidor de IA.');
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return readVerdict(
        data['choices']?[0]?['message']?['content']?.toString() ?? '',
      );
    }
    throw AiUnavailableException(
      'El servidor de IA respondió con el código ${response.statusCode}.',
    );
  }

  /// Traduce la respuesta cruda del modelo a un veredicto, quitando los bloques
  /// de razonamiento y decidiendo por la PRIMERA palabra reconocible: si el
  /// modelo se explaya ("NO, no hay ningún lavamanos, sí veo una mesa"), lo que
  /// vale es su veredicto, no si en algún punto aparece un "sí".
  @visibleForTesting
  PhotoVerdict readVerdict(String rawContent) {
    final clean = rawContent
        .replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '')
        // Un <think> sin cerrar significa respuesta cortada por num_predict:
        // no llegó a haber veredicto.
        .replaceAll(RegExp(r'<think>[\s\S]*'), '')
        .trim()
        .toUpperCase();
    if (clean.isEmpty) return PhotoVerdict.unclear;

    final tokens = clean
        .split(RegExp('[\\s,.\\-!?;():"\'«»]+'))
        .where((t) => t.isNotEmpty);
    for (final token in tokens) {
      if (token == 'SÍ' || token == 'SI' || token == 'YES') {
        return PhotoVerdict.yes;
      }
      if (token == 'NO' || token == 'NOT') return PhotoVerdict.no;
    }
    return PhotoVerdict.unclear;
  }
}
