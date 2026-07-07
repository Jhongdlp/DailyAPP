import 'dart:convert';
import 'package:http/http.dart' as http;

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

  /// Envía una consulta de texto al modelo Qwen Local
  Future<String> askText(String prompt, {String? systemPrompt}) async {
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
        return _askOpenAI(prompt, systemPrompt: systemPrompt);
      }
    } catch (e) {
      // Fallback a OpenAI API style por si falla la estructura Ollama
      try {
        return await _askOpenAI(prompt, systemPrompt: systemPrompt);
      } catch (err) {
        throw Exception('Error al conectar con el servidor local de IA: $err');
      }
    }
  }

  /// Envía una imagen (en Base64) y un prompt al modelo Qwen-VL para verificar la foto de la alarma
  Future<bool> verifyAlarmPhoto(String base64Image, String targetObject) async {
    final prompt = 'Analiza esta imagen y responde únicamente "SÍ" si contiene "$targetObject" (o un equivalente directo/sinónimo, tolerando pequeños errores de escritura o variaciones de nombre como "abamanos" por "lavamanos") de forma clara, o "NO" si no lo contiene. No añadas explicaciones ni más texto.';
    
    try {
      // Intentar API de Ollama para visión (soporta pasar base64 en el campo 'images')
      final url = Uri.parse('$baseUrl/api/chat');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
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
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['message']['content'].toString();
        return _isPositiveResponse(result);
      } else {
        return _verifyAlarmPhotoOpenAI(base64Image, targetObject);
      }
    } catch (e) {
      try {
        return await _verifyAlarmPhotoOpenAI(base64Image, targetObject);
      } catch (err) {
        throw Exception('Error al validar imagen con Qwen-VL local: $err');
      }
    }
  }

  /// Envía una consulta de texto y retorna la respuesta como stream de tokens
  /// (API de Ollama con stream:true, formato NDJSON — una línea JSON por chunk).
  /// Si el streaming falla antes de emitir algo, cae al modo no-streaming
  /// ([askText]) y emite la respuesta completa de una vez.
  Stream<String> askTextStream(String prompt, {String? systemPrompt}) async* {
    var emitted = false;
    try {
      await for (final token in _streamOllama(prompt, systemPrompt: systemPrompt)) {
        emitted = true;
        yield token;
      }
    } catch (e) {
      if (emitted) rethrow;
      // Fallback: respuesta completa sin streaming (incluye fallback OpenAI)
      yield await askText(prompt, systemPrompt: systemPrompt);
    }
  }

  Stream<String> _streamOllama(String prompt, {String? systemPrompt}) async* {
    final client = http.Client();
    try {
      final request = http.Request('POST', Uri.parse('$baseUrl/api/chat'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'model': textModelName,
          'messages': [
            if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
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
  Future<String> _askOpenAI(String prompt, {String? systemPrompt}) async {
    final url = Uri.parse('$baseUrl/v1/chat/completions');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': textModelName,
        'messages': [
          if (systemPrompt != null) {'role': 'system', 'content': systemPrompt},
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
  Future<bool> _verifyAlarmPhotoOpenAI(String base64Image, String targetObject) async {
    final prompt = 'Analiza esta imagen y responde únicamente "SÍ" si contiene "$targetObject" (o un equivalente directo/sinónimo, tolerando pequeños errores de escritura o variaciones de nombre como "abamanos" por "lavamanos") de forma clara, o "NO" si no lo contiene. No añadas explicaciones ni más texto.';
    final url = Uri.parse('$baseUrl/v1/chat/completions');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'model': visionModelName,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'text',
                'text': prompt
              },
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:image/jpeg;base64,$base64Image'
                }
              }
            ]
          }
        ],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final result = data['choices'][0]['message']['content'].toString();
      return _isPositiveResponse(result);
    } else {
      throw Exception('Servidor local OpenAI vision retornó código de error: ${response.statusCode}');
    }
  }

  /// Procesa la respuesta de la IA de forma robusta, eliminando bloques de pensamiento <think>
  /// y realizando coincidencia exacta de palabras para evitar falsos positivos.
  bool _isPositiveResponse(String rawContent) {
    // Eliminar bloque de razonamiento <think>...</think> si existe
    final clean = rawContent.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim().toUpperCase();
    
    if (clean == 'SÍ' || clean == 'SI' || clean == 'YES') {
      return true;
    }
    
    // Dividir por espacios y signos de puntuación comunes para extraer tokens
    final tokens = clean.split(RegExp('[\\s,.\\-!?;():"\'«»]+'));
    return tokens.contains('SÍ') || tokens.contains('SI') || tokens.contains('YES');
  }
}
