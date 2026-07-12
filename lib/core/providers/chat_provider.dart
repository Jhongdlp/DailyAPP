import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_model.dart';
import '../models/transaction_model.dart';
import '../network/local_ai_client.dart';
import '../services/knowledge_service.dart';
import 'alarms_provider.dart';
import 'finance_provider.dart';
import 'habits_provider.dart';
import 'notes_provider.dart';
import 'settings_provider.dart';

/// Turnos previos que se reenvían al modelo en cada mensaje. Acotado para no
/// desbordar la ventana de contexto ni disparar el tiempo de respuesta.
const int _kHistoryTurns = 20;

/// Persona del copiloto: asesor financiero cuyo sesgo es invertir antes que gastar.
const String kFinanceSystemPrompt = '''
Eres el copiloto financiero personal del usuario dentro de la app SistemDaily.
Eres un experto en finanzas personales, presupuesto e inversión, con criterio propio y directo.

TU FILOSOFÍA (guía todas tus respuestas):
- Cada dólar tiene dos destinos posibles: consumirse o trabajar. Tu sesgo por defecto es que trabaje.
- Antes de recomendar un gasto, buscas la alternativa que lo reduzca, lo elimine o lo convierta en inversión.
- Distingues siempre entre activo (mete dinero al bolsillo) y pasivo (lo saca), y se lo nombras al usuario.
- Priorizas en este orden: 1) eliminar deuda cara, 2) fondo de emergencia (3-6 meses de gastos),
  3) inversión periódica y automática, 4) consumo consciente con lo que sobra.
- Odias los gastos hormiga y las suscripciones muertas: cuando los detectas en sus datos, los señalas con cifras.
- Cuando el usuario quiere comprar algo, le muestras el costo de oportunidad: qué pasaría con ese dinero invertido.

CÓMO RESPONDES:
- En español, tuteando, claro y sin rodeos. Honesto aunque incomode; nada de adulación vacía.
- Concreto y accionable: números, porcentajes y pasos, no generalidades.
- Usas los datos reales del usuario (cuentas, movimientos, hábitos, notas) que se te entregan abajo.
- Si haces una estimación o supuesto, lo dices. No inventas cifras que no tienes.
- Recuerdas y usas lo que ya se habló antes en esta conversación.
- No eres asesor licenciado: en decisiones grandes (deuda, invertir ahorros) recuerdas que la decisión final es suya.

Además del dinero, el usuario te puede preguntar por sus hábitos, notas o alarmas: respóndele igual,
como su coach de confianza, pero sin soltar la mentalidad financiera.
''';

class ChatState {
  final List<ChatConversation> conversations;
  final String? activeId;
  final List<ChatMessage> messages;
  final bool sending;

  const ChatState({
    this.conversations = const [],
    this.activeId,
    this.messages = const [],
    this.sending = false,
  });

  ChatState copyWith({
    List<ChatConversation>? conversations,
    String? activeId,
    bool clearActive = false,
    List<ChatMessage>? messages,
    bool? sending,
  }) {
    return ChatState(
      conversations: conversations ?? this.conversations,
      activeId: clearActive ? null : (activeId ?? this.activeId),
      messages: messages ?? this.messages,
      sending: sending ?? this.sending,
    );
  }
}

class ChatNotifier extends AsyncNotifier<ChatState> {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<ChatState> build() async {
    final user = _db.auth.currentUser;
    if (user == null) return const ChatState();

    final data = await _db
        .from('chat_conversations')
        .select()
        .order('updated_at', ascending: false);

    final conversations =
        (data as List).map((e) => ChatConversation.fromJson(e)).toList();

    if (conversations.isEmpty) return const ChatState();

    final activeId = conversations.first.id;
    return ChatState(
      conversations: conversations,
      activeId: activeId,
      messages: await _fetchMessages(activeId),
    );
  }

  ChatState get _current => state.value ?? const ChatState();

  Future<List<ChatMessage>> _fetchMessages(String conversationId) async {
    final data = await _db
        .from('chat_messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at');
    return (data as List).map((e) => ChatMessage.fromJson(e)).toList();
  }

  /// Abre una conversación existente y carga su historial.
  Future<void> selectConversation(String id) async {
    if (_current.activeId == id) return;
    state = AsyncData(_current.copyWith(activeId: id, messages: const []));
    final messages = await _fetchMessages(id);
    state = AsyncData(_current.copyWith(activeId: id, messages: messages));
  }

  /// Prepara un chat nuevo. La fila en la BD se crea al enviar el primer
  /// mensaje, para no dejar conversaciones vacías si el usuario se arrepiente.
  void newConversation() {
    state = AsyncData(
      _current.copyWith(clearActive: true, messages: const []),
    );
  }

  Future<void> deleteConversation(String id) async {
    await _db.from('chat_conversations').delete().eq('id', id);
    final remaining =
        _current.conversations.where((c) => c.id != id).toList();

    if (_current.activeId != id) {
      state = AsyncData(_current.copyWith(conversations: remaining));
      return;
    }

    if (remaining.isEmpty) {
      state = AsyncData(ChatState(conversations: remaining));
      return;
    }

    final nextId = remaining.first.id;
    state = AsyncData(ChatState(
      conversations: remaining,
      activeId: nextId,
      messages: await _fetchMessages(nextId),
    ));
  }

  Future<void> renameConversation(String id, String title) async {
    final clean = title.trim();
    if (clean.isEmpty) return;
    await _db.from('chat_conversations').update({'title': clean}).eq('id', id);
    state = AsyncData(_current.copyWith(
      conversations: [
        for (final c in _current.conversations)
          if (c.id == id) c.copyWith(title: clean) else c,
      ],
    ));
  }

  Future<ChatConversation> _createConversation(String firstMessage) async {
    final user = _db.auth.currentUser!;
    final data = await _db
        .from('chat_conversations')
        .insert({'user_id': user.id, 'title': _titleFrom(firstMessage)})
        .select()
        .single();

    final conversation = ChatConversation.fromJson(data);
    state = AsyncData(_current.copyWith(
      conversations: [conversation, ..._current.conversations],
      activeId: conversation.id,
    ));
    return conversation;
  }

  String _titleFrom(String message) {
    final oneLine = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= 42) return oneLine;
    return '${oneLine.substring(0, 42).trimRight()}…';
  }

  Future<ChatMessage> _insertMessage(
    String conversationId,
    String role,
    String content,
  ) async {
    final user = _db.auth.currentUser!;
    final data = await _db
        .from('chat_messages')
        .insert({
          'user_id': user.id,
          'conversation_id': conversationId,
          'role': role,
          'content': content,
        })
        .select()
        .single();
    return ChatMessage.fromJson(data);
  }

  /// Mueve la conversación al tope de la lista y refresca su `updated_at`.
  Future<void> _touch(String conversationId) async {
    final now = DateTime.now().toUtc();
    await _db
        .from('chat_conversations')
        .update({'updated_at': now.toIso8601String()})
        .eq('id', conversationId);

    final list = [..._current.conversations];
    final idx = list.indexWhere((c) => c.id == conversationId);
    if (idx == -1) return;
    final updated = list.removeAt(idx).copyWith(updatedAt: now);
    state = AsyncData(_current.copyWith(conversations: [updated, ...list]));
  }

  /// Envía el mensaje del usuario y transmite la respuesta token a token.
  /// Crea la conversación si aún no existe, guarda ambos turnos en la BD y
  /// reenvía el historial previo al modelo (esa es su memoria).
  Future<void> sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty || _current.sending) return;

    final conversationId =
        _current.activeId ?? (await _createConversation(query)).id;

    // Historial ANTES de añadir el mensaje actual (que va aparte en el prompt).
    final history = _current.messages
        .where((m) => m.content.trim().isNotEmpty)
        .toList()
        .reversed
        .take(_kHistoryTurns)
        .toList()
        .reversed
        .map((m) => m.toApiMessage())
        .toList();

    final userMessage = await _insertMessage(conversationId, 'user', query);
    state = AsyncData(_current.copyWith(
      messages: [..._current.messages, userMessage],
      sending: true,
    ));

    // Burbuja del asistente que se rellena token a token; se persiste al final.
    final reply = ChatMessage(
      id: 'streaming-${DateTime.now().millisecondsSinceEpoch}',
      conversationId: conversationId,
      isUser: false,
      content: '',
      createdAt: DateTime.now(),
    );
    state = AsyncData(_current.copyWith(messages: [..._current.messages, reply]));

    try {
      final settings = ref.read(settingsProvider);
      final client = LocalAIClient(
        baseUrl: settings.localAiUrl,
        textModelName: settings.textModel,
      );
      final systemPrompt = await _buildSystemPrompt(query);

      await for (final token in client.askTextStream(
        query,
        systemPrompt: systemPrompt,
        history: history,
      )) {
        reply.content += token;
        // Lista nueva para que Riverpod notifique a los oyentes.
        state = AsyncData(_current.copyWith(messages: [..._current.messages]));
      }

      if (reply.content.trim().isEmpty) {
        reply.content = 'El servidor de IA no devolvió respuesta.';
      }

      final saved =
          await _insertMessage(conversationId, 'assistant', reply.content);
      state = AsyncData(_current.copyWith(
        messages: [
          for (final m in _current.messages)
            if (m.id == reply.id) saved else m,
        ],
      ));
      await _touch(conversationId);
    } catch (e) {
      // El turno del asistente no se guarda en la BD si falló: así el historial
      // que se reenvía al modelo no queda contaminado con mensajes de error.
      reply.content =
          'Error de conexión con el Servidor IA Local. Asegúrate de tener Ollama o tu servidor encendido.\nDetalles: $e';
      state = AsyncData(_current.copyWith(messages: [..._current.messages]));
    } finally {
      state = AsyncData(_current.copyWith(sending: false));
    }
  }

  /// Contexto del sistema: la persona financiera + los datos reales del usuario
  /// (notas relevantes por RAG, hábitos, finanzas y alarmas).
  Future<String> _buildSystemPrompt(String query) async {
    final habits = ref.read(habitsProvider);
    final notes = ref.read(notesProvider);
    final accounts = ref.read(accountsProvider).value ?? [];
    final balances = ref.read(accountBalancesProvider);
    final monthSummary = ref.read(monthSummaryProvider);
    final transactions = ref.read(transactionsProvider).value ?? [];
    final alarms = ref.read(alarmsProvider).value ?? [];

    final buffer = StringBuffer(kFinanceSystemPrompt);
    buffer.writeln();
    buffer.writeln('INFORMACIÓN ACTUAL DEL USUARIO:');

    // ── Finanzas (lo primero: es tu especialidad) ──
    buffer.writeln('---');
    if (accounts.isEmpty) {
      buffer.writeln(
          'FINANZAS: el usuario aún no ha registrado cuentas en la app. '
          'Si la consulta es financiera, anímalo a registrarlas para darle cifras reales.');
    } else {
      buffer.writeln('FINANZAS (USD):');
      var total = 0.0;
      for (final a in accounts) {
        final balance = balances[a.id] ?? a.initialBalance;
        total += balance;
        buffer.writeln('- Cuenta "${a.name}": \$${balance.toStringAsFixed(2)}');
      }
      buffer.writeln('Patrimonio en cuentas: \$${total.toStringAsFixed(2)}.');
      buffer.writeln(
          'Este mes: ingresos \$${monthSummary.income.toStringAsFixed(2)}, '
          'gastos \$${monthSummary.expense.toStringAsFixed(2)}, '
          'balance \$${(monthSummary.income - monthSummary.expense).toStringAsFixed(2)}.');

      // Gasto acumulado por categoría del mes: base para detectar fugas.
      final now = DateTime.now();
      final byCategory = <String, double>{};
      for (final t in transactions) {
        if (t.type != TransactionType.expense) continue;
        if (t.occurredAt.year != now.year || t.occurredAt.month != now.month) {
          continue;
        }
        byCategory.update(t.categoryInfo.label, (v) => v + t.amount,
            ifAbsent: () => t.amount);
      }
      if (byCategory.isNotEmpty) {
        final sorted = byCategory.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        buffer.writeln('Gastos del mes por categoría:');
        for (final e in sorted) {
          buffer.writeln('- ${e.key}: \$${e.value.toStringAsFixed(2)}');
        }
      }
      if (transactions.isNotEmpty) {
        buffer.writeln('Últimos movimientos:');
        for (final t in transactions.take(15)) {
          buffer.writeln(
              '- ${t.occurredAt.toIso8601String().substring(0, 10)} ${t.type.label} '
              '\$${t.amount.toStringAsFixed(2)} (${t.categoryInfo.label})'
              '${t.description.isNotEmpty ? ': ${t.description}' : ''}');
        }
      }
    }

    // ── Notas relevantes (RAG semántico) ──
    buffer.writeln('---');
    buffer.writeln('NOTAS RELEVANTES A LA CONSULTA (segundo cerebro):');
    try {
      final related =
          await ref.read(knowledgeServiceProvider).semanticSearch(query, count: 5);
      if (related.isNotEmpty) {
        for (final r in related) {
          // El contenido completo vive en el estado local de notas
          final note = notes.where((n) => n.id == r.id).firstOrNull;
          final content = note?.content ?? '';
          buffer.writeln(
              '- "${r.title}": ${content.length > 600 ? '${content.substring(0, 600)}…' : content}');
        }
      } else {
        buffer.writeln(
            'Sin coincidencias directas. Títulos de las notas del usuario: '
            '${notes.take(20).map((n) => '"${n.title}"').join(', ')}.');
      }
    } catch (_) {
      // Servidor de embeddings caído: seguimos sin notas antes que fallar el chat.
      buffer.writeln(
          'No disponible ahora mismo. Títulos de las notas del usuario: '
          '${notes.take(20).map((n) => '"${n.title}"').join(', ')}.');
    }

    // ── Hábitos ──
    if (habits.isNotEmpty) {
      buffer.writeln('---');
      buffer.writeln('HÁBITOS:');
      for (final h in habits) {
        buffer.writeln(
          '- "${h.name}" (${h.category.label}). Racha: ${h.currentStreak()} días. '
          'Cumplimiento 30 días: ${(h.completionRate(days: 30) * 100).round()}%.',
        );
      }
    }

    // ── Alarmas ──
    final active = alarms.where((a) => a.enabled).toList();
    if (active.isNotEmpty) {
      buffer.writeln('---');
      buffer.writeln('ALARMAS ACTIVAS:');
      for (final a in active) {
        buffer.writeln(
            '- ${a.formattedTime}${a.label.isNotEmpty ? ' "${a.label}"' : ''} (${a.daysLabel})');
      }
    }

    buffer.writeln('---');
    buffer.writeln(
        'Responde el último mensaje del usuario apoyándote en esta información y en lo ya hablado '
        'en la conversación. No digas "según los datos entregados" salvo que aporte. Responde en español.');
    return buffer.toString();
  }
}

final chatProvider =
    AsyncNotifierProvider<ChatNotifier, ChatState>(ChatNotifier.new);
