import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/editorial_theme.dart';

/// Vidrio líquido: la única superficie del sistema editorial que sí flota.
///
/// El sistema editorial es plano a propósito —tres tonos, cero sombras— pero
/// esa regla habla de cómo se separan los planos *dentro* de una página. Una
/// pieza que se queda quieta encima del contenido que se desplaza no es otro
/// plano de la misma página: es una capa aparte, y necesita leerse como tal.
/// De ahí el vidrio, y de ahí que sea la excepción a la regla de "sin sombra".
///
/// La receta tiene cuatro ingredientes y los cuatro hacen falta. Si se quita
/// uno, deja de leerse como vidrio y pasa a leerse como un rectángulo
/// semitransparente, que es otra cosa:
///
///  1. **Desenfoque** del fondo. Es lo que dice "hay material aquí".
///  2. **Saturación** por encima de 1. Un vidrio real concentra el color de lo
///     que hay detrás; un desenfoque a secas lo promedia hacia el gris y el
///     resultado se ve sucio, no traslúcido.
///  3. **Tinte oscuro**, no claro. Sobre el lienzo `#191919` un tinte crema
///     casi no se ve, y sobre una tarjeta de papel blanco desaparece del todo.
///     Con tinte oscuro la pieza mantiene el mismo peso pase lo que pase por
///     debajo, y los iconos claros conservan su contraste siempre.
///  4. **Filete de luz en el canto**, y en degradado. El canto uniforme se lee
///     como borde dibujado; el canto que va de brillante arriba-izquierda a
///     tenue abajo-derecha se lee como el grosor del material atrapando la luz.
///     Es el detalle más barato de todos y el que hace la mitad del efecto.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    required this.borderRadius,
    this.blur = 18,
    this.tint,
    this.padding = EdgeInsets.zero,
    this.lift = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;

  /// Tinte del vidrio. Por defecto, el lienzo a media opacidad.
  final Color? tint;

  final EdgeInsets padding;

  /// Sombra de despegue. Se apaga cuando la pieza ya está apoyada contra un
  /// velo oscuro (una hoja modal), donde la sombra no separa nada y sólo
  /// ensucia el canto.
  final bool lift;

  /// Saturación del fondo antes de desenfocarlo (punto 2 de la receta): la
  /// matriz de luminancia Rec. 709 con el factor en 1.5. Va escrita a mano y
  /// no calculada para que sea `const` y no se rearme en cada fotograma.
  static const ColorFilter _saturate = ColorFilter.matrix(<double>[
    1.3935, -0.3575, -0.036, 0, 0, //
    -0.1065, 1.1425, -0.036, 0, 0, //
    -0.1065, -0.3575, 1.464, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    // 0.62 no es un número redondo por casualidad: con menos, una tarjeta de
    // papel pasando por debajo blanquea la barra entera y los iconos claros se
    // quedan sin contraste; con más, deja de leerse traslúcida y vuelve a ser
    // una barra opaca con las esquinas redondeadas.
    final fill = tint ?? EditorialTheme.canvas.withValues(alpha: 0.62);

    final glass = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        // El orden importa: primero desenfoca, después satura. Al revés se
        // saturan píxeles que después se promedian y el efecto se pierde.
        filter: ui.ImageFilter.compose(
          outer: _saturate,
          inner: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            // OJO: el tinte va compuesto DENTRO del degradado, no en `color`.
            // `BoxDecoration` ignora `color` en cuanto hay `gradient`, así que
            // ponerlos por separado pinta sólo el brillo y deja el vidrio sin
            // tintar: la barra se blanquea entera cuando pasa una tarjeta de
            // papel por detrás y los iconos se pierden.
            //
            // El degradado es el brillo especular: la cara superior del vidrio
            // recibe la luz. Es el mismo gesto que el filete, repartido sobre
            // la superficie.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(EditorialTheme.paperAlpha(0.07), fill),
                Color.alphaBlend(EditorialTheme.paperAlpha(0.015), fill),
                fill,
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: lift
              ? [
                  // Difusa y baja. La sombra acá no dibuja una forma, sólo
                  // ocluye: dice a qué distancia está la pieza del contenido.
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.30),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: CustomPaint(
          foregroundPainter: _GlassRimPainter(borderRadius),
          child: glass,
        ),
      ),
    );
  }
}

/// El canto del vidrio. Va como pintor y no como `Border` porque un borde
/// uniforme no puede tener degradado, y el degradado ES el efecto.
class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter(this.radius);

  final BorderRadius radius;

  static const double _width = 1.1;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect).deflate(_width / 2);

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _width
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            EditorialTheme.paperAlpha(0.38),
            EditorialTheme.paperAlpha(0.07),
            EditorialTheme.paperAlpha(0.18),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassRimPainter old) => old.radius != radius;
}
