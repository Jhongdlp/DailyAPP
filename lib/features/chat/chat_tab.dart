import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/network/local_ai_client.dart';
import '../habits/widgets/habit_blob_header.dart';
import '../notes/notes_tab.dart';
import '../../core/providers/habits_provider.dart';

class ChatMessage {
  final String id;
  final String text;
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

  Future<void> _sendMessage() async {
    final query = _textController.text.trim();
    if (query.isEmpty) return;

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

    // 1. Obtener notas y hábitos actuales para inyectar al prompt
    final notes = ref.read(notesProvider);
    final habits = ref.read(habitsProvider);
    final settings = ref.read(settingsProvider);

    final contextBuffer = StringBuffer();
    contextBuffer.writeln('INFORMACIÓN ACTUAL DEL USUARIO:');
    contextBuffer.writeln('---');
    contextBuffer.writeln('HÁBITOS:');
    for (var h in habits) {
      contextBuffer.writeln(
        '- Hábito: "${h.name}" (${h.category.label}). Racha actual: ${h.currentStreak()} días. '
        'Cumplimiento últimos 30 días: ${(h.completionRate(days: 30) * 100).round()}%.',
      );
    }
    contextBuffer.writeln('---');
    contextBuffer.writeln('SEGUNDO CEREBRO (NOTAS):');
    for (var n in notes) {
      contextBuffer.writeln('- Nota: "${n.title}". Contenido: "${n.content}"');
    }
    contextBuffer.writeln('---');
    contextBuffer.writeln('Responde la consulta del usuario usando de base esta información. No menciones explícitamente "según los datos entregados" a menos que sea necesario. Sé amigable, directo, y actúa como su coach de vida de confianza.');

    final systemPrompt = contextBuffer.toString();

    try {
      // 2. Conectar a Qwen Local
      final client = LocalAIClient(
        baseUrl: settings.localAiUrl,
        textModelName: settings.textModel,
      );

      final reply = await client.askText(query, systemPrompt: systemPrompt);

      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: reply,
            isUser: false,
            timestamp: DateTime.now(),
          ));
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: 'Error de conexión con el Servidor IA Local. Asegúrate de tener Ollama o tu servidor encendido.\nDetalles: $e',
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
                            Text(
                              msg.text,
                              style: TextStyle(
                                fontSize: 14,
                                color: BentoTheme.cream,
                                fontWeight: FontWeight.w500,
                                height: 1.4,
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
