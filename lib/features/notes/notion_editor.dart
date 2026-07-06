import 'package:flutter/material.dart';
import '../../core/theme/bento_theme.dart';

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
}

class EditorBlock {
  final String id;
  BlockType type;
  final TextEditingController controller;
  final FocusNode focusNode;
  bool isChecked;
  // Para tablas:
  List<List<TextEditingController>> cellControllers;

  EditorBlock({
    String? id,
    required this.type,
    TextEditingController? controller,
    FocusNode? focusNode,
    this.isChecked = false,
    List<List<TextEditingController>>? cellControllers,
  })  : this.id = id ?? UniqueKey().toString(),
        this.controller = controller ?? TextEditingController(),
        this.focusNode = focusNode ?? FocusNode(),
        this.cellControllers = cellControllers ?? [];
}

class NotionEditor extends StatefulWidget {
  final TextEditingController titleController;
  final TextEditingController contentController;
  final Color accentColor;

  const NotionEditor({
    super.key,
    required this.titleController,
    required this.contentController,
    required this.accentColor,
  });

  @override
  State<NotionEditor> createState() => _NotionEditorState();
}

class _NotionEditorState extends State<NotionEditor> {
  List<EditorBlock> _blocks = [];
  int _focusedBlockIndex = 0;

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
      if (trimmed.startsWith('# ')) {
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

  // ─── LISTENERS & EVENTOS ───────────────────────────────

  void _registerBlockListeners(EditorBlock block) {
    block.controller.addListener(() {
      if (!mounted) return;
      final text = block.controller.text;
      if (text.contains('\n')) {
        final index = _blocks.indexOf(block);
        if (index == -1) return;
        
        final newlineIndex = text.indexOf('\n');
        final before = text.substring(0, newlineIndex);
        final after = text.substring(newlineIndex + 1);

        block.controller.value = TextEditingValue(
          text: before,
          selection: TextSelection.collapsed(offset: before.length),
        );

        final newBlock = EditorBlock(
          type: BlockType.text,
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
        _serialize();
      }
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
      backgroundColor: BentoTheme.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: BentoTheme.borderMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Añadir elemento Notion',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: BentoTheme.textPrimary,
                  ),
                ),
              ),
              const Divider(color: BentoTheme.borderMuted, height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _blockMenuTile(ctx, 'Texto Normal', 'Texto plano estándar', Icons.notes, BlockType.text),
                    _blockMenuTile(ctx, 'Título 1', 'Título grande principal', Icons.looks_one, BlockType.heading1),
                    _blockMenuTile(ctx, 'Título 2', 'Título mediano de sección', Icons.looks_two, BlockType.heading2),
                    _blockMenuTile(ctx, 'Título 3', 'Título pequeño de subsección', Icons.looks_3, BlockType.heading3),
                    _blockMenuTile(ctx, 'Lista de tareas', 'Casillas para tachar tareas', Icons.check_box_outlined, BlockType.todoList),
                    _blockMenuTile(ctx, 'Lista con viñetas', 'Viñetas circulares simples', Icons.format_list_bulleted, BlockType.bulletList),
                    _blockMenuTile(ctx, 'Lista numerada', 'Lista con secuencia numérica', Icons.format_list_numbered, BlockType.numberedList),
                    _blockMenuTile(ctx, 'Cita destacada', 'Bloque de cita estilizado', Icons.format_quote, BlockType.quote),
                    _blockMenuTile(ctx, 'Código', 'Editor con tipografía monoespaciada', Icons.code, BlockType.code),
                    _blockMenuTile(ctx, 'Tabla', 'Insertar tabla editable interactiva', Icons.grid_on, BlockType.table),
                  ],
                ),
              ),
            ],
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
          color: widget.accentColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: widget.accentColor, size: 20),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: BentoTheme.textPrimary)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: BentoTheme.textSecondary)),
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
      backgroundColor: BentoTheme.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: BentoTheme.borderMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Convertir bloque actual a...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: BentoTheme.textPrimary,
                  ),
                ),
              ),
              const Divider(color: BentoTheme.borderMuted, height: 1),
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
          color: isSelected ? widget.accentColor.withOpacity(0.15) : BentoTheme.bgLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: isSelected ? widget.accentColor : BentoTheme.textSecondary, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          color: isSelected ? widget.accentColor : BentoTheme.textPrimary,
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
            style: const TextStyle(fontSize: 15, color: BentoTheme.textPrimary, height: 1.5),
            hint: 'Escribe algo...');
      case BlockType.heading1:
        return _buildTextField(block, index,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: BentoTheme.textPrimary),
            hint: 'Título 1');
      case BlockType.heading2:
        return _buildTextField(block, index,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: BentoTheme.textPrimary),
            hint: 'Título 2');
      case BlockType.heading3:
        return _buildTextField(block, index,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BentoTheme.textPrimary),
            hint: 'Título 3');
      case BlockType.quote:
        return Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: widget.accentColor, width: 4)),
          ),
          padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
          child: _buildTextField(block, index,
              style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic, color: BentoTheme.textSecondary, height: 1.5),
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
                decoration: const BoxDecoration(
                  color: BentoTheme.textPrimary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(
              child: _buildTextField(block, index,
                  style: const TextStyle(fontSize: 15, color: BentoTheme.textPrimary, height: 1.5),
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
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: BentoTheme.textPrimary),
              ),
            ),
            Expanded(
              child: _buildTextField(block, index,
                  style: const TextStyle(fontSize: 15, color: BentoTheme.textPrimary, height: 1.5),
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
                    color: block.isChecked ? BentoTheme.textSecondary : BentoTheme.textPrimary,
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
            color: BentoTheme.primaryDark.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: BentoTheme.borderMuted, width: 1.5),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '💻 CÓDIGO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: BentoTheme.textSecondary.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _buildTextField(block, index,
                  style: const TextStyle(fontSize: 13.5, fontFamily: 'monospace', color: BentoTheme.textPrimary),
                  hint: 'Escribe tu código aquí...'),
            ],
          ),
        );
      case BlockType.table:
        return _buildTableWidget(block, index);
    }
  }

  Widget _buildTextField(EditorBlock block, int index,
      {required TextStyle style, required String hint}) {
    return Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) {
          setState(() {
            _focusedBlockIndex = index;
          });
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
      ),
    );
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
          color: BentoTheme.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BentoTheme.borderMuted, width: 2),
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
                    const Text(
                      'TABLA',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: BentoTheme.textPrimary),
                    ),
                  ],
                ),
                Text(
                  '${rowsCount}x$colsCount',
                  style: const TextStyle(fontSize: 11, color: BentoTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const FixedColumnWidth(100),
                border: TableBorder.all(
                  color: BentoTheme.borderMuted,
                  width: 1.5,
                  borderRadius: BorderRadius.circular(8),
                ),
                children: List.generate(rowsCount, (rIndex) {
                  final rowCtrls = block.cellControllers[rIndex];
                  final isHeader = rIndex == 0;

                  return TableRow(
                    decoration: BoxDecoration(
                      color: isHeader ? widget.accentColor.withOpacity(0.08) : null,
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
                            color: BentoTheme.textPrimary,
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
          color: BentoTheme.bgLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: BentoTheme.borderMuted),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: BentoTheme.textPrimary),
            const SizedBox(width: 2),
            Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: BentoTheme.textPrimary)),
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
      decoration: const BoxDecoration(
        color: BentoTheme.cardBg,
        border: Border(top: BorderSide(color: BentoTheme.borderMuted, width: 1.5)),
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
    final finalColor = color ?? BentoTheme.textPrimary;
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
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: BentoTheme.textPrimary,
                ),
                decoration: const InputDecoration(
                  hintText: 'Sin título',
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
                color: BentoTheme.borderMuted,
              ),
              const SizedBox(height: 16),
              // Lista de bloques editables
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _blocks.length,
                itemBuilder: (context, index) {
                  final block = _blocks[index];
                  final isFocused = _focusedBlockIndex == index;

                  return Container(
                    key: ValueKey(block.id),
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: isFocused ? widget.accentColor.withOpacity(0.03) : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
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
                                  : BentoTheme.textSecondary.withOpacity(0.3),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _buildBlockField(block, index),
                        ),
                      ],
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
