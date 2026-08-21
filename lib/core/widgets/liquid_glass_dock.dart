import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../models/app_destination.dart';
import '../theme/editorial_theme.dart';
import 'glass_surface.dart';

/// Dock flotante de navegación.
///
/// Antes el dock nacía del borde inferior con las esquinas superiores
/// redondeadas: esa silueta es la de una hoja modal, y el ojo la lee como algo
/// que se acaba de abrir y se va a cerrar, no como la barra permanente de la
/// app. Despegarlo del borde y cerrarle las cuatro esquinas cambia lo que
/// significa: pasa a ser un objeto que viaja por encima del contenido.
///
/// Como el contenido le sigue pasando por debajo, la pieza tiene que ser de
/// vidrio (ver [GlassSurface]): opaca taparía la última fila de cada lista y
/// convertiría el dock en un agujero negro al pie de todas las pantallas.
///
/// La selección la marca **una sola cápsula de papel que se desliza**, no un
/// fondo que se enciende en cada hueco. Es la misma regla que sostiene la
/// pantalla de hábitos —la inversión es la jerarquía— y además da continuidad:
/// el ojo sigue una pieza que se mueve, mientras que dos fondos cruzándose en
/// opacidad se leen como un parpadeo.
class LiquidGlassDock extends StatelessWidget {
  const LiquidGlassDock({
    super.key,
    required this.slots,
    required this.currentIndex,
    required this.onSelect,
    required this.onMenu,
    this.overflowActive,
  });

  /// Destinos que viven en el dock, en orden.
  final List<AppDestination> slots;

  /// Índice de pestaña activo en el stack del dashboard.
  final int currentIndex;

  final ValueChanged<AppDestination> onSelect;
  final VoidCallback onMenu;

  /// Destino activo cuando NO está en el dock (se llegó desde el menú). El
  /// dock no puede marcarlo con la cápsula, así que lo delata con un punto de
  /// su acento sobre el botón de menú: sin eso la barra se queda sin ningún
  /// hueco marcado y la pantalla parece haberse perdido.
  final AppDestination? overflowActive;

  static const double height = 62;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        // Flota por encima de la barra de gestos, nunca sobre ella: un dock que
        // invade esa franja se come el swipe de "atrás" del sistema.
        bottomInset > 0 ? bottomInset + 6 : 16,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: GlassSurface(
            borderRadius: BorderRadius.circular(height / 2),
            blur: 18,
            child: SizedBox(
              height: height,
              child: Row(
                // `stretch` no es cosmético: sin él los hijos reciben altura
                // suelta, el `Stack` de la pista se encoge a la altura de un
                // icono y la cápsula sale recortada por la mitad.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _DockTrack(
                      slots: slots,
                      selected: slots.indexWhere((d) => d.tabIndex == currentIndex),
                      onSelect: onSelect,
                    ),
                  ),
                  // Filete que separa navegación de menú. El botón de menú no
                  // es una pestaña más —no se queda seleccionado— y sin esta
                  // línea el ojo lo cuenta como el quinto destino.
                  Center(
                    child: Container(
                      width: 1,
                      height: 22,
                      color: EditorialTheme.paperAlpha(0.12),
                    ),
                  ),
                  _MenuButton(onTap: onMenu, active: overflowActive),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── la pista y su cápsula ───────────────────────────

class _DockTrack extends StatefulWidget {
  const _DockTrack({
    required this.slots,
    required this.selected,
    required this.onSelect,
  });

  final List<AppDestination> slots;

  /// Hueco marcado, o -1 si el destino activo no está en el dock.
  final int selected;

  final ValueChanged<AppDestination> onSelect;

  @override
  State<_DockTrack> createState() => _DockTrackState();
}

class _DockTrackState extends State<_DockTrack> with TickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..value = 1;

  /// Presencia de la cápsula. Va como controlador propio y no como
  /// `AnimatedOpacity` porque los iconos también lo consultan: su color no
  /// depende de cuál esté seleccionado sino de cuánta lente tienen encima.
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.selected >= 0 ? 1 : 0,
  );

  late final Listenable _repaint = Listenable.merge([_slide, _fade]);

  /// Posición en unidades de hueco: de dónde sale y a dónde va la cápsula.
  late double _from = math.max(0, widget.selected).toDouble();
  late double _to = _from;

  static const Curve _curve = Curves.easeOutCubic;

  /// Cuánto se estira la cápsula por unidad de velocidad. Ver [_stretch].
  static const double _elasticity = 0.055;
  static const double _maxStretch = 0.30;

  @override
  void didUpdateWidget(covariant _DockTrack old) {
    super.didUpdateWidget(old);
    if (widget.selected == old.selected) return;
    if (widget.selected < 0) {
      // Se navegó a un destino que no vive en el dock: la cápsula se va, no se
      // queda marcando un hueco que ya no es el actual.
      _fade.reverse();
      return;
    }
    _fade.forward();
    // Sale de donde esté AHORA, no del hueco anterior: si se toca un tercer
    // destino a mitad del viaje, la cápsula sigue de largo en vez de saltar
    // hacia atrás para volver a empezar.
    _from = _positionAt(_slide.value);
    _to = widget.selected.toDouble();
    _slide.forward(from: 0);
  }

  @override
  void dispose() {
    _slide.dispose();
    _fade.dispose();
    super.dispose();
  }

  double _positionAt(double t) => _from + (_to - _from) * _curve.transform(t.clamp(0, 1));

  /// Estiramiento en la dirección del viaje: la cápsula se alarga cuando va
  /// rápido y recupera su forma al frenar. Es lo que la vuelve líquida en vez
  /// de rígida.
  ///
  /// La velocidad se saca derivando la curva, no midiendo el desplazamiento
  /// entre fotogramas: así el efecto es idéntico a 60 y a 120 Hz.
  double _stretch(double t) {
    const eps = 0.001;
    final v = (_curve.transform((t + eps).clamp(0, 1)) -
                _curve.transform((t - eps).clamp(0, 1))) /
            (2 * eps);
    final travel = (_to - _from).abs();
    return 1 + math.min(_maxStretch, travel * v.abs() * _elasticity);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = constraints.maxWidth / widget.slots.length;
        const capsuleInset = 5.0;
        const capsuleHeight = 46.0;

        return Stack(
          // Sin `expand`, la fila de iconos no recibe la altura de la barra y
          // el `Stack` la pega arriba: los iconos quedarían por encima de la
          // cápsula en vez de dentro.
          fit: StackFit.expand,
          children: [
            // La cápsula va DEBAJO de los iconos: es superficie, no adorno.
            //
            // El `Positioned` tiene que quedar por fuera del `FadeTransition`:
            // ese sí crea render object, y un `Positioned` por dentro dejaría
            // de hablarle al `Stack`.
            AnimatedBuilder(
              animation: _slide,
              builder: (context, child) {
                final t = _slide.value;
                final stretch = _stretch(t);
                return Positioned(
                  left: _positionAt(t) * slotWidth + capsuleInset,
                  top: (LiquidGlassDock.height - capsuleHeight) / 2,
                  width: slotWidth - capsuleInset * 2,
                  height: capsuleHeight,
                  child: FadeTransition(
                    opacity: _fade,
                    child: Transform.scale(
                      scaleX: stretch,
                      // Compensa el alargue con un achatamiento a la mitad:
                      // conserva el área aparente y evita que la cápsula se
                      // vea inflada al cruzar la barra.
                      scaleY: 1 - (stretch - 1) * 0.5,
                      child: child,
                    ),
                  ),
                );
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: EditorialTheme.paper,
                  borderRadius: BorderRadius.circular(capsuleHeight / 2),
                  boxShadow: [
                    // La cápsula es una lente apoyada SOBRE el vidrio, y por
                    // eso proyecta. Sin esto, cuando pasa una tarjeta de papel
                    // por detrás el vidrio se aclara hasta casi el blanco y la
                    // cápsula desaparece justo en el momento en que más falta
                    // hace: el hueco marcado se pierde al desplazar la lista.
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < widget.slots.length; i++)
                  Expanded(
                    child: _DockIcon(
                      destination: widget.slots[i],
                      selected: i == widget.selected,
                      repaint: _repaint,
                      // Cuánta cápsula tiene este icono encima, de 0 a 1. Es lo
                      // que decide su color, así que la tinta llega exactamente
                      // cuando llega el papel: ni antes ni después.
                      coverage: () =>
                          (1 - (_positionAt(_slide.value) - i).abs()).clamp(0.0, 1.0) *
                          _fade.value,
                      onTap: () {
                        if (i == widget.selected) return;
                        HapticFeedback.selectionClick();
                        widget.onSelect(widget.slots[i]);
                      },
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DockIcon extends StatelessWidget {
  const _DockIcon({
    required this.destination,
    required this.selected,
    required this.repaint,
    required this.coverage,
    required this.onTap,
  });

  final AppDestination destination;

  /// Sólo para lectores de pantalla: lo visual lo decide [coverage].
  final bool selected;

  final Listenable repaint;
  final double Function() coverage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Sobre la cápsula de papel el icono usa la variante oscura del acento (la
    // misma receta que las tarjetas de hábitos invertidas); sobre el vidrio va
    // en crema apagada. El color aparece sólo donde marca estado.
    final active = EditorialTheme.accent(destination.accent, onDark: false);
    final idle = EditorialTheme.paperAlpha(0.60);

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedBuilder(
          animation: repaint,
          builder: (context, _) {
            final t = coverage();
            return Transform.scale(
              scale: 1 + t * 0.06,
              child: Icon(
                destination.icon,
                size: 22,
                color: Color.lerp(idle, active, t),
                // Halo oscuro bajo el glifo, y sólo mientras está sobre el
                // vidrio. El vidrio no tiene un color propio: es tan claro u
                // oscuro como lo que pase por detrás, y un icono crema sobre
                // una tarjeta de papel desenfocada se queda sin separación. El
                // halo se la pone por debajo, sin subir el brillo del icono ni
                // oscurecer la barra entera. Sobre la cápsula ya no hace falta
                // —ahí el contraste lo da el papel— y encima ensuciaría, así
                // que se apaga con la llegada de la lente.
                shadows: t < 0.99
                    ? [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.38 * (1 - t)),
                          blurRadius: 7,
                        ),
                      ]
                    : null,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MenuButton extends StatefulWidget {
  const _MenuButton({required this.onTap, this.active});

  final VoidCallback onTap;
  final AppDestination? active;

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;

    return Semantics(
      button: true,
      label: 'Más opciones',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          _spin.forward(from: 0);
          widget.onTap();
        },
        child: SizedBox(
          width: 54,
          height: LiquidGlassDock.height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RotationTransition(
                turns: Tween<double>(begin: 0, end: 0.25).animate(
                  CurvedAnimation(parent: _spin, curve: Curves.easeOutBack),
                ),
                child: Icon(
                  Icons.menu_rounded,
                  size: 22,
                  color: EditorialTheme.paperAlpha(active != null ? 0.95 : 0.60),
                  // Mismo halo que los iconos de la pista: acá nunca llega la
                  // cápsula, así que va siempre.
                  shadows: [
                    Shadow(color: Colors.black.withValues(alpha: 0.38), blurRadius: 7),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              AnimatedContainer(
                duration: EditorialTheme.motion,
                curve: EditorialTheme.curve,
                width: active != null ? 5 : 0,
                height: 5,
                decoration: BoxDecoration(
                  color: active == null
                      ? Colors.transparent
                      : EditorialTheme.accent(active.accent, onDark: true),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
