import 'package:flutter/material.dart';

/// Igual que [IndexedStack], pero solo construye el subárbol de un hijo la
/// primera vez que su índice es seleccionado. Una vez construido, el hijo
/// permanece montado (mismo comportamiento de retención de estado que
/// [IndexedStack] al cambiar de índice), evitando que todos los hijos
/// disparen su inicialización (p.ej. providers que hacen fetch) de una sola vez.
class LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final AlignmentGeometry alignment;
  final StackFit sizing;

  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.alignment = AlignmentDirectional.topStart,
    this.sizing = StackFit.loose,
  });

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  late final Set<int> _builtIndices = {widget.index};

  @override
  void didUpdateWidget(covariant LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      _builtIndices.add(widget.index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      alignment: widget.alignment,
      sizing: widget.sizing,
      children: [
        // TickerMode apaga las animaciones (llamas, loaders…) de los tabs que
        // no están visibles: IndexedStack los mantiene montados y sus tickers
        // seguirían corriendo a 60fps en segundo plano. Al volver al tab, sus
        // animaciones se reanudan solas.
        for (int i = 0; i < widget.children.length; i++)
          if (_builtIndices.contains(i))
            TickerMode(enabled: i == widget.index, child: widget.children[i])
          else
            const SizedBox.shrink(),
      ],
    );
  }
}
