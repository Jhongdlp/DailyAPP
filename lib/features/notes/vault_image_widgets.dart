import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/note_vault_model.dart';
import '../../core/services/signed_url_cache.dart';

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

    if (path.startsWith('http://') || path.startsWith('https://')) {
      return _buildImage(Image.network(path, fit: fit));
    } else if (path.startsWith('/')) {
      final file = File(path);
      if (!file.existsSync()) {
        return const SizedBox.shrink();
      }
      return _buildImage(Image.file(file, fit: fit));
    } else {
      return FutureBuilder<String>(
        future: SignedUrlCache.get('exercise-photos', path),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return _buildImage(Image.network(snapshot.data!, fit: fit));
          }
          return const SizedBox.shrink();
        },
      );
    }
  }

  Widget _buildImage(Widget imageWidget) {
    return Transform(
      transform: Matrix4.identity()
        ..translate(vault.imageOffsetX, vault.imageOffsetY)
        ..scale(vault.imageScale),
      alignment: Alignment.center,
      child: imageWidget,
    );
  }
}

class VaultImageAdjuster extends StatefulWidget {
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
  State<VaultImageAdjuster> createState() => _VaultImageAdjusterState();
}

class _VaultImageAdjusterState extends State<VaultImageAdjuster> {
  late double _offsetX;
  late double _offsetY;
  late double _scale;

  @override
  void initState() {
    super.initState();
    _offsetX = widget.initialOffsetX;
    _offsetY = widget.initialOffsetY;
    _scale = widget.initialScale;
  }

  @override
  void didUpdateWidget(covariant VaultImageAdjuster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _offsetX = widget.initialOffsetX;
      _offsetY = widget.initialOffsetY;
      _scale = widget.initialScale;
    }
  }

  void _update() {
    widget.onChanged(_offsetX, _offsetY, _scale);
  }

  @override
  Widget build(BuildContext context) {
    Widget image;
    final path = widget.imagePath;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      image = Image.network(path, fit: BoxFit.contain);
    } else if (path.startsWith('/')) {
      image = Image.file(File(path), fit: BoxFit.contain);
    } else {
      image = FutureBuilder<String>(
        future: SignedUrlCache.get('exercise-photos', path),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Image.network(snapshot.data!, fit: BoxFit.contain);
          }
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      );
    }

    return Column(
      children: [
        Container(
          height: 120,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          clipBehavior: Clip.antiAlias,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) {
              setState(() {
                _offsetX += details.delta.dx;
                _offsetY += details.delta.dy;
              });
              _update();
            },
            child: Stack(
              clipBehavior: Clip.antiAlias,
              children: [
                Positioned.fill(
                  child: Center(
                    child: Transform(
                      transform: Matrix4.identity()
                        ..translate(_offsetX, _offsetY)
                        ..scale(_scale),
                      alignment: Alignment.center,
                      child: image,
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.drag_indicator, size: 12, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Arrastra para mover',
                          style: TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.zoom_out, size: 14, color: Colors.grey),
            Expanded(
              child: Slider(
                value: _scale,
                min: 0.2,
                max: 4.0,
                activeColor: const Color(0xFF758BFD),
                onChanged: (val) {
                  setState(() {
                    _scale = val;
                  });
                  _update();
                },
              ),
            ),
            const Icon(Icons.zoom_in, size: 14, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              '${_scale.toStringAsFixed(1)}x',
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.refresh, size: 16, color: Colors.grey),
              onPressed: () {
                setState(() {
                  _offsetX = 0;
                  _offsetY = 0;
                  _scale = 1.0;
                });
                _update();
              },
            ),
          ],
        ),
      ],
    );
  }
}
