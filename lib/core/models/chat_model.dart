// Modelos del copiloto financiero: conversaciones con memoria persistente.

class ChatConversation {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChatConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    return ChatConversation(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'Nueva conversación',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  ChatConversation copyWith({String? title, DateTime? updatedAt}) =>
      ChatConversation(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

class ChatMessage {
  final String id;
  final String conversationId;
  final bool isUser;
  String content;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.isUser,
    required this.content,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      isUser: json['role'] == 'user',
      content: (json['content'] as String?) ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  String get role => isUser ? 'user' : 'assistant';

  /// Formato que espera el servidor de IA en el arreglo `messages`.
  Map<String, String> toApiMessage() => {'role': role, 'content': content};
}
