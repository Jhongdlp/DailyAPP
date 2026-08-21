import 'package:flutter/widgets.dart';

/// Qué lenguaje visual pinta las pantallas que tienen más de una versión.
///
/// La app arrastra dos sistemas terminados y ninguno reemplaza al otro: el
/// neumorfismo (`BentoTheme`, superficies extruidas y sombras duales) y el
/// editorial (`EditorialTheme`, papel sobre lienzo y cero sombras). Convivían
/// eligiéndose a mano en el import de `dashboard_screen.dart`; esto lo saca al
/// usuario.
///
/// **No es un tema.** El modo claro/oscuro, la paleta y el material siguen
/// viviendo en `AppearanceState` y se aplican igual en los dos lenguajes. Esto
/// elige *qué implementación de pantalla se monta*, no qué colores usa: cada
/// pestaña con dos versiones tiene dos archivos, y este enum decide cuál.
///
/// Por eso no todas las pestañas responden: sólo las que tienen la pareja
/// hecha (hoy: Hábitos, Notas y Alarma). El resto se pinta siempre en
/// neumorfismo, que es el sistema base.
///
/// Un par de pantallas críticas —la de apagar la alarma y la del reto mental—
/// no tienen archivo aparte: llevan las dos pieles dentro del mismo `build`,
/// porque encima cuelga lógica que no puede vivir por duplicado. Ver la nota
/// en `alarm_dismiss_screen.dart`.
enum DesignLanguage {
  /// El sistema base: `BentoTheme`, `NeuCard`/`NeuPressed`, luz arriba-izquierda.
  neu(
    label: 'Relieve',
    blurb: 'Superficies extruidas y sombras suaves.',
  ),

  /// El sistema nuevo: `EditorialTheme`, papel sobre lienzo, tipografía grande.
  editorial(
    label: 'Editorial',
    blurb: 'Papel sobre lienzo, sin sombras ni relieve.',
  );

  const DesignLanguage({required this.label, required this.blurb});

  final String label;
  final String blurb;

  bool get isEditorial => this == DesignLanguage.editorial;

  static DesignLanguage byName(String? name) => values.firstWhere(
        (d) => d.name == name,
        orElse: () => defaults,
      );

  /// El que trae la app de fábrica. Editorial: es el que quedó montado en la
  /// rama de diseño y el que se sigue afinando.
  static const DesignLanguage defaults = DesignLanguage.editorial;
}

/// Elige entre dos widgets según el lenguaje activo, sin construir el descartado.
///
/// Existe para que la pareja de implementaciones se lea junta en el sitio donde
/// se decide, en vez de repartir `if (design.isEditorial)` por el árbol.
Widget byDesign(
  DesignLanguage design, {
  required Widget Function() neu,
  required Widget Function() editorial,
}) =>
    design.isEditorial ? editorial() : neu();
