import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/network/local_ai_client.dart';
import '../../core/services/knowledge_service.dart';
import '../habits/widgets/habit_blob_header.dart';
import '../notes/notes_tab.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/providers/finance_provider.dart';
import '../../core/providers/alarms_provider.dart';

class ChatMessage {
  final String id;
  String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class ChatTab extends ConsumerStatefulWidget {
  const ChatTab({super.key});

  @override
  ConsumerState<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends ConsumerState<ChatTab> {
  final List<ChatMessage> _messages = [
    ChatMessage(
      id: '1',
      text: '¡Hola! Soy tu asistente de SistemDaily. ¿En qué te puedo ayudar hoy? Tengo acceso a tus notas y hábitos de la semana para darte la mejor asesoría.',
      isUser: false,
      timestamp: DateTime.now(),
    ),
  ];

  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _loading = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Construye el contexto del sistema: notas recuperadas por RAG (solo las
  /// relevantes a la consulta, no todas) + resúmenes compactos de hábitos,
  /// finanzas y alarmas.
  Future<String> _buildSystemPrompt(String query) async {
    final habits = ref.read(habitsProvider);
    final notes = ref.read(notesProvider);
    final accounts = ref.read(accountsProvider).value ?? [];
    final balances = ref.read(accountBalancesProvider);
    final monthSummary = ref.read(monthSummaryProvider);
    final transactions = ref.read(transactionsProvider).value ?? [];
    final alarms = ref.read(alarmsProvider).value ?? [];

    final buffer = StringBuffer();
    buffer.writeln('INFORMACIÓN ACTUAL DEL USUARIO:');

    // ── Notas relevantes (RAG semántico) ──
    buffer.writeln('---');
    buffer.writeln('NOTAS RELEVANTES A LA CONSULTA (segundo cerebro):');
    final related = await ref
        .read(knowledgeServiceProvider)
        .semanticSearch(query, count: 5);
    if (related.isNotEmpty) {
      for (final r in related) {
        // El contenido completo vive en el estado local de notas
        final note = notes.where((n) => n.id == r.id).firstOrNull;
        final content = note?.content ?? '';
        buffer.writeln(
            '- "${r.title}": ${content.length > 600 ? '${content.substring(0, 600)}…' : content}');
      }
    } else {
      // Fallback (servidor de embeddings caído o sin resultados): solo títulos
      buffer.writeln(
          'Sin coincidencias directas. Títulos de las notas del usuario: '
          '${notes.take(20).map((n) => '"${n.title}"').join(', ')}.');
    }

    // ── Hábitos ──
    buffer.writeln('---');
    buffer.writeln('HÁBITOS:');
    for (final h in habits) {
      buffer.writeln(
        '- "${h.name}" (${h.category.label}). Racha: ${h.currentStreak()} días. '
        'Cumplimiento 30 días: ${(h.completionRate(days: 30) * 100).round()}%.',
      );
    }

    // ── Finanzas ──
    if (accounts.isNotEmpty) {
      buffer.writeln('---');
      buffer.writeln('FINANZAS (USD):');
      for (final a in accounts) {
        final balance = balances[a.id] ?? a.initialBalance;
        buffer.writeln('- Cuenta "${a.name}": \$${balance.toStringAsFixed(2)}');
      }
      buffer.writeln(
          'Este mes: ingresos \$${monthSummary.income.toStringAsFixed(2)}, '
          'gastos \$${monthSummary.expense.toStringAsFixed(2)}.');
      if (transactions.isNotEmpty) {
        buffer.writeln('Últimos movimientos:');
        for (final t in transactions.take(10)) {
          buffer.writeln(
              '- ${t.type.name} \$${t.amount.toStringAsFixed(2)} (${t.category})'
              '${t.description.isNotEmpty ? ': ${t.description}' : ''}');
        }
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
        'Responde la consulta del usuario usando de base esta información. '
        'No menciones explícitamente "según los datos entregados" a menos que sea necesario. '
        'Sé amigable, directo, y actúa como su coach de vida de confianza. Responde en español.');
    return buffer.toString();
  }

  Future<void> _sendMessage() async {
    final query = _textController.text.trim();
    if (query.isEmpty || _loading) return;

    _textController.clear();
    setState(() {
      _messages.add(ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: query,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _loading = true;
    });
    _scrollToBottom();

    try {
      final settings = ref.read(settingsProvider);
      final systemPrompt = await _buildSystemPrompt(query);

      final client = LocalAIClient(
        baseUrl: settings.localAiUrl,
        textModelName: settings.textModel,
      );

      // Mensaje del asistente vacío que se rellena token a token (streaming)
      final reply = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
      );
      if (mounted) setState(() => _messages.add(reply));

      await for (final token
          in client.askTextStream(query, systemPrompt: systemPrompt)) {
        if (!mounted) return;
        setState(() => reply.text += token);
        _scrollToBottom();
      }

      if (mounted && reply.text.trim().isEmpty) {
        setState(() => reply.text = 'El servidor de IA no devolvió respuesta.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // Retirar el mensaje vacío del asistente si el stream falló sin emitir
          if (_messages.isNotEmpty &&
              !_messages.last.isUser &&
              _messages.last.text.isEmpty) {
            _messages.removeLast();
          }
          _messages.add(ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text:
                'Error de conexión con el Servidor IA Local. Asegúrate de tener Ollama o tu servidor encendido.\nDetalles: $e',
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        _scrollToBottom();
      }
    }
  }

  Widget _buildHeader(BuildContext context) {
    return SizedBox(
      height: 92,
      child: Stack(
        children: [
          const Positioned.fill(child: HabitBlobHeader(accentColor: BentoTheme.accentChat)),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                'Copiloto',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.w800,
                  fontSize: 42,
                  height: 0.92,
                  letterSpacing: -1.4,
                  color: BentoTheme.cream,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),

          // Área de Mensajes
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final accent = msg.isUser ? BentoTheme.accentChat : BentoTheme.accentBlue;
                return Align(
                  alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: FractionallySizedBox(
                      widthFactor: 0.85,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: BentoTheme.darkCardAlt,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.5),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg.isUser ? 'Tú' : 'Asistente AI',
                              style: GoogleFonts.montserrat(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: accent,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (msg.isUser)
                              Text(
                                msg.text,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: BentoTheme.cream,
                                  fontWeight: FontWeight.w500,
                                  height: 1.4,
                                ),
                              )
                            else if (msg.text.isEmpty)
                              // Streaming iniciando: indicador de escritura
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  'Escribiendo…',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                    color: BentoTheme.creamAlpha(0.5),
                                  ),
                                ),
                              )
                            else
                              MarkdownBody(
                                data: msg.text,
                                styleSheet: MarkdownStyleSheet(
                                  p: TextStyle(
                                    fontSize: 14,
                                    color: BentoTheme.cream,
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                  ),
                                  strong: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: BentoTheme.cream,
                                  ),
                                  listBullet: TextStyle(
                                    fontSize: 14,
                                    color: BentoTheme.cream,
                                  ),
                                  h1: GoogleFonts.montserrat(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: BentoTheme.cream,
                                  ),
                                  h2: GoogleFonts.montserrat(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: BentoTheme.cream,
                                  ),
                                  h3: GoogleFonts.montserrat(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: BentoTheme.cream,
                                  ),
                                  code: TextStyle(
                                    fontSize: 13,
                                    color: BentoTheme.accentChat,
                                    backgroundColor: BentoTheme.creamAlpha(0.06),
                                  ),
                                  blockquote: TextStyle(
                                    fontSize: 13.5,
                                    color: BentoTheme.creamSecondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: BentoTheme.accentChat),
              ),
            ),

          // Input de texto
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 110),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    onSubmitted: (_) => _sendMessage(),
                    style: const TextStyle(color: BentoTheme.cream, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: 'Pregúntame sobre tus notas y hábitos...',
                      hintStyle: TextStyle(color: BentoTheme.creamAlpha(0.35)),
                      filled: true,
                      fillColor: BentoTheme.darkCardAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: BentoTheme.creamAlpha(0.14)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: BentoTheme.creamAlpha(0.14)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                        borderSide: BorderSide(color: BentoTheme.accentChat, width: 2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Botón enviar
                IconButton.filled(
                  onPressed: _loading ? null : _sendMessage,
                  style: IconButton.styleFrom(
                    backgroundColor: BentoTheme.accentChat,
                    padding: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.send, color: Color(0xFF0C0C0D)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
