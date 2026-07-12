import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/models/chat_model.dart';
import '../../core/providers/chat_provider.dart';
import '../habits/widgets/habit_blob_header.dart';

class ChatTab extends ConsumerStatefulWidget {
  const ChatTab({super.key});

  @override
  ConsumerState<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends ConsumerState<ChatTab> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

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
    _scrollToBottom();
    await ref.read(chatProvider.notifier).sendMessage(query);
    _scrollToBottom();
  }

  void _newConversation() {
    ref.read(chatProvider.notifier).newConversation();
    _textController.clear();
  }

  Future<void> _openHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: BentoTheme.darkCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _ConversationSheet(
        onSelect: (id) {
          Navigator.pop(sheetContext);
          ref.read(chatProvider.notifier).selectConversation(id);
          _scrollToBottom();
        },
        onNew: () {
          Navigator.pop(sheetContext);
          _newConversation();
        },
      ),
    );
  }

  Widget _buildHeader(ChatState chat) {
    final title = chat.activeId == null
        ? 'Chat nuevo'
        : chat.conversations
            .where((c) => c.id == chat.activeId)
            .map((c) => c.title)
            .firstOrNull;

    return SizedBox(
      height: 92,
      child: Stack(
        children: [
          const Positioned.fill(
              child: HabitBlobHeader(accentColor: BentoTheme.accentChat)),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Copiloto',
                        style: GoogleFonts.montserrat(
                          fontWeight: FontWeight.w800,
                          fontSize: 38,
                          height: 0.95,
                          letterSpacing: -1.4,
                          color: BentoTheme.cream,
                        ),
                      ),
                      if (title != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: BentoTheme.creamAlpha(0.55),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Conversaciones',
                  onPressed: _openHistory,
                  icon: const Icon(Icons.forum_outlined,
                      color: BentoTheme.cream, size: 22),
                ),
                IconButton(
                  tooltip: 'Chat nuevo',
                  onPressed: chat.sending ? null : _newConversation,
                  icon: const Icon(Icons.add_comment_outlined,
                      color: BentoTheme.cream, size: 22),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.savings_outlined,
                size: 44, color: BentoTheme.accentChat),
            const SizedBox(height: 16),
            Text(
              'Tu asesor financiero',
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: BentoTheme.cream,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Conoce tus cuentas, tus gastos del mes, tus hábitos y tus notas. '
              'Pregúntale si te conviene una compra, cómo recortar gastos o dónde empezar a invertir.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: BentoTheme.creamAlpha(0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(ChatMessage msg) {
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
              border: Border.all(
                  color: accent.withValues(alpha: 0.45), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.isUser ? 'Tú' : 'Copiloto financiero',
                  style: GoogleFonts.montserrat(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 6),
                if (msg.isUser)
                  Text(
                    msg.content,
                    style: const TextStyle(
                      fontSize: 14,
                      color: BentoTheme.cream,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  )
                else if (msg.content.isEmpty)
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
                    data: msg.content,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(
                        fontSize: 14,
                        color: BentoTheme.cream,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                      strong: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: BentoTheme.cream,
                      ),
                      listBullet: const TextStyle(
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
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider).value ?? const ChatState();

    return Container(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(chat),

          Expanded(
            child: chat.messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    itemCount: chat.messages.length,
                    itemBuilder: (context, index) =>
                        _buildMessage(chat.messages[index]),
                  ),
          ),

          if (chat.sending)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: BentoTheme.accentChat),
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
                    style: const TextStyle(
                        color: BentoTheme.cream, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: '¿En qué gasto o inversión te ayudo?',
                      hintStyle:
                          TextStyle(color: BentoTheme.creamAlpha(0.35)),
                      filled: true,
                      fillColor: BentoTheme.darkCardAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            BorderSide(color: BentoTheme.creamAlpha(0.14)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            BorderSide(color: BentoTheme.creamAlpha(0.14)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                        borderSide: BorderSide(
                            color: BentoTheme.accentChat, width: 2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  onPressed: chat.sending ? null : _sendMessage,
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

/// Hoja inferior con las conversaciones guardadas.
class _ConversationSheet extends ConsumerWidget {
  final void Function(String id) onSelect;
  final VoidCallback onNew;

  const _ConversationSheet({
    required this.onSelect,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatProvider).value ?? const ChatState();
    final conversations = chat.conversations;
    final activeId = chat.activeId;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Conversaciones',
                    style: GoogleFonts.montserrat(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: BentoTheme.cream,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onNew,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nuevo'),
                  style: TextButton.styleFrom(
                      foregroundColor: BentoTheme.accentChat),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (conversations.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Aún no tienes conversaciones guardadas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: BentoTheme.creamAlpha(0.5)),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: conversations.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final c = conversations[index];
                    final isActive = c.id == activeId;
                    return Container(
                      decoration: BoxDecoration(
                        color: BentoTheme.darkCardAlt,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isActive
                              ? BentoTheme.accentChat
                              : BentoTheme.creamAlpha(0.12),
                          width: isActive ? 1.5 : 1,
                        ),
                      ),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        title: Text(
                          c.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: BentoTheme.cream,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          _relativeDate(c.updatedAt),
                          style: TextStyle(
                            color: BentoTheme.creamAlpha(0.45),
                            fontSize: 12,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Eliminar',
                          icon: Icon(Icons.delete_outline,
                              size: 20, color: BentoTheme.creamAlpha(0.5)),
                          onPressed: () => ref
                              .read(chatProvider.notifier)
                              .deleteConversation(c.id),
                        ),
                        onTap: () => onSelect(c.id),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _relativeDate(DateTime date) {
    final diff = DateTime.now().difference(date.toLocal());
    if (diff.inMinutes < 1) return 'Ahora mismo';
    if (diff.inHours < 1) return 'Hace ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'Hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'Ayer';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
    return '${date.toLocal().day}/${date.toLocal().month}/${date.toLocal().year}';
  }
}
