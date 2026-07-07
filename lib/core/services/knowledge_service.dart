import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../network/local_ai_client.dart';
import '../providers/settings_provider.dart';
import 'cache_service.dart';

/// Nota relacionada semánticamente (resultado de `related_notes`/`match_notes`).
class RelatedNote {
  final String id;
  final String title;
  final double similarity;

  const RelatedNote({
    required this.id,
    required this.title,
    required this.similarity,
  });

  factory RelatedNote.fromJson(Map<String, dynamic> json) => RelatedNote(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        similarity: (json['similarity'] as num?)?.toDouble() ?? 0,
      );
}

/// Arista semántica del grafo de conocimiento: par de notas similares.
class SemanticEdge {
  final String sourceId;
  final String targetId;
  final double similarity;

  const SemanticEdge({
    required this.sourceId,
    required this.targetId,
    required this.similarity,
  });

  factory SemanticEdge.fromJson(Map<String, dynamic> json) => SemanticEdge(
        sourceId: json['source_id'] as String,
        targetId: json['target_id'] as String,
        similarity: (json['similarity'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'source_id': sourceId,
        'target_id': targetId,
        'similarity': similarity,
      };
}

/// Servicio de la Máquina de Conocimiento: conexiones y búsqueda semántica
/// sobre los embeddings de notas (bge-m3, 1024 dims) almacenados en Supabase.
///
/// Todos los métodos degradan con gracia: si el servidor de IA o Supabase no
/// responden, retornan listas vacías (o el caché local para las aristas) y la
/// UI sigue funcionando solo con los enlaces manuales.
class KnowledgeService {
  // Umbrales calibrados empíricamente con bge-m3: pares realmente
  // relacionados rondan 0.60+, pares no relacionados quedan en ~0.35-0.40.
  static const double edgeThreshold = 0.55;
  static const double relatedThreshold = 0.50;
  static const double searchThreshold = 0.35;

  static final _uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  final LocalAIClient aiClient;

  KnowledgeService({required this.aiClient});

  bool get _hasSession => Supabase.instance.client.auth.currentUser != null;

  /// Notas relacionadas a [noteId] usando su embedding ya almacenado en el
  /// servidor (no requiere el servidor de IA, solo Supabase + pgvector).
  Future<List<RelatedNote>> relatedTo(
    String noteId, {
    double threshold = relatedThreshold,
    int count = 8,
  }) async {
    if (!_hasSession || !_uuidRegex.hasMatch(noteId)) return [];
    try {
      final result = await Supabase.instance.client.rpc('related_notes', params: {
        'p_note_id': noteId,
        'match_threshold': threshold,
        'match_count': count,
      });
      return (result as List)
          .map((e) => RelatedNote.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Aristas semánticas cacheadas localmente (render instantáneo del grafo).
  Future<List<SemanticEdge>> cachedEdges() async {
    try {
      final cached = await CacheService.read('semantic_edges');
      if (cached is List) {
        return cached
            .map((e) => SemanticEdge.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Aristas semánticas frescas desde el servidor; actualiza el caché local.
  Future<List<SemanticEdge>> fetchEdges({
    double threshold = edgeThreshold,
    int maxPairs = 200,
  }) async {
    if (!_hasSession) return [];
    final result = await Supabase.instance.client.rpc('semantic_edges', params: {
      'match_threshold': threshold,
      'max_pairs': maxPairs,
    });
    final edges = (result as List)
        .map((e) => SemanticEdge.fromJson(e as Map<String, dynamic>))
        .toList();
    await CacheService.save(
        'semantic_edges', edges.map((e) => e.toJson()).toList());
    return edges;
  }

  /// Búsqueda semántica: embebe la consulta con bge-m3 y busca las notas más
  /// cercanas por coseno. Retorna vacío si el servidor de IA está caído.
  Future<List<RelatedNote>> semanticSearch(
    String query, {
    double threshold = searchThreshold,
    int count = 12,
    String? excludeId,
  }) async {
    if (!_hasSession || query.trim().isEmpty) return [];
    try {
      final embedding = await aiClient.embed(query);
      final result = await Supabase.instance.client.rpc('match_notes', params: {
        'query_embedding': embedding,
        'match_threshold': threshold,
        'match_count': count,
        if (excludeId != null && _uuidRegex.hasMatch(excludeId))
          'exclude_id': excludeId,
      });
      return (result as List)
          .map((e) => RelatedNote.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

final knowledgeServiceProvider = Provider<KnowledgeService>((ref) {
  final settings = ref.watch(settingsProvider);
  return KnowledgeService(
    aiClient: LocalAIClient(
      baseUrl: settings.localAiUrl,
      embeddingModelName: settings.embeddingModel,
    ),
  );
});
