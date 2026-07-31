/// Digest de noticias generado cada mañana por una routine (agente programado
/// en la nube) que busca, filtra y resume en español.
///
/// El agente corre fuera de la app y no tiene credenciales de Supabase, así
/// que publica el resultado como `news/YYYY-MM-DD.json` en el repo y la app lo
/// lee por HTTP. Este archivo define el contrato entre ambos lados: si cambia
/// una clave aquí, hay que cambiar el prompt de la routine.
library;

enum NewsCategory {
  ia('IA & LLMs'),
  dev('Dev'),
  startups('Startups'),
  papers('Papers');

  const NewsCategory(this.label);

  final String label;

  static NewsCategory fromJson(String? raw) {
    return switch (raw?.toLowerCase().trim()) {
      'dev' || 'programacion' || 'programación' => NewsCategory.dev,
      'startups' || 'negocio' || 'business' => NewsCategory.startups,
      'papers' || 'research' || 'investigacion' => NewsCategory.papers,
      _ => NewsCategory.ia,
    };
  }
}

class NewsItem {
  final String title;
  final String summary;
  final String source;
  final String url;
  final NewsCategory category;

  /// 0-10. El agente la asigna; ordena el digest y decide qué entra en portada.
  final int relevance;

  const NewsItem({
    required this.title,
    required this.summary,
    required this.source,
    required this.url,
    required this.category,
    required this.relevance,
  });

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    return NewsItem(
      title: (json['title'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      category: NewsCategory.fromJson(json['category'] as String?),
      // El modelo a veces devuelve la relevancia como número y a veces como
      // texto; se normaliza aquí en vez de confiar en un cast.
      relevance: switch (json['relevance']) {
        final int v => v,
        final double v => v.round(),
        final String v => int.tryParse(v) ?? 0,
        _ => 0,
      }
          .clamp(0, 10),
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'summary': summary,
        'source': source,
        'url': url,
        'category': category.name,
        'relevance': relevance,
      };
}

class NewsDigest {
  final DateTime date;

  /// Párrafo de apertura: qué es lo importante del día.
  final String editorial;

  final List<NewsItem> items;

  const NewsDigest({
    required this.date,
    required this.editorial,
    required this.items,
  });

  factory NewsDigest.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = <NewsItem>[
      if (rawItems is List)
        for (final entry in rawItems)
          if (entry is Map<String, dynamic>) NewsItem.fromJson(entry),
    ]..sort((a, b) => b.relevance.compareTo(a.relevance));

    return NewsDigest(
      date: DateTime.tryParse((json['date'] ?? '').toString()) ?? DateTime.now(),
      editorial: (json['editorial'] ?? '').toString(),
      items: items,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String().split('T').first,
        'editorial': editorial,
        'items': [for (final item in items) item.toJson()],
      };

  List<NewsItem> byCategory(NewsCategory category) =>
      [for (final item in items) if (item.category == category) item];

  /// Categorías que realmente traen noticias hoy — el digest no siempre cubre
  /// las cuatro, y una sección vacía en el PDF se lee como un error.
  List<NewsCategory> get activeCategories => [
        for (final category in NewsCategory.values)
          if (byCategory(category).isNotEmpty) category,
      ];

  bool get isEmpty => items.isEmpty;
}
