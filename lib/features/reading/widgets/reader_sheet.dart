import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/reader_theme_provider.dart';

/// Abre un panel inferior con los colores del modo de lectura activo.
///
/// Los paneles del lector no usan el neumorfismo oscuro del resto de la app a
/// propósito: leyendo en modo claro o sepia, un panel oscuro deslumbra y
/// rompe la adaptación del ojo.
Future<T?> showReaderSheet<T>(
  BuildContext context, {
  required ReaderPalette palette,
  required Widget Function(BuildContext context) builder,
  bool expand = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (sheetContext) => ReaderSheetShell(
      palette: palette,
      expand: expand,
      child: Builder(builder: builder),
    ),
  );
}

class ReaderSheetShell extends StatelessWidget {
  final ReaderPalette palette;
  final Widget child;
  final bool expand;

  const ReaderSheetShell({
    super.key,
    required this.palette,
    required this.child,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: media.size.height * (expand ? 0.85 : 0.7),
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 10,
        left: 18,
        right: 18,
        bottom: 14 + media.viewInsets.bottom + media.viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.foregroundAlpha(0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// Título de sección dentro de un panel del lector.
class ReaderSheetTitle extends StatelessWidget {
  final String text;
  final ReaderPalette palette;
  final Widget? trailing;

  const ReaderSheetTitle({
    super.key,
    required this.text,
    required this.palette,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.montserrat(
              color: palette.foreground,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
