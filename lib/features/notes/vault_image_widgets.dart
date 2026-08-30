import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/models/note_vault_model.dart';
import '../../core/services/signed_url_cache.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/theme/editorial_theme.dart';

/// Renderiza una imagen cruda soportando URLs de internet, rutas locales de archivo
/// y rutas de almacenamiento en Supabase (`exercise-photos`).
class VaultRawImage extends StatelessWidget {
  final String path;
  final BoxFit fit;

  const VaultRawImage({
    super.key,
    required this.path,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) return const SizedBox.shrink();

    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: fit,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 24),
        ),
      );
    } else if (path.startsWith('/')) {
      final file = File(path);
      if (!file.existsSync()) {
        return const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 24),
        );
      }
      return Image.file(
        file,
        fit: fit,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 24),
        ),
      );
    } else {
      return FutureBuilder<String>(
        future: SignedUrlCache.get('exercise-photos', path),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null && snapshot.data!.isNotEmpty) {
            return Image.network(
              snapshot.data!,
              fit: fit,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 24),
              ),
            );
          }
          if (snapshot.hasError) {
            return const Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 24),
            );
          }
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
            ),
          );
        },
      );
    }
  }
}

/// Widget para mostrar la imagen de una bóveda con su transformación (offset y zoom).
class VaultImageWidget extends StatelessWidget {
  final NoteVault vault;
  final BoxFit fit;

  const VaultImageWidget({
    super.key,
    required this.vault,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final path = vault.imagePath;
    if (path == null || path.isEmpty) {
      return const SizedBox.shrink();
    }

    return Transform(
      transform: Matrix4.identity()
        ..translate(vault.imageOffsetX, vault.imageOffsetY)
        ..scale(vault.imageScale),
      alignment: Alignment.center,
      child: VaultRawImage(path: path, fit: fit),
    );
  }
}

/// Resultado retornado por el popup selector y ajustador de portada.
class VaultCoverResult {
  final String? imagePath;
  final double offsetX;
  final double offsetY;
  final double scale;
  final File? newFile;
  final bool clearImage;

  const VaultCoverResult({
    this.imagePath,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.scale = 1.0,
    this.newFile,
    this.clearImage = false,
  });
}

/// Abre el popup/diálogo interactivo para seleccionar y ajustar la foto de portada.
Future<VaultCoverResult?> showVaultCoverPickerDialog({
  required BuildContext context,
  String? currentImagePath,
  double initialOffsetX = 0.0,
  double initialOffsetY = 0.0,
  double initialScale = 1.0,
  File? initialFile,
  String vaultName = 'Mi Bóveda',
  String? vaultDescription,
  String vaultIcon = 'folder',
  String vaultColor = '#758BFD',
  bool showIcon = true,
  int noteCount = 0,
  bool isEditorial = false,
}) {
  return showDialog<VaultCoverResult>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (ctx) => VaultCoverEditorDialog(
      initialImagePath: currentImagePath,
      initialOffsetX: initialOffsetX,
      initialOffsetY: initialOffsetY,
      initialScale: initialScale,
      initialUploadFile: initialFile,
      vaultName: vaultName,
      vaultDescription: vaultDescription,
      vaultIcon: vaultIcon,
      vaultColor: vaultColor,
      showIcon: showIcon,
      noteCount: noteCount,
      isEditorial: isEditorial,
    ),
  );
}

/// Diálogo modal con barra lateral de miniaturas (para borrar/subir)
/// y vista previa exacta de la carta con ajuste de arrastre y zoom.
class VaultCoverEditorDialog extends StatefulWidget {
  final String? initialImagePath;
  final double initialOffsetX;
  final double initialOffsetY;
  final double initialScale;
  final File? initialUploadFile;
  final String vaultName;
  final String? vaultDescription;
  final String vaultIcon;
  final String vaultColor;
  final bool showIcon;
  final int noteCount;
  final bool isEditorial;

  const VaultCoverEditorDialog({
    super.key,
    this.initialImagePath,
    this.initialOffsetX = 0.0,
    this.initialOffsetY = 0.0,
    this.initialScale = 1.0,
    this.initialUploadFile,
    this.vaultName = 'Mi Bóveda',
    this.vaultDescription,
    this.vaultIcon = 'folder',
    this.vaultColor = '#758BFD',
    this.showIcon = true,
    this.noteCount = 0,
    this.isEditorial = false,
  });

  @override
  State<VaultCoverEditorDialog> createState() => _VaultCoverEditorDialogState();
}

class _VaultCoverEditorDialogState extends State<VaultCoverEditorDialog> {
  final List<String> _thumbnails = [];
  String? _selectedPath;
  File? _newFile;
  late double _offsetX;
  late double _offsetY;
  late double _scale;

  double _startScale = 1.0;

  @override
  void initState() {
    super.initState();
    _selectedPath = widget.initialImagePath;
    _offsetX = widget.initialOffsetX;
    _offsetY = widget.initialOffsetY;
    _scale = widget.initialScale;
    _newFile = widget.initialUploadFile;

    if (_selectedPath != null && _selectedPath!.isNotEmpty) {
      _thumbnails.add(_selectedPath!);
    }

    _loadExistingImages();
  }

  Future<void> _loadExistingImages() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final files = docs.listSync().whereType<File>().where((f) {
        final p = f.path.toLowerCase();
        return p.endsWith('.jpg') ||
            p.endsWith('.png') ||
            p.endsWith('.jpeg') ||
            p.endsWith('.webp');
      }).toList();

      files.sort((a, b) {
        try {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        } catch (_) {
          return 0;
        }
      });

      for (final f in files) {
        if (!_thumbnails.contains(f.path)) {
          _thumbnails.add(f.path);
        }
      }

      if (mounted) setState(() {});
    } catch (_) {}
  }

  Color get _accentColor {
    try {
      final hex = widget.vaultColor.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return const Color(0xFF758BFD);
    }
  }

  Future<void> _pickNewImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (picked != null) {
      setState(() {
        if (!_thumbnails.contains(picked.path)) {
          _thumbnails.insert(0, picked.path);
        }
        _selectedPath = picked.path;
        _newFile = File(picked.path);
        _offsetX = 0.0;
        _offsetY = 0.0;
        _scale = 1.0;
      });
    }
  }

  void _removeThumbnail(String path) {
    setState(() {
      _thumbnails.remove(path);
      if (_selectedPath == path) {
        if (_thumbnails.isNotEmpty) {
          _selectedPath = _thumbnails.first;
          _newFile = File(_selectedPath!);
          _offsetX = 0.0;
          _offsetY = 0.0;
          _scale = 1.0;
        } else {
          _selectedPath = null;
          _newFile = null;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isCompact = screenSize.width < 450;
    final accent = _accentColor;
    final iconData = vaultIconMap[widget.vaultIcon] ?? Icons.folder_rounded;

    return Dialog(
      backgroundColor: const Color(0xFF141416),
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: screenSize.height * 0.90,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── Header ───
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.tune_rounded, color: accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Foto de Portada',
                          style: GoogleFonts.montserrat(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'Ajusta la posición y zoom en tu tarjeta',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 14),

              // ─── Body: Sidebar + Live Card Canvas ───
              Flexible(
                child: isCompact ? _buildCompactBody(accent, iconData) : _buildWideBody(accent, iconData),
              ),

              const SizedBox(height: 14),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 12),

              // ─── Bottom Actions ───
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop(
                        VaultCoverResult(
                          imagePath: _selectedPath,
                          offsetX: _offsetX,
                          offsetY: _offsetY,
                          scale: _scale,
                          newFile: _newFile,
                          clearImage: _selectedPath == null || _selectedPath!.isEmpty,
                        ),
                      );
                    },
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Aplicar Portada', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: const Color(0xFF0C0C0D),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Layout horizontal estándar con sidebar a la izquierda
  Widget _buildWideBody(Color accent, IconData iconData) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Sidebar izquierdo de miniaturas ───
        SizedBox(
          width: 86,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'IMÁGENES',
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Colors.white38,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // Botón de subir (+)
                    _buildAddButton(accent),
                    const SizedBox(height: 10),
                    // Miniaturas
                    ..._thumbnails.map((path) => _buildThumbnailItem(path, accent)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Container(width: 1, color: Colors.white10),
        const SizedBox(width: 14),

        // ─── Centro: Tarjeta interactiva de la carta ───
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCardViewport(accent, iconData),
                const SizedBox(height: 10),
                _buildControls(accent),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Layout compacto para pantallas muy estrechas
  Widget _buildCompactBody(Color accent, IconData iconData) {
    return Column(
      children: [
        // Tira horizontal de miniaturas
        SizedBox(
          height: 72,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildAddButton(accent, compact: true),
              const SizedBox(width: 8),
              ..._thumbnails.map((path) => _buildThumbnailItem(path, accent, compact: true)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildCardViewport(accent, iconData),
                const SizedBox(height: 8),
                _buildControls(accent),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Botón "+" para subir nueva foto desde la galería
  Widget _buildAddButton(Color accent, {bool compact = false}) {
    return InkWell(
      onTap: _pickNewImage,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: compact ? 64 : double.infinity,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accent.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_rounded, color: accent, size: 22),
            const SizedBox(height: 2),
            Text(
              'Subir',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Ítem individual de miniatura con botón de eliminar
  Widget _buildThumbnailItem(String path, Color accent, {bool compact = false}) {
    final isSelected = _selectedPath == path;

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 0 : 10, right: compact ? 8 : 0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedPath = path;
                _newFile = File(path);
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: compact ? 64 : double.infinity,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? accent : Colors.white24,
                  width: isSelected ? 2.5 : 1.0,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.35),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: VaultRawImage(
                  path: path,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          // Botón de borrar miniatura
          Positioned(
            top: -4,
            right: -4,
            child: GestureDetector(
              onTap: () => _removeThumbnail(path),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Vista previa de la carta con proporciones exactas y gestos de arrastre/zoom
  Widget _buildCardViewport(Color accent, IconData iconData) {
    final name = widget.vaultName.trim().isEmpty ? 'Mi Bóveda' : widget.vaultName.trim();
    final count = widget.noteCount;
    final hasImage = _selectedPath != null && _selectedPath!.isNotEmpty;

    return Center(
      child: Container(
        width: 220,
        height: 200,
        decoration: BoxDecoration(
          color: widget.isEditorial ? EditorialTheme.paper : const Color(0xFF1E1E22),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accent.withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (details) {
            _startScale = _scale;
          },
          onScaleUpdate: (details) {
            if (!hasImage) return;
            setState(() {
              if (details.scale != 1.0) {
                _scale = (_startScale * details.scale).clamp(0.2, 5.0);
              }
              _offsetX += details.focalPointDelta.dx;
              _offsetY += details.focalPointDelta.dy;
            });
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ─── Capa de fondo: Imagen transformada ───
              if (hasImage)
                Positioned.fill(
                  child: Center(
                    child: Transform(
                      transform: Matrix4.identity()
                        ..translate(_offsetX, _offsetY)
                        ..scale(_scale),
                      alignment: Alignment.center,
                      child: VaultRawImage(
                        path: _selectedPath!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.image_outlined,
                        size: 38,
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sin imagen de portada',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),

              // ─── Capa superior: Contenido exacto de la carta ───
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.showIcon) ...[
                            Icon(iconData, size: 16, color: accent),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: widget.isEditorial && !hasImage
                                    ? EditorialTheme.ink
                                    : BentoTheme.cream,
                                shadows: hasImage
                                    ? [
                                        const Shadow(
                                          color: Colors.black87,
                                          blurRadius: 4.0,
                                          offset: Offset(1.0, 1.0),
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (widget.vaultDescription != null &&
                          widget.vaultDescription!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.vaultDescription!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: widget.isEditorial && !hasImage
                                ? EditorialTheme.grayText
                                : BentoTheme.creamAlpha(0.65),
                            shadows: hasImage
                                ? [
                                    const Shadow(
                                      color: Colors.black87,
                                      blurRadius: 4.0,
                                      offset: Offset(1.0, 1.0),
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        count == 1 ? '1 NOTA' : '$count NOTAS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: widget.isEditorial && !hasImage
                              ? EditorialTheme.grayText
                              : BentoTheme.creamSecondary,
                          shadows: hasImage
                              ? [
                                  const Shadow(
                                    color: Colors.black87,
                                    blurRadius: 4.0,
                                    offset: Offset(1.0, 1.0),
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ─── Pill indicador de gestos ───
              if (hasImage)
                Positioned(
                  bottom: 8,
                  left: 8,
                  right: 8,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.70),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_with_rounded, size: 11, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Arrastra y pellizca para encuadrar',
                            style: TextStyle(color: Colors.white, fontSize: 9.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Barra de controles de zoom, reset y opciones de quitar imagen
  Widget _buildControls(Color accent) {
    final hasImage = _selectedPath != null && _selectedPath!.isNotEmpty;

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.zoom_out, size: 16, color: Colors.white60),
              tooltip: 'Alejar',
              onPressed: hasImage
                  ? () => setState(() => _scale = math.max(0.2, _scale - 0.15))
                  : null,
            ),
            Expanded(
              child: Slider(
                value: _scale.clamp(0.2, 5.0),
                min: 0.2,
                max: 5.0,
                activeColor: accent,
                inactiveColor: Colors.white12,
                onChanged: hasImage
                    ? (val) {
                        setState(() => _scale = val);
                      }
                    : null,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.zoom_in, size: 16, color: Colors.white60),
              tooltip: 'Acercar',
              onPressed: hasImage
                  ? () => setState(() => _scale = math.min(5.0, _scale + 0.15))
                  : null,
            ),
            const SizedBox(width: 4),
            Text(
              '${_scale.toStringAsFixed(1)}x',
              style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.restart_alt_rounded, size: 17, color: Colors.white60),
              tooltip: 'Restablecer posición y zoom',
              onPressed: hasImage
                  ? () {
                      setState(() {
                        _offsetX = 0.0;
                        _offsetY = 0.0;
                        _scale = 1.0;
                      });
                    }
                  : null,
            ),
          ],
        ),
        if (hasImage)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedPath = null;
                  _newFile = null;
                  _offsetX = 0.0;
                  _offsetY = 0.0;
                  _scale = 1.0;
                });
              },
              icon: const Icon(Icons.delete_outline_rounded, color: BentoTheme.errorRed, size: 15),
              label: const Text(
                'Quitar portada de esta tarjeta',
                style: TextStyle(color: BentoTheme.errorRed, fontSize: 11.5),
              ),
            ),
          ),
      ],
    );
  }
}

/// Mantiene compatibilidad con cualquier llamada existente a `VaultImageAdjuster`
class VaultImageAdjuster extends StatelessWidget {
  final String imagePath;
  final double initialOffsetX;
  final double initialOffsetY;
  final double initialScale;
  final void Function(double offsetX, double offsetY, double scale) onChanged;

  const VaultImageAdjuster({
    super.key,
    required this.imagePath,
    required this.initialOffsetX,
    required this.initialOffsetY,
    required this.initialScale,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: VaultRawImage(path: imagePath, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Foto seleccionada',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Toca "Ajustar portada" para encuadrar y escalar',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
