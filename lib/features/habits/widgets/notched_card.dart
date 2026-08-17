import 'package:flutter/material.dart';

/// Métricas de la tarjeta mordida. Están juntas y en un solo lugar porque las
/// comparten tres piezas que TIENEN que coincidir al píxel: la silueta que
/// recorta la tarjeta, el hueco que se le reserva al botón y el relleno que
/// aparta el título del mordisco. Si cada una llevara su número, el canal de
/// aire alrededor del botón se abriría o se cerraría solo.
class NotchMetrics {
  const NotchMetrics._();

  /// El botón es un rectángulo tumbado, no un cuadrado.
  ///
  /// Es lo que permite agrandarlo sin que vuelva a dominar la tarjeta. Un
  /// cuadrado de 46 pesaba demasiado porque el peso visual de una forma lo
  /// manda su lado *corto* contra el alto de la tarjeta: 46 de alto era un
  /// tercio de la fila. Tumbado a 52×40 el área crece un 19% respecto de aquel
  /// cuadrado y aun así baja de altura, así que se lee como control de fila y
  /// no como bloque. De paso repite la proporción del propio mordisco, que
  /// también es más ancho que alto.
  static const double buttonWidth = 58;
  static const double buttonHeight = 34;

  /// Radio del botón. ~0.32 del lado corto.
  static const double buttonRadius = 11;

  /// Cuánto sobresale el botón por encima del borde superior de la tarjeta.
  /// Es lo único que hace que se lea "por fuera" y no "hundido en un pozo".
  static const double overhang = 0;

  /// Canal de aire entre el botón y el filo del mordisco.
  ///
  /// Se probó a cero, con el botón calzado al milímetro en el hueco, y el
  /// problema es que sin luz entre las dos piezas dejan de ser dos piezas: el
  /// botón se lee como un trozo de la tarjeta pintado de otro color. Cinco
  /// píxeles alcanzan para separarlo y no tanto como para que flote suelto.
  static const double gap = 5;

  /// Cuánto crece el objetivo del dedo respecto del cuadrado visible.
  ///
  /// Crece hacia adentro de la tarjeta —abajo y a la izquierda— porque arriba y
  /// a la derecha no hay nada que ganar: es el borde de la pantalla. En la zona
  /// compartida gana el gesto del botón, y eso está bien: lo que le roba a la
  /// tarjeta es justo el canal de aire, que no es sitio de nadie.
  static const double touchPad = 6;

  /// El mordisco = botón + canal, en los dos ejes. El alto sólo cuenta la parte
  /// del botón que baja por dentro de la tarjeta.
  static const double width = buttonWidth + gap;
  static const double height = buttonHeight - overhang + gap;

  /// Espacio horizontal que el contenido tiene que cederle al mordisco antes de
  /// llegar al borde. Se usa como padding derecho del título.
  static const double contentInset = width;
}

/// Silueta de la tarjeta de hábito: rectángulo redondeado con un mordisco en la
/// esquina superior derecha.
///
/// El mordisco no es un rectángulo recortado. Sus dos quiebres llevan radio y
/// van en sentidos opuestos, y ahí está todo el efecto:
///
///  - **Arriba** el borde superior se hunde con un radio *convexo*: la tarjeta
///    se redondea igual que en cualquier esquina propia.
///  - **Abajo** el borde vuelve a salir con un radio *cóncavo* — el arco curva
///    hacia adentro del material. Es la curva que el ojo lee como "algo estaba
///    apoyado acá y se levantó", y es la única razón por la que el botón parece
///    haber salido de la tarjeta en vez de estar puesto encima.
///
/// Un mordisco de esquinas vivas se lee como un error de recorte; uno con los
/// dos radios convexos, como dos tarjetas mal apiladas.
class NotchedCardBorder extends ShapeBorder {
  const NotchedCardBorder({
    this.radius = 20,
    this.notchWidth = NotchMetrics.width,
    this.notchHeight = NotchMetrics.height,
    this.notchCorner = 8,
    this.notchFillet = 16,
  });

  /// Radio de las esquinas propias de la tarjeta.
  final double radius;

  final double notchWidth;
  final double notchHeight;

  /// Radio convexo con el que el borde superior se hunde hacia el mordisco, y
  /// con el que el piso del mordisco vuelve a salir al filo derecho.
  ///
  /// Chico a propósito. Son los dos puntos donde el filo recto de la tarjeta se
  /// cruza con una esquina redondeada del botón, y ahí no hay encastre posible:
  /// lo único que se puede hacer es que la tarjeta llegue lo más cerca que
  /// pueda. Con un radio grande esos dos cruces se abren en dos medialunas
  /// oscuras y el botón vuelve a parecer suelto.
  final double notchCorner;

  /// Radio cóncavo del vértice interno del mordisco.
  ///
  /// Bastante mayor que [NotchMetrics.buttonRadius], y no por gusto. El fillet
  /// **mete** material en el vértice, así que cuanto más grande, más se acerca
  /// el filo de la tarjeta a la esquina redondeada del botón. Con un radio
  /// parecido al del botón las dos curvas se separan en la diagonal y aparece
  /// un charco oscuro justo bajo el botón, el doble de ancho que el canal
  /// recto.
  ///
  /// El valor sale de una cuenta, no del ojo: el fillet mete material hasta
  /// `0.293·f` en la diagonal del vértice, y se busca la `f` que deja ese punto
  /// a [NotchMetrics.gap] del arco de la esquina del botón. Con el botón actual
  /// da 16. Si cambian el radio del botón, su alto o el gap, este número hay que
  /// recalcularlo o el canal deja de ser parejo.
  final double notchFillet;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final w = rect.width;
    final h = rect.height;

    // Sin ancho o alto suficientes el mordisco se comería la tarjeta entera y
    // los arcos se cruzarían: se degrada a un rectángulo redondeado normal.
    // Pasa en el primer frame de un layout, no en pantalla.
    final fits = w > notchWidth + notchCorner + notchFillet + radius * 2 &&
        h > notchHeight + radius * 2;
    if (!fits) {
      return Path()
        ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    }

    final nx = w - notchWidth; // pared izquierda del mordisco
    final ny = notchHeight; // piso del mordisco

    final path = Path()
      ..moveTo(radius, 0)
      // Borde superior hasta el arranque del mordisco.
      ..lineTo(nx - notchCorner, 0)
      // Se hunde: convexo, como una esquina cualquiera.
      ..arcToPoint(
        Offset(nx, notchCorner),
        radius: Radius.circular(notchCorner),
        clockwise: true,
      )
      // Pared del mordisco.
      ..lineTo(nx, ny - notchFillet)
      // Vuelve a salir: cóncavo. `clockwise: false` es lo que invierte la curva.
      ..arcToPoint(
        Offset(nx + notchFillet, ny),
        radius: Radius.circular(notchFillet),
        clockwise: false,
      )
      // Piso del mordisco hasta el filo derecho.
      ..lineTo(w - notchCorner, ny)
      ..arcToPoint(
        Offset(w, ny + notchCorner),
        radius: Radius.circular(notchCorner),
        clockwise: true,
      )
      // Resto de la tarjeta, ya sin sorpresas.
      ..lineTo(w, h - radius)
      ..arcToPoint(
        Offset(w - radius, h),
        radius: Radius.circular(radius),
        clockwise: true,
      )
      ..lineTo(radius, h)
      ..arcToPoint(
        Offset(0, h - radius),
        radius: Radius.circular(radius),
        clockwise: true,
      )
      ..lineTo(0, radius)
      ..arcToPoint(
        Offset(radius, 0),
        radius: Radius.circular(radius),
        clockwise: true,
      )
      ..close();

    return path.shift(rect.topLeft);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => NotchedCardBorder(
        radius: radius * t,
        notchWidth: notchWidth * t,
        notchHeight: notchHeight * t,
        notchCorner: notchCorner * t,
        notchFillet: notchFillet * t,
      );

  // Sin esto el ClipPath recalcula y repinta la silueta en cada rebuild de la
  // lista, que son muchos: la tarjeta se reconstruye en cada fotograma de la
  // animación de completar.
  @override
  bool operator ==(Object other) =>
      other is NotchedCardBorder &&
      other.radius == radius &&
      other.notchWidth == notchWidth &&
      other.notchHeight == notchHeight &&
      other.notchCorner == notchCorner &&
      other.notchFillet == notchFillet;

  @override
  int get hashCode =>
      Object.hash(radius, notchWidth, notchHeight, notchCorner, notchFillet);
}
