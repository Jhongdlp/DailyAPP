import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/models/note_model.dart';

enum BlockType {
  text,
  heading1,
  heading2,
  heading3,
  bulletList,
  numberedList,
  todoList,
  quote,
  code,
  table,
  divider,
}

class EditorBlock {
  final String id;
  BlockType type;
  final TextEditingController controller;
  final FocusNode focusNode;
  bool isChecked;
  // Ancla para posicionar overlays flotantes (comando '/', wikilinks) justo
  // debajo de este bloque.
  final LayerLink layerLink = LayerLink();
  // Para tablas:
  List<List<TextEditingController>> cellControllers;

  EditorBlock({
    String? id,
    required this.type,
    TextEditingController? controller,
    FocusNode? focusNode,
    this.isChecked = false,
    List<List<TextEditingController>>? cellControllers,
  })  : id = id ?? UniqueKey().toString(),
        controller = controller ?? TextEditingController(),
        focusNode = focusNode ?? FocusNode(),
        cellControllers = cellControllers ?? [];
}

class _BlockMenuOption {
  final String label;
  final String subtitle;
  final IconData icon;
  final BlockType type;
  const _BlockMenuOption(this.label, this.subtitle, this.icon, this.type);
}

const List<_BlockMenuOption> _blockMenuOptions = [
  _BlockMenuOption('Texto Normal', 'Texto plano estándar', Icons.notes, BlockType.text),
  _BlockMenuOption('Título 1', 'Título grande principal', Icons.looks_one, BlockType.heading1),
  _BlockMenuOption('Título 2', 'Título mediano de sección', Icons.looks_two, BlockType.heading2),
  _BlockMenuOption('Título 3', 'Título pequeño de subsección', Icons.looks_3, BlockType.heading3),
  _BlockMenuOption('Lista de tareas', 'Casillas para tachar tareas', Icons.check_box_outlined, BlockType.todoList),
  _BlockMenuOption('Lista con viñetas', 'Viñetas circulares simples', Icons.format_list_bulleted, BlockType.bulletList),
  _BlockMenuOption('Lista numerada', 'Lista con secuencia numérica', Icons.format_list_numbered, BlockType.numberedList),
  _BlockMenuOption('Cita destacada', 'Bloque de cita estilizado', Icons.format_quote, BlockType.quote),
  _BlockMenuOption('Código', 'Editor con tipografía monoespaciada', Icons.code, BlockType.code),
  _BlockMenuOption('Tabla', 'Insertar tabla editable interactiva', Icons.grid_on, BlockType.table),
  _BlockMenuOption('Divisor', 'Línea separadora entre secciones', Icons.horizontal_rule, BlockType.divider),
];

class NotionEditor extends StatefulWidget {
  final TextEditingController titleController;
  final TextEditingController contentController;
  final Color accentColor;
  // Notas existentes (para el autocompletado de wikilinks [[ ]]) y el
  // callback que vincula la nota actual con la seleccionada.
  final List<Note> allNotes;
  final String? currentNoteId;
  final ValueChanged<String> onLinkNote;

  const NotionEditor({
    super.key,
    required this.titleController,
    required this.contentController,
    required this.accentColor,
    this.allNotes = const [],
    this.currentNoteId,
    required this.onLinkNote,
  });

  @override
  State<NotionEditor> createState() => _NotionEditorState();
}

class _NotionEditorState extends State<NotionEditor> {
  List<EditorBlock> _blocks = [];
  int _focusedBlockIndex = 0;

  // Overlay flotante compartido por el comando '/' y el autocompletado de
  // wikilinks '[[ ]]' — solo uno puede estar activo a la vez.
  OverlayEntry? _overlayEntry;
  EditorBlock? _overlayBlock;
  String _overlayQuery = '';
  bool _overlayIsWikilink = false;

  @override
  void initState() {
    super.initState();
    // Parsear el contenido markdown inicial
    final initialMarkdown = widget.contentController.text;
    _blocks = _parseMarkdownToBlocks(initialMarkdown);
    
    // Registrar listeners iniciales
    for (final block in _blocks) {
      _registerBlockListeners(block);
      if (block.type == BlockType.table) {
        _registerTableListeners(block);
      }
    }
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    // Limpiar controladores y focus nodes creados por nosotros
    for (final block in _blocks) {
      block.controller.dispose();
      block.focusNode.dispose();
      for (final row in block.cellControllers) {
        for (final cell in row) {
          cell.dispose();
        }
      }
    }
    super.dispose();
  }

  // ─── PARSER & SERIALIZER ────────────────────────────────

  List<EditorBlock> _parseMarkdownToBlocks(String content) {
    if (content.trim().isEmpty) {
      return [EditorBlock(type: BlockType.text)];
    }

    final lines = content.split('\n');
    final List<EditorBlock> blocks = [];
    
    int i = 0;
    while (i < lines.length) {
      final line = lines[i];
      
      // Detección de Tabla
      if (line.trim().startsWith('|')) {
        final List<List<String>> tableData = [];
        int tableEndIndex = i;
        
        while (tableEndIndex < lines.length && lines[tableEndIndex].trim().startsWith('|')) {
          final rowLine = lines[tableEndIndex].trim();
          // Ignorar fila separadora (ej: |---|---|)
          if (!rowLine.contains(RegExp(r'^\|[\s-|-]*\|$')) && !rowLine.replaceAll(' ', '').contains('|---|')) {
            final cells = rowLine.split('|')
              .map((c) => c.trim())
              .toList();
            if (cells.isNotEmpty && cells.first.isEmpty) cells.removeAt(0);
            if (cells.isNotEmpty && cells.last.isEmpty) cells.removeLast();
            tableData.add(cells);
          }
          tableEndIndex++;
        }
        
        if (tableData.isNotEmpty) {
          int maxCols = 0;
          for (final row in tableData) {
            if (row.length > maxCols) maxCols = row.length;
          }
          if (maxCols == 0) maxCols = 2;
          
          final List<List<TextEditingController>> cellCtrls = [];
          for (final row in tableData) {
            final List<TextEditingController> rowCtrls = [];
            for (int c = 0; c < maxCols; c++) {
              final cellText = c < row.length ? row[c] : '';
              rowCtrls.add(TextEditingController(text: cellText));
            }
            cellCtrls.add(rowCtrls);
          }
          
          if (cellCtrls.length < 2) {
            cellCtrls.add(List.generate(maxCols, (_) => TextEditingController()));
          }
          
          blocks.add(EditorBlock(
            type: BlockType.table,
            cellControllers: cellCtrls,
          ));
          
          i = tableEndIndex;
          continue;
        }
      }
      
      // Detección de Bloque de Código
      if (line.trim().startsWith('```')) {
        final codeLines = <String>[];
        int codeEndIndex = i + 1;
        while (codeEndIndex < lines.length && !lines[codeEndIndex].trim().startsWith('```')) {
          codeLines.add(lines[codeEndIndex]);
          codeEndIndex++;
        }
        final codeContent = codeLines.join('\n');
        blocks.add(EditorBlock(
          type: BlockType.code,
          controller: TextEditingController(text: codeContent),
        ));
        i = codeEndIndex + 1;
        continue;
      }
      
      // Detección de otros tipos
      final trimmed = line.trim();
      if (RegExp(r'^-{3,}$').hasMatch(trimmed)) {
        blocks.add(EditorBlock(type: BlockType.divider));
      } else if (trimmed.startsWith('# ')) {
        blocks.add(EditorBlock(
          type: BlockType.heading1,
          controller: TextEditingController(text: trimmed.substring(2)),
        ));
      } else if (trimmed.startsWith('## ')) {
        blocks.add(EditorBlock(
          type: BlockType.heading2,
          controller: TextEditingController(text: trimmed.substring(3)),
        ));
      } else if (trimmed.startsWith('### ')) {
        blocks.add(EditorBlock(
          type: BlockType.heading3,
          controller: TextEditingController(text: trimmed.substring(4)),
        ));
      } else if (trimmed.startsWith('> ')) {
        blocks.add(EditorBlock(
          type: BlockType.quote,
          controller: TextEditingController(text: trimmed.substring(2)),
        ));
      } else if (trimmed.startsWith('- [ ] ') || trimmed.startsWith('* [ ] ')) {
        blocks.add(EditorBlock(
          type: BlockType.todoList,
          isChecked: false,
          controller: TextEditingController(text: trimmed.substring(6)),
        ));
      } else if (trimmed.startsWith('- [x] ') || trimmed.startsWith('* [x] ')) {
        blocks.add(EditorBlock(
          type: BlockType.todoList,
          isChecked: true,
          controller: TextEditingController(text: trimmed.substring(6)),
        ));
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        blocks.add(EditorBlock(
          type: BlockType.bulletList,
          controller: TextEditingController(text: trimmed.substring(2)),
        ));
      } else if (RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
        final match = RegExp(r'^(\d+)\.\s').firstMatch(trimmed);
        final prefixLen = match != null ? match.group(0)!.length : 3;
        blocks.add(EditorBlock(
          type: BlockType.numberedList,
          controller: TextEditingController(text: trimmed.substring(prefixLen)),
        ));
      } else {
        blocks.add(EditorBlock(
          type: BlockType.text,
          controller: TextEditingController(text: line),
        ));
      }
      
      i++;
    }
    
    if (blocks.isEmpty) {
      blocks.add(EditorBlock(type: BlockType.text));
    }
    
    return blocks;
  }

  String _serializeBlocksToMarkdown() {
    final List<String> lines = [];
    
    for (final block in _blocks) {
      final text = block.controller.text;
      switch (block.type) {
        case BlockType.text:
          lines.add(text);
          break;
        case BlockType.heading1:
          lines.add('# $text');
          break;
        case BlockType.heading2:
          lines.add('## $text');
          break;
        case BlockType.heading3:
          lines.add('### $text');
          break;
        case BlockType.quote:
          lines.add('> $text');
          break;
        case BlockType.bulletList:
          lines.add('- $text');
          break;
        case BlockType.numberedList:
          lines.add('1. $text');
          break;
        case BlockType.todoList:
          final box = block.isChecked ? '[x]' : '[ ]';
          lines.add('- $box $text');
          break;
        case BlockType.code:
          lines.add('```\n$text\n```');
          break;
        case BlockType.divider:
          lines.add('---');
          break;
        case BlockType.table:
          if (block.cellControllers.isEmpty) break;
          final List<String> tableLines = [];
          
          for (int r = 0; r < block.cellControllers.length; r++) {
            final rowCtrls = block.cellControllers[r];
            final rowText = '| ${rowCtrls.map((c) => c.text.replaceAll('|', '\\|')).join(' | ')} |';
            tableLines.add(rowText);
            
            if (r == 0) {
              final sepText = '| ${List.generate(rowCtrls.length, (_) => '---').join(' | ')} |';
              tableLines.add(sepText);
            }
          }
          lines.add(tableLines.join('\n'));
          break;
      }
    }
    
    return lines.join('\n');
  }

  void _serialize() {
    final markdown = _serializeBlocksToMarkdown();
    widget.contentController.value = TextEditingValue(
      text: markdown,
      selection: widget.contentController.selection,
    );
  }

  void _onReorderBlocks(int oldIndex, int newIndex) {
    setState(() {
      final block = _blocks.removeAt(oldIndex);
      _blocks.insert(newIndex, block);
      if (_focusedBlockIndex == oldIndex) {
        _focusedBlockIndex = newIndex;
      } else if (_focusedBlockIndex > oldIndex && _focusedBlockIndex <= newIndex) {
        _focusedBlockIndex -= 1;
      } else if (_focusedBlockIndex < oldIndex && _focusedBlockIndex >= newIndex) {
        _focusedBlockIndex += 1;
      }
    });
    _serialize();
  }

  // ─── LISTENERS & EVENTOS ───────────────────────────────

  static const Set<BlockType> _listLikeTypes = {
    BlockType.bulletList,
    BlockType.numberedList,
    BlockType.todoList,
    BlockType.quote,
  };

  /// Detecta atajos de auto-markdown (estilo Notion/Obsidian) en un bloque de
  /// texto plano recién editado. Retorna true si convirtió el bloque.
  bool _tryAutoConvert(EditorBlock block, String text) {
    BlockType? newType;
    if (text == '# ') {
      newType = BlockType.heading1;
    } else if (text == '## ') {
      newType = BlockType.heading2;
    } else if (text == '### ') {
      newType = BlockType.heading3;
    } else if (text == '- ' || text == '* ') {
      newType = BlockType.bulletList;
    } else if (RegExp(r'^\d+\.\s$').hasMatch(text)) {
      newType = BlockType.numberedList;
    } else if (text == '> ') {
      newType = BlockType.quote;
    } else if (text == '[] ' || text == '[ ] ') {
      newType = BlockType.todoList;
    } else if (text == '```') {
      newType = BlockType.code;
    }

    if (newType == null) return false;

    block.controller.value = const TextEditingValue(text: '');
    setState(() {
      block.type = newType!;
      if (newType == BlockType.todoList) block.isChecked = false;
    });
    _serialize();
    return true;
  }

  void _registerBlockListeners(EditorBlock block) {
    block.controller.addListener(() {
      if (!mounted) return;
      final text = block.controller.text;

      if (block.type == BlockType.text &&
          !text.contains('\n') &&
          _tryAutoConvert(block, text)) {
        return;
      }

      if (text.contains('\n')) {
        if (_overlayBlock == block) _closeOverlay();
        final index = _blocks.indexOf(block);
        if (index == -1) return;

        // El código conserva los saltos de línea como contenido literal.
        if (block.type == BlockType.code) {
          _serialize();
          return;
        }

        final newlineIndex = text.indexOf('\n');
        final before = text.substring(0, newlineIndex);
        final after = text.substring(newlineIndex + 1);
        final continuesType = _listLikeTypes.contains(block.type);

        // Enter sobre un ítem de lista/cita vacío: sale de la lista sin
        // crear un bloque nuevo (estilo Notion).
        if (continuesType && before.isEmpty && after.isEmpty) {
          block.controller.value = const TextEditingValue(text: '');
          setState(() => block.type = BlockType.text);
          _serialize();
          return;
        }

        block.controller.value = TextEditingValue(
          text: before,
          selection: TextSelection.collapsed(offset: before.length),
        );

        final newBlock = EditorBlock(
          type: continuesType ? block.type : BlockType.text,
          controller: TextEditingController(text: after),
        );
        _registerBlockListeners(newBlock);

        setState(() {
          _blocks.insert(index + 1, newBlock);
          _focusedBlockIndex = index + 1;
        });

        _serialize();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          newBlock.focusNode.requestFocus();
        });
      } else {
        final isOverlayEligible =
            block.type != BlockType.code && block.type != BlockType.table;
        if (isOverlayEligible) {
          _handleOverlayTriggers(block, text);
        } else if (_overlayBlock == block) {
          _closeOverlay();
        }
        _serialize();
      }
    });
  }

  // ─── OVERLAYS FLOTANTES: comando '/' y wikilinks '[[ ]]' ──────

  /// Detecta el trigger de comando '/' (solo en bloques de texto plano) o de
  /// wikilink '[[' (en cualquier bloque de texto libre) y abre/actualiza/
  /// cierra el overlay flotante correspondiente.
  void _handleOverlayTriggers(EditorBlock block, String text) {
    if (block.type == BlockType.text) {
      final slashMatch = RegExp(r'^/(\w*)$').firstMatch(text);
      if (slashMatch != null) {
        _overlayIsWikilink = false;
        _showOverlay(block, slashMatch.group(1) ?? '');
        return;
      }
    }

    final selection = block.controller.selection;
    final caret = selection.baseOffset;
    final safeCaret = (caret < 0 ? text.length : caret).clamp(0, text.length);
    final beforeCaret = text.substring(0, safeCaret);
    final wikiMatch = RegExp(r'\[\[([^\[\]]*)$').firstMatch(beforeCaret);
    if (wikiMatch != null) {
      _overlayIsWikilink = true;
      _showOverlay(block, wikiMatch.group(1) ?? '');
      return;
    }

    if (_overlayBlock == block) _closeOverlay();
  }

  void _showOverlay(EditorBlock block, String query) {
    _overlayQuery = query;
    if (_overlayBlock == block && _overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }
    _closeOverlay();
    _overlayBlock = block;
    _overlayEntry = OverlayEntry(builder: (ctx) => _buildOverlay(block));
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _closeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _overlayBlock = null;
    _overlayQuery = '';
  }

  Widget _buildOverlay(EditorBlock block) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _closeOverlay,
          ),
        ),
        CompositedTransformFollower(
          link: block.layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 38),
          child: _overlayIsWikilink ? _buildWikilinkCard(block) : _buildSlashMenuCard(block),
        ),
      ],
    );
  }

  Widget _overlayCardShell({required Widget child}) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 240,
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(
            color: BentoTheme.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: BentoTheme.creamAlpha(0.25)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _overlayEmptyState(String text) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Text(text, style: TextStyle(color: BentoTheme.creamAlpha(0.5), fontSize: 12)),
    );
  }

  Widget _buildSlashMenuCard(EditorBlock block) {
    final query = _overlayQuery.toLowerCase();
    final options = _blockMenuOptions
        .where((o) => query.isEmpty || o.label.toLowerCase().contains(query))
        .toList();
    return _overlayCardShell(
      child: options.isEmpty
          ? _overlayEmptyState('Sin bloques')
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              children: [
                for (final o in options)
                  ListTile(
                    dense: true,
                    leading: Icon(o.icon, size: 18, color: widget.accentColor),
                    title: Text(o.label,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BentoTheme.cream)),
                    onTap: () => _applySlashSelection(block, o.type),
                  ),
              ],
            ),
    );
  }

  Widget _buildWikilinkCard(EditorBlock block) {
    final query = _overlayQuery.toLowerCase();
    final matches = widget.allNotes
        .where((n) => n.id != widget.currentNoteId)
        .where((n) => query.isEmpty || n.title.toLowerCase().contains(query))
        .take(8)
        .toList();
    return _overlayCardShell(
      child: matches.isEmpty
          ? _overlayEmptyState('Sin notas coincidentes')
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              children: [
                for (final n in matches)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.description_outlined, size: 18, color: widget.accentColor),
                    title: Text(n.title,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: BentoTheme.cream),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    onTap: () => _applyWikilinkSelection(block, n),
                  ),
              ],
            ),
    );
  }

  void _applySlashSelection(EditorBlock block, BlockType type) {
    block.controller.value = const TextEditingValue(text: '');
    setState(() {
      block.type = type;
      if (type == BlockType.todoList) block.isChecked = false;
    });
    _closeOverlay();
    _serialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      block.focusNode.requestFocus();
    });
  }

  void _applyWikilinkSelection(EditorBlock block, Note note) {
    final text = block.controller.text;
    final caret = block.controller.selection.baseOffset;
    final safeCaret = (caret < 0 ? text.length : caret).clamp(0, text.length);
    final beforeCaret = text.substring(0, safeCaret);
    final afterCaret = text.substring(safeCaret);
    final match = RegExp(r'\[\[([^\[\]]*)$').firstMatch(beforeCaret);

    _closeOverlay();
    if (match == null) return;

    final newBefore = '${beforeCaret.substring(0, match.start)}[[${note.title}]]';
    final newText = newBefore + afterCaret;
    block.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newBefore.length),
    );
    _serialize();
    widget.onLinkNote(note.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      block.focusNode.requestFocus();
    });
  }

  void _registerTableListeners(EditorBlock block) {
    for (final row in block.cellControllers) {
      for (final cellCtrl in row) {
        cellCtrl.addListener(() {
          if (!mounted) return;
          _serialize();
        });
      }
    }
  }

  // ─── ACCIONES DE BLOQUES ────────────────────────────────

  void _insertBlock(BlockType type) {
    final int index = _focusedBlockIndex;
    final newBlock = EditorBlock(type: type);
    
    if (type == BlockType.table) {
      newBlock.cellControllers = [
        [TextEditingController(text: 'Encabezado 1'), TextEditingController(text: 'Encabezado 2')],
        [TextEditingController(), TextEditingController()],
      ];
      _registerTableListeners(newBlock);
    } else {
      _registerBlockListeners(newBlock);
    }
    
    setState(() {
      if (index >= 0 && index < _blocks.length) {
        _blocks.insert(index + 1, newBlock);
        _focusedBlockIndex = index + 1;
      } else {
        _blocks.add(newBlock);
        _focusedBlockIndex = _blocks.length - 1;
      }
    });
    
    _serialize();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (type != BlockType.table) {
        newBlock.focusNode.requestFocus();
      }
    });
  }

  void _moveBlockUp() {
    final index = _focusedBlockIndex;
    if (index <= 0 || index >= _blocks.length) return;
    setState(() {
      final temp = _blocks[index];
      _blocks[index] = _blocks[index - 1];
      _blocks[index - 1] = temp;
      _focusedBlockIndex = index - 1;
    });
    _serialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _blocks[_focusedBlockIndex].focusNode.requestFocus();
    });
  }

  void _moveBlockDown() {
    final index = _focusedBlockIndex;
    if (index < 0 || index >= _blocks.length - 1) return;
    setState(() {
      final temp = _blocks[index];
      _blocks[index] = _blocks[index + 1];
      _blocks[index + 1] = temp;
      _focusedBlockIndex = index + 1;
    });
    _serialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _blocks[_focusedBlockIndex].focusNode.requestFocus();
    });
  }

  void _deleteBlock() {
    final index = _focusedBlockIndex;
    if (index < 0 || index >= _blocks.length) return;
    
    if (_blocks.length == 1) {
      setState(() {
        _blocks[0].controller.clear();
        _blocks[0].type = BlockType.text;
      });
      _serialize();
      return;
    }
    
    setState(() {
      final removed = _blocks.removeAt(index);
      removed.controller.dispose();
      removed.focusNode.dispose();
      for (final row in removed.cellControllers) {
        for (final cell in row) {
          cell.dispose();
        }
      }
      
      if (index > 0) {
        _focusedBlockIndex = index - 1;
      } else {
        _focusedBlockIndex = 0;
      }
    });
    
    _serialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_focusedBlockIndex >= 0 && _focusedBlockIndex < _blocks.length) {
        _blocks[_focusedBlockIndex].focusNode.requestFocus();
      }
    });
  }

  // ─── MENÚS DESPLEGABLES (STYLE NOTION) ───────────────────

  void _showAddBlockMenu() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Habilitar scroll controlado
      backgroundColor: BentoTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SizedBox(
          height: 480, // Limitar altura para evitar problemas de restricciones infinitas en Linux/escritorio
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: BentoTheme.creamAlpha(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Añadir elemento Notion',
                    style: GoogleFonts.montserrat(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: BentoTheme.cream,
                    ),
                  ),
                ),
                Divider(color: BentoTheme.creamAlpha(0.18), height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final o in _blockMenuOptions)
                        _blockMenuTile(ctx, o.label, o.subtitle, o.icon, o.type),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _blockMenuTile(BuildContext ctx, String label, String subtitle, IconData icon, BlockType type) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: widget.accentColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: widget.accentColor, size: 20),
      ),
      title: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: BentoTheme.cream)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: BentoTheme.creamSecondary)),
      onTap: () {
        Navigator.pop(ctx);
        _insertBlock(type);
      },
    );
  }

  void _showConvertBlockMenu() {
    final index = _focusedBlockIndex;
    if (index < 0 || index >= _blocks.length) return;
    final currentBlock = _blocks[index];
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Habilitar scroll controlado
      backgroundColor: BentoTheme.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SizedBox(
          height: 420, // Altura fija segura para evitar restricciones infinitas en Linux/escritorio
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: BentoTheme.creamAlpha(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Convertir bloque actual a...',
                    style: GoogleFonts.montserrat(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: BentoTheme.cream,
                    ),
                  ),
                ),
                Divider(color: BentoTheme.creamAlpha(0.18), height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _convertMenuTile(ctx, 'Texto Normal', Icons.notes, BlockType.text, currentBlock),
                      _convertMenuTile(ctx, 'Título 1', Icons.looks_one, BlockType.heading1, currentBlock),
                      _convertMenuTile(ctx, 'Título 2', Icons.looks_two, BlockType.heading2, currentBlock),
                      _convertMenuTile(ctx, 'Título 3', Icons.looks_3, BlockType.heading3, currentBlock),
                      _convertMenuTile(ctx, 'Lista de tareas', Icons.check_box_outlined, BlockType.todoList, currentBlock),
                      _convertMenuTile(ctx, 'Lista con viñetas', Icons.format_list_bulleted, BlockType.bulletList, currentBlock),
                      _convertMenuTile(ctx, 'Lista numerada', Icons.format_list_numbered, BlockType.numberedList, currentBlock),
                      _convertMenuTile(ctx, 'Cita destacada', Icons.format_quote, BlockType.quote, currentBlock),
                      _convertMenuTile(ctx, 'Código', Icons.code, BlockType.code, currentBlock),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _convertMenuTile(BuildContext ctx, String label, IconData icon, BlockType targetType, EditorBlock block) {
    final isSelected = block.type == targetType;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? widget.accentColor.withValues(alpha: 0.15) : BentoTheme.darkCardAlt,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: isSelected ? widget.accentColor : BentoTheme.creamSecondary, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          color: isSelected ? widget.accentColor : BentoTheme.cream,
          fontSize: 14,
        ),
      ),
      trailing: isSelected ? Icon(Icons.check, color: widget.accentColor, size: 18) : null,
      onTap: () {
        Navigator.pop(ctx);
        setState(() {
          block.type = targetType;
          if (targetType == BlockType.todoList) {
            block.isChecked = false;
          }
        });
        _serialize();
      },
    );
  }

  // ─── RENDERIZADOS DE BLOQUES INDIVIDUALES ─────────────────

  Widget _buildBlockField(EditorBlock block, int index) {
    switch (block.type) {
      case BlockType.text:
        return _buildTextField(block, index,
            style: TextStyle(fontSize: 15, color: BentoTheme.cream, height: 1.5),
            hint: 'Escribe algo...');
      case BlockType.heading1:
        return _buildTextField(block, index,
            style: GoogleFonts.montserrat(fontSize: 22, fontWeight: FontWeight.w900, color: BentoTheme.cream),
            hint: 'Título 1');
      case BlockType.heading2:
        return _buildTextField(block, index,
            style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.w800, color: BentoTheme.cream),
            hint: 'Título 2');
      case BlockType.heading3:
        return _buildTextField(block, index,
            style: GoogleFonts.montserrat(fontSize: 15, fontWeight: FontWeight.w700, color: BentoTheme.cream),
            hint: 'Título 3');
      case BlockType.quote:
        return Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: widget.accentColor, width: 4)),
          ),
          padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
          child: _buildTextField(block, index,
              style: TextStyle(fontSize: 15, fontStyle: FontStyle.italic, color: BentoTheme.creamAlpha(0.6), height: 1.5),
              hint: 'Cita'),
        );
      case BlockType.bulletList:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, right: 10, left: 4),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: BentoTheme.cream,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(
              child: _buildTextField(block, index,
                  style: TextStyle(fontSize: 15, color: BentoTheme.cream, height: 1.5),
                  hint: 'Elemento de lista'),
            ),
          ],
        );
      case BlockType.numberedList:
        int itemNumber = 1;
        for (int i = index - 1; i >= 0; i--) {
          if (_blocks[i].type == BlockType.numberedList) {
            itemNumber++;
          } else {
            break;
          }
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8, left: 4),
              child: Text(
                '$itemNumber.',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: BentoTheme.cream),
              ),
            ),
            Expanded(
              child: _buildTextField(block, index,
                  style: TextStyle(fontSize: 15, color: BentoTheme.cream, height: 1.5),
                  hint: 'Elemento de lista'),
            ),
          ],
        );
      case BlockType.todoList:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: block.isChecked,
                  activeColor: widget.accentColor,
                  onChanged: (val) {
                    setState(() {
                      block.isChecked = val ?? false;
                    });
                    _serialize();
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTextField(block, index,
                  style: TextStyle(
                    fontSize: 15,
                    color: block.isChecked ? BentoTheme.creamAlpha(0.5) : BentoTheme.cream,
                    decoration: block.isChecked ? TextDecoration.lineThrough : null,
                    height: 1.5,
                  ),
                  hint: 'Tarea'),
            ),
          ],
        );
      case BlockType.code:
        return Container(
          decoration: BoxDecoration(
            color: BentoTheme.darkCardAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: BentoTheme.creamAlpha(0.18), width: 1.5),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.code_rounded, size: 12, color: BentoTheme.creamTertiary),
                      const SizedBox(width: 4),
                      Text(
                        'CÓDIGO',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: BentoTheme.creamTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _buildTextField(block, index,
                  style: TextStyle(fontSize: 13.5, fontFamily: 'monospace', color: BentoTheme.cream),
                  hint: 'Escribe tu código aquí...'),
            ],
          ),
        );
      case BlockType.table:
        return _buildTableWidget(block, index);
      case BlockType.divider:
        return _buildDividerBlock(block, index);
    }
  }

  Widget _buildDividerBlock(EditorBlock block, int index) {
    final isFocused = _focusedBlockIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _focusedBlockIndex = index);
        block.focusNode.requestFocus();
      },
      child: Focus(
        focusNode: block.focusNode,
        child: Container(
          height: 28,
          alignment: Alignment.center,
          child: Divider(
            color: isFocused
                ? widget.accentColor.withValues(alpha: 0.6)
                : BentoTheme.creamAlpha(0.20),
            thickness: isFocused ? 2 : 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(EditorBlock block, int index,
      {required TextStyle style, required String hint}) {
    return Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          setState(() {
            _focusedBlockIndex = index;
          });
        } else if (_overlayBlock == block) {
          _closeOverlay();
        }
      },
      child: TextField(
        controller: block.controller,
        focusNode: block.focusNode,
        style: style,
        maxLines: null,
        minLines: 1,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          filled: false,
        ),
        onTap: () {
          setState(() {
            _focusedBlockIndex = index;
          });
        },
        contextMenuBuilder: (ctx, editableTextState) =>
            _buildFormattingContextMenu(ctx, editableTextState, block.controller),
      ),
    );
  }

  /// Añade botones de formato markdown (negrita/cursiva/código/enlace) al
  /// menú contextual nativo de selección de texto, en vez de construir un
  /// tercer overlay flotante a mano — el menú nativo ya resuelve el
  /// posicionamiento junto a la selección.
  Widget _buildFormattingContextMenu(
    BuildContext ctx,
    EditableTextState editableTextState,
    TextEditingController controller,
  ) {
    final selection = controller.selection;
    final items = List<ContextMenuButtonItem>.from(editableTextState.contextMenuButtonItems);

    if (selection.isValid && !selection.isCollapsed) {
      items.insertAll(0, [
        ContextMenuButtonItem(
          label: 'Negrita',
          onPressed: () => _wrapSelectionWithMarkdown(controller, editableTextState, '**', '**'),
        ),
        ContextMenuButtonItem(
          label: 'Cursiva',
          onPressed: () => _wrapSelectionWithMarkdown(controller, editableTextState, '_', '_'),
        ),
        ContextMenuButtonItem(
          label: 'Código',
          onPressed: () => _wrapSelectionWithMarkdown(controller, editableTextState, '`', '`'),
        ),
        ContextMenuButtonItem(
          label: 'Enlace',
          onPressed: () => _wrapSelectionWithMarkdown(controller, editableTextState, '[', '](url)'),
        ),
      ]);
    }

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: items,
    );
  }

  void _wrapSelectionWithMarkdown(
    TextEditingController controller,
    EditableTextState editableTextState,
    String prefix,
    String suffix,
  ) {
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final selected = text.substring(start, end);
    final newText = text.replaceRange(start, end, '$prefix$selected$suffix');
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + prefix.length + selected.length + suffix.length),
    );
    editableTextState.hideToolbar();
  }

  // ─── TABLA INTERACTIVA ───────────────────────────────────

  Widget _buildTableWidget(EditorBlock block, int index) {
    if (block.cellControllers.isEmpty) return const SizedBox();

    final colsCount = block.cellControllers[0].length;
    final rowsCount = block.cellControllers.length;

    return Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          setState(() {
            _focusedBlockIndex = index;
          });
        }
      },
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 8),
        decoration: BoxDecoration(
          color: BentoTheme.darkCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BentoTheme.creamAlpha(0.20), width: 2),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.grid_on, size: 16, color: widget.accentColor),
                    const SizedBox(width: 8),
                    Text(
                      'TABLA',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: BentoTheme.cream),
                    ),
                  ],
                ),
                Text(
                  '${rowsCount}x$colsCount',
                  style: TextStyle(fontSize: 11, color: BentoTheme.creamSecondary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const FixedColumnWidth(100),
                border: TableBorder.all(
                  color: BentoTheme.creamAlpha(0.20),
                  width: 1.5,
                  borderRadius: BorderRadius.circular(8),
                ),
                children: List.generate(rowsCount, (rIndex) {
                  final rowCtrls = block.cellControllers[rIndex];
                  final isHeader = rIndex == 0;

                  return TableRow(
                    decoration: BoxDecoration(
                      color: isHeader ? widget.accentColor.withValues(alpha: 0.12) : null,
                    ),
                    children: List.generate(colsCount, (cIndex) {
                      final ctrl = rowCtrls[cIndex];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: TextField(
                          controller: ctrl,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                            color: BentoTheme.cream,
                          ),
                          maxLines: 1,
                          decoration: const InputDecoration(
                            hintText: '...',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 4),
                            filled: false,
                          ),
                          onTap: () {
                            setState(() {
                              _focusedBlockIndex = index;
                            });
                          },
                        ),
                      );
                    }),
                  );
                }),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _tableActionBtn(Icons.add, 'Fila', () => _addTableRow(block)),
                const SizedBox(width: 4),
                _tableActionBtn(Icons.remove, 'Fila', () => _removeTableRow(block)),
                const SizedBox(width: 8),
                _tableActionBtn(Icons.add, 'Col', () => _addTableCol(block)),
                const SizedBox(width: 4),
                _tableActionBtn(Icons.remove, 'Col', () => _removeTableCol(block)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _tableActionBtn(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: BentoTheme.darkCardAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: BentoTheme.creamAlpha(0.20)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: BentoTheme.cream),
            const SizedBox(width: 2),
            Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: BentoTheme.cream)),
          ],
        ),
      ),
    );
  }

  void _addTableRow(EditorBlock block) {
    final cols = block.cellControllers.isNotEmpty ? block.cellControllers[0].length : 2;
    final List<TextEditingController> newRow = List.generate(cols, (_) {
      final ctrl = TextEditingController();
      ctrl.addListener(_serialize);
      return ctrl;
    });
    setState(() {
      block.cellControllers.add(newRow);
    });
    _serialize();
  }

  void _removeTableRow(EditorBlock block) {
    if (block.cellControllers.length <= 2) return;
    setState(() {
      final removedRow = block.cellControllers.removeLast();
      for (final ctrl in removedRow) {
        ctrl.dispose();
      }
    });
    _serialize();
  }

  void _addTableCol(EditorBlock block) {
    setState(() {
      for (final row in block.cellControllers) {
        final ctrl = TextEditingController();
        ctrl.addListener(_serialize);
        row.add(ctrl);
      }
    });
    _serialize();
  }

  void _removeTableCol(EditorBlock block) {
    if (block.cellControllers.isEmpty || block.cellControllers[0].length <= 1) return;
    setState(() {
      for (final row in block.cellControllers) {
        final ctrl = row.removeLast();
        ctrl.dispose();
      }
    });
    _serialize();
  }

  // ─── BOTTOM BAR TOOLBAR ──────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: BentoTheme.darkCard,
        border: Border(top: BorderSide(color: BentoTheme.creamAlpha(0.18), width: 1.5)),
      ),
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _bottomBarBtn(Icons.add_circle_outline, 'Bloque', _showAddBlockMenu),
          _bottomBarBtn(Icons.swap_horiz, 'Convertir', _showConvertBlockMenu),
          _bottomBarBtn(Icons.keyboard_arrow_up, 'Subir', _moveBlockUp),
          _bottomBarBtn(Icons.keyboard_arrow_down, 'Bajar', _moveBlockDown),
          _bottomBarBtn(Icons.delete_outline, 'Borrar', _deleteBlock, color: BentoTheme.errorRed),
        ],
      ),
    );
  }

  Widget _bottomBarBtn(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    final finalColor = color ?? BentoTheme.cream;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: finalColor),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: finalColor),
            ),
          ],
        ),
      ),
    );
  }

  // ─── MAIN BUILD ─────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            children: [
              // Título de la Nota
              TextField(
                controller: widget.titleController,
                style: GoogleFonts.montserrat(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: BentoTheme.cream,
                ),
                decoration: InputDecoration(
                  hintText: 'Sin título',
                  hintStyle: TextStyle(color: BentoTheme.creamAlpha(0.3)),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  filled: false,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 1.5,
                color: BentoTheme.creamAlpha(0.18),
              ),
              const SizedBox(height: 16),
              // Lista de bloques editables (long-press en el handle reordena)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _blocks.length,
                onReorderItem: _onReorderBlocks,
                itemBuilder: (context, index) {
                  final block = _blocks[index];
                  final isFocused = _focusedBlockIndex == index;

                  return Container(
                    key: ValueKey(block.id),
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: isFocused ? widget.accentColor.withValues(alpha: 0.03) : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: CompositedTransformTarget(
                      link: block.layerLink,
                      child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ReorderableDelayedDragStartListener(
                          index: index,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _focusedBlockIndex = index;
                              });
                              block.focusNode.requestFocus();
                            },
                            child: Container(
                              width: 24,
                              height: 38,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.drag_indicator,
                                size: 16,
                                color: isFocused
                                    ? widget.accentColor
                                    : BentoTheme.creamAlpha(0.25),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildBlockField(block, index),
                        ),
                      ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        // Toolbar inferior adaptado a celular que sube con el teclado
        _buildBottomBar(),
      ],
    );
  }
}
