import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/editorial_theme.dart';
import '../../../core/widgets/editorial_kit.dart';

/// Rueda de hora en el sistema editorial.
///
/// Misma mecánica que `bento_time_picker.dart` —dos ruedas infinitas y AM/PM al
/// lado, sin abrir ningún diálogo—, recompuesta para vivir sobre papel.
///
/// ## La regla que gobierna esta pieza
///
/// **Todo lo que se lee es tinta sobre papel, en todo momento.** Suena obvio y
/// es justo lo que falló en la primera versión: la banda de selección se pintó
/// en tinta y los números en papel, de modo que el número centrado se leía
/// blanco sobre oscuro… y los otros seis quedaban blancos sobre el papel del
/// panel, es decir, invisibles. Peor todavía durante el arrastre: cualquier
/// número a medio camino de entrar en la banda quedaba del color equivocado
/// contra el fondo que le tocara.
///
/// Una rueda no puede permitirse eso, porque su información no es sólo el
/// número elegido: es **ver de dónde vienes y adónde vas**. Si los vecinos no
/// se leen, la rueda deja de ser una rueda y pasa a ser un número con dos
/// flechas invisibles.
///
/// De ahí las tres decisiones:
///
///  1. **La banda de selección es gris, no tinta.** Un escalón de la escala
///     ([EditorialTheme.gray]) rematado por dos filetes. Marca el renglón
///     activo sin obligar a que el texto cambie de color al cruzarla.
///  2. **La jerarquía la lleva el texto, no el fondo.** El número elegido va en
///     tinta plena y semibold; los vecinos, en el gris de texto. Los dos se
///     leen; sólo uno manda.
///  3. **Los minutos tienen atajos.** Llegar a `:45` girando de uno en uno son
///     cuarenta y cinco pasos con retorno háptico en cada uno. Cuatro chips
///     resuelven el 90% de los casos reales y la rueda queda para el resto.
class EditorialTimePicker extends StatefulWidget {
  const EditorialTimePicker({
    super.key,
    required this.initialTime,
    required this.onChanged,
  });

  final TimeOfDay initialTime;
  final ValueChanged<TimeOfDay> onChanged;

  /// Color de la cifra elegida y de las vecinas.
  ///
  /// Públicos porque son el contrato de legibilidad de la pieza, y hay un test
  /// que comprueba que ambos superan 4.5:1 contra [EditorialTheme.paper]. Sin
  /// esa red, "atenuar un poco los vecinos" vuelve a dejarlos invisibles a la
  /// primera pasada de ajuste fino.
  static const Color selectedColor = EditorialTheme.ink;

  /// Gris propio de esta pieza, un paso más oscuro que
  /// [EditorialTheme.grayText].
  ///
  /// El gris de texto del sistema está calibrado para párrafos sobre papel y da
  /// 4.48:1 — suficiente ahí, pero la banda de selección es gris, no blanca, y
  /// sobre ella cae a 3.96:1. Como las cifras vecinas atraviesan la banda al
  /// girar, tienen que aguantar el fondo MÁS oscuro de los dos. Este tono da
  /// 5.77:1 sobre papel y 5.10:1 sobre la banda, y sigue a 2.13:1 de la tinta,
  /// que es lo que lo mantiene distinguible de la cifra elegida.
  static const Color neighborColor = Color(0xFF666662);

  @override
  State<EditorialTimePicker> createState() => _EditorialTimePickerState();
}

class _EditorialTimePickerState extends State<EditorialTimePicker> {
  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minuteCtrl;
  late int _hour12;
  late int _minute;
  late bool _pm;

  /// Alto de cada renglón, y también el de la banda de selección: si no
  /// coinciden, la cifra activa queda descentrada dentro de su propio resalte y
  /// la pieza entera se ve descalibrada.
  static const double _itemExtent = 52;

  /// Minutos a los que se llega de un toque. Son los cuatro que la gente usa de
  /// verdad al poner una alarma.
  static const List<int> _quickMinutes = [0, 15, 30, 45];

  @override
  void initState() {
    super.initState();
    final t = widget.initialTime;
    _hour12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    _minute = t.minute;
    _pm = t.period == DayPeriod.pm;
    _hourCtrl = FixedExtentScrollController(initialItem: _hour12 - 1);
    _minuteCtrl = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minuteCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    final hour24 =
        _pm ? (_hour12 == 12 ? 12 : _hour12 + 12) : (_hour12 == 12 ? 0 : _hour12);
    widget.onChanged(TimeOfDay(hour: hour24, minute: _minute));
  }

  /// Salta a un minuto concreto animando la rueda.
  ///
  /// Anima en vez de saltar porque el salto seco rompe la ilusión de que el
  /// chip y la rueda son el mismo control: viéndola girar hasta el destino,
  /// queda claro que el atajo hizo lo mismo que habrías hecho a mano.
  void _jumpToMinute(int minute) {
    if (_minute == minute) return;
    HapticFeedback.selectionClick();
    _minuteCtrl.animateToItem(
      minute,
      duration: const Duration(milliseconds: 320),
      curve: EditorialTheme.curve,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 172,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // La banda envuelve SÓLO las dos ruedas. Cuando abarcaba el Stack
              // entero se colaba por detrás de AM/PM y sugería que esos botones
              // eran otro renglón girable, que es justo lo que no son.
              Stack(
                alignment: Alignment.center,
                children: [
                  _selectionBand(),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _wheel(
                        controller: _hourCtrl,
                        itemCount: 12,
                        labelOf: (i) => '${i + 1}',
                        selectedIndex: _hour12 - 1,
                        semanticsLabel: 'Hora',
                        onSelected: (i) {
                          setState(() => _hour12 = i + 1);
                          _notify();
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          ':',
                          style: EditorialTheme.caps(
                            34,
                            color: EditorialTimePicker.selectedColor,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      _wheel(
                        controller: _minuteCtrl,
                        itemCount: 60,
                        labelOf: (i) => i.toString().padLeft(2, '0'),
                        selectedIndex: _minute,
                        semanticsLabel: 'Minutos',
                        onSelected: (i) {
                          setState(() => _minute = i);
                          _notify();
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _period('AM', false),
                  const SizedBox(height: 8),
                  _period('PM', true),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _quickMinuteRow(),
      ],
    );
  }

  /// La banda: relleno gris entre dos filetes.
  ///
  /// Los filetes hacen el trabajo que antes hacía la inversión. Un relleno gris
  /// suelto sobre papel es un cambio de 14 niveles —deliberadamente sutil, ver
  /// [EditorialTheme.gray]— y por sí solo no se lee como "el renglón activo";
  /// con los dos filetes pasa a leerse como un visor, que es lo que es.
  Widget _selectionBand() {
    return Positioned(
      left: -6,
      right: -6,
      child: Container(
        height: _itemExtent,
        decoration: BoxDecoration(
          color: EditorialTheme.gray,
          borderRadius: BorderRadius.circular(12),
          border: const Border.symmetric(
            horizontal: BorderSide(color: EditorialTheme.grayStrong, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int) labelOf,
    required int selectedIndex,
    required String semanticsLabel,
    required ValueChanged<int> onSelected,
  }) {
    return SizedBox(
      width: 78,
      child: Semantics(
        label: semanticsLabel,
        value: labelOf(selectedIndex),
        child: ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: _itemExtent,
          physics: const FixedExtentScrollPhysics(),
          perspective: 0.004,
          diameterRatio: 1.7,
          // 1.0: la atenuación de los vecinos la da su COLOR, no una capa de
          // opacidad. Con opacidad, el gris de texto se lavaba hasta salirse
          // del contraste mínimo justo en los renglones que hay que poder leer.
          overAndUnderCenterOpacity: 1,
          onSelectedItemChanged: (i) {
            HapticFeedback.selectionClick();
            onSelected(i);
          },
          childDelegate: ListWheelChildLoopingListDelegate(
            children: [
              for (var i = 0; i < itemCount; i++)
                Center(
                  child: Text(
                    labelOf(i),
                    style: EditorialTheme.caps(
                      i == selectedIndex ? 36 : 30,
                      color: i == selectedIndex
                          ? EditorialTimePicker.selectedColor
                          : EditorialTimePicker.neighborColor,
                      weight: i == selectedIndex ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: -1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _period(String label, bool pm) {
    final active = _pm == pm;
    return EditorialPressable(
      onTap: () {
        if (_pm == pm) return;
        HapticFeedback.selectionClick();
        setState(() => _pm = pm);
        _notify();
      },
      scale: 0.9,
      child: AnimatedContainer(
        duration: EditorialTheme.motion,
        curve: EditorialTheme.curve,
        width: 54,
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? EditorialTheme.ink : EditorialTheme.gray,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: EditorialTheme.text(
            14,
            weight: FontWeight.w600,
            // Aquí sí hay inversión, y aquí sí funciona: el bloque es opaco y
            // el texto nunca lo desborda, así que el fondo bajo cada letra es
            // siempre conocido.
            color: active ? EditorialTheme.paper : EditorialTheme.grayText,
          ),
        ),
      ),
    );
  }

  Widget _quickMinuteRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final minute in _quickMinutes) ...[
          if (minute != _quickMinutes.first) const SizedBox(width: 7),
          EditorialChoice(
            label: ':${minute.toString().padLeft(2, '0')}',
            compact: true,
            selected: _minute == minute,
            onTap: () => _jumpToMinute(minute),
          ),
        ],
      ],
    );
  }
}
