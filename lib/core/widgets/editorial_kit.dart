import 'package:flutter/material.dart';

import '../theme/editorial_theme.dart';

/// Piezas compartidas del sistema editorial.
///
/// Nacieron privadas dentro de la pestaña de Hábitos. Al llegar la segunda
/// pantalla editorial (Notas) se sacaron acá en vez de copiarlas: son las
/// piezas donde el sistema se define —cómo responde algo al dedo, qué material
/// es un modal, cómo se ve una opción elegida— y dos copias divergen a la
/// primera corrección.
///
/// Regla que gobierna todo el archivo: **un solo material por plano**. Sobre el
/// lienzo oscuro las piezas son de papel; dentro del papel, los escalones son
/// grises de la escala ([EditorialTheme.gray] / [EditorialTheme.grayStrong]),
/// nunca tinta con alfa. Ver el comentario de `gray` en [EditorialTheme]: una
/// tinta cálida diluida ensucia el gris hacia el beige.

/// Respuesta táctil de todo lo que se toca.
///
/// Baja rápido y sube con calma: es lo que hace que algo se sienta físico en
/// vez de elástico. No hay ripple ni resalte de color — en un sistema sin
/// sombras, el único recurso de feedback disponible es la escala.
class EditorialPressable extends StatefulWidget {
  const EditorialPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.scale = 0.96,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  @override
  State<EditorialPressable> createState() => _EditorialPressableState();
}

class _EditorialPressableState extends State<EditorialPressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: Duration(milliseconds: _down ? 90 : 240),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Botón circular de papel sobre el lienzo. La acción de una cabecera.
class EditorialCircleButton extends StatelessWidget {
  const EditorialCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.busy = false,
    this.size = 42,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;
  final double size;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: EditorialPressable(
        onTap: onTap,
        scale: 0.90,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? EditorialTheme.paper : EditorialTheme.paperAlpha(0.22),
          ),
          child: Center(
            child: busy
                ? SizedBox(
                    width: size * 0.38,
                    height: size * 0.38,
                    child: const CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: EditorialTheme.ink,
                    ),
                  )
                : Icon(
                    icon,
                    size: size * 0.48,
                    color: enabled ? EditorialTheme.ink : EditorialTheme.inkAlpha(0.35),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Filete de separación DENTRO del papel. Un solo píxel del gris fuerte: es un
/// remate, no una estructura, y por eso nunca lleva alfa ni margen propio.
class EditorialRule extends StatelessWidget {
  const EditorialRule({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: indent),
        child: const SizedBox(
          height: 1,
          width: double.infinity,
          child: ColoredBox(color: EditorialTheme.grayStrong),
        ),
      );
}

/// Etiqueta de sección dentro de una hoja: versalitas chicas sobre papel.
///
/// Va de a una por bloque. Ver la regla 3 de [EditorialTheme]: las versalitas
/// chicas envejecen una pantalla si se reparten por todos lados.
class EditorialSectionLabel extends StatelessWidget {
  const EditorialSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: EditorialTheme.label(11, color: EditorialTheme.grayText),
            ),
          ),
          ?trailing,
        ],
      );
}

/// Opción de un grupo excluyente, sobre papel.
///
/// Apagada es un bloque gris; elegida es tinta plena con el texto en papel. La
/// inversión ES la selección: sin sombras ni bordes que la marquen, el contraste
/// de área es el único recurso que se lee de un vistazo. [accent] sólo entra
/// cuando el color significa algo (una prioridad, un color de bóveda); si no,
/// se deja en null y la elección se pinta en tinta.
class EditorialChoice extends StatelessWidget {
  const EditorialChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.accent,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fill = selected ? (accent ?? EditorialTheme.ink) : EditorialTheme.gray;
    final on = selected ? EditorialTheme.paper : EditorialTheme.grayText;

    return EditorialPressable(
      onTap: onTap,
      scale: 0.94,
      child: AnimatedContainer(
        duration: EditorialTheme.motion,
        curve: EditorialTheme.curve,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 8 : 11,
        ),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: compact ? 14 : 16, color: on),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: EditorialTheme.text(
                  compact ? 12.5 : 13.5,
                  weight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: on,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila accionable dentro de una hoja: bloque gris a ancho completo con icono,
/// texto y un remate a la derecha. Es el control de "esto lleva a otro sitio o
/// abre un selector".
class EditorialRow extends StatelessWidget {
  const EditorialRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.accent,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tone = active ? (accent ?? EditorialTheme.ink) : EditorialTheme.grayText;

    return EditorialPressable(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: EditorialTheme.gray,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: tone),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: EditorialTheme.text(
                  14,
                  weight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? EditorialTheme.ink : EditorialTheme.grayText,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Botón principal de una hoja: tinta plena, texto de papel, ancho completo.
class EditorialButton extends StatelessWidget {
  const EditorialButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.tone,
    this.ghost = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  /// Color de la acción. Por defecto tinta; se cambia sólo cuando el color
  /// significa algo (rojo = destruye).
  final Color? tone;

  /// Sin relleno: el mismo botón en su registro secundario.
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? EditorialTheme.ink;
    final enabled = onTap != null;

    return EditorialPressable(
      onTap: onTap,
      scale: 0.97,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: ghost ? EditorialTheme.gray : color.withValues(alpha: enabled ? 1 : 0.35),
          borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: ghost ? color : EditorialTheme.paper),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: EditorialTheme.text(
                14.5,
                weight: FontWeight.w600,
                color: ghost ? color : EditorialTheme.paper,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Campo de texto sobre papel: bloque gris, sin borde y sin etiqueta flotante.
///
/// La etiqueta va FUERA, arriba, en versalitas. Un `InputDecoration` con label
/// animada mete un segundo lenguaje tipográfico (Material) en una pantalla que
/// no lo usa en ningún otro sitio.
class EditorialField extends StatelessWidget {
  const EditorialField({
    super.key,
    required this.controller,
    required this.hint,
    this.autofocus = false,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.prefix,
    this.suffix,
  });

  final TextEditingController controller;
  final String hint;
  final bool autofocus;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? prefix;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EditorialTheme.gray,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (prefix != null) ...[prefix!, const SizedBox(width: 10)],
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              maxLines: maxLines,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              cursorColor: EditorialTheme.ink,
              style: EditorialTheme.text(15, color: EditorialTheme.ink),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                hintText: hint,
                hintStyle: EditorialTheme.text(15, color: EditorialTheme.grayText),
              ),
            ),
          ),
          if (suffix != null) ...[const SizedBox(width: 8), suffix!],
        ],
      ),
    );
  }
}

/// Hoja modal: una lámina de papel que sube desde abajo.
///
/// El modal es papel y no lienzo oscuro a propósito. En este sistema el papel
/// es "lo que estás manipulando ahora" y el lienzo es el fondo donde eso vive;
/// una hoja oscura sobre un fondo oscuro necesitaría un borde para existir, que
/// es exactamente el recurso que el sistema no usa.
Future<T?> showEditorialSheet<T>({
  required BuildContext context,
  required String title,
  required Widget Function(BuildContext context, StateSetter setSheetState) builder,
  double maxHeightFactor = 0.86,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (innerContext, setSheetState) => Padding(
        // El teclado empuja la hoja en vez de taparla: dentro hay campos de
        // texto en casi todas.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(innerContext).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(innerContext).height * maxHeightFactor,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: EditorialTheme.paper,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(EditorialTheme.radiusPanel),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: EditorialTheme.grayStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                  child: Text(
                    title.toUpperCase(),
                    style: EditorialTheme.caps(
                      22,
                      color: EditorialTheme.ink,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                Flexible(child: builder(innerContext, setSheetState)),
                SizedBox(height: MediaQuery.viewPaddingOf(innerContext).bottom + 14),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Confirmación destructiva, en el mismo material que las hojas.
Future<bool> confirmEditorial(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Eliminar',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => Dialog(
      backgroundColor: EditorialTheme.paper,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: EditorialTheme.caps(21, color: EditorialTheme.ink, letterSpacing: -0.5),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: EditorialTheme.text(14, color: EditorialTheme.grayText, height: 1.45),
            ),
            const SizedBox(height: 20),
            EditorialButton(
              label: confirmLabel,
              tone: const Color(0xFFB3261E),
              onTap: () => Navigator.of(ctx).pop(true),
            ),
            const SizedBox(height: 8),
            EditorialButton(
              label: 'Cancelar',
              ghost: true,
              onTap: () => Navigator.of(ctx).pop(false),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

/// Aviso breve, en papel. El SnackBar por defecto llega con el tema de
/// Material —esquinas, sombra y tipografía ajenas— y rompe la pantalla justo
/// cuando el usuario está mirando.
void showEditorialSnack(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Color? tone,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: EditorialTheme.text(14, color: tone ?? EditorialTheme.ink),
      ),
      backgroundColor: EditorialTheme.paper,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 1600),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 104),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
      ),
      action: action,
    ),
  );
}
