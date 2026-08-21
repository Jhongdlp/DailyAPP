import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/alarm_model.dart';
import '../../core/providers/alarms_provider.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/widgets/editorial_kit.dart';

/// Tarjeta de alarma en el sistema editorial.
///
/// Lo que cambia respecto de la versión neumórfica es sobre todo **cómo se
/// dice que una alarma está apagada**. Antes el estado se repartía entre cinco
/// sitios: una campana que se balanceaba sola, el naranja del AM/PM, el color
/// de la hora, el del nombre y el del interruptor. Con cinco señales para un
/// booleano ninguna manda, y la lista se vuelve un mosaico donde cuesta ver de
/// un vistazo cuáles van a sonar mañana.
///
/// Aquí el estado es **una sola cosa: el peso de la tinta**. Encendida, la hora
/// es tinta plena y la tarjeta es papel; apagada, todo el bloque baja al gris
/// de la escala. El interruptor confirma, no informa.
///
/// La campana animada se quitó. En un sistema sin sombras el movimiento es el
/// recurso más fuerte que queda, y gastarlo en una decoración que se repite en
/// cada fila deja la lista temblando; el movimiento se reserva para lo que
/// responde al dedo.
class AlarmCardEditorial extends ConsumerWidget {
  const AlarmCardEditorial({super.key, required this.alarm, required this.onTap});

  final AlarmModel alarm;
  final VoidCallback onTap;

  /// Rojo fijo, igual que en el resto del sistema: destruir tiene que decir lo
  /// mismo con cualquier paleta elegida.
  static final Color _destructive =
      EditorialTheme.accentAt(const Color(0xFFE5484D), 0.52);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = alarm.enabled;
    // Un solo par de tonos gobierna la tarjeta entera. Definirlos acá y no en
    // cada Text es lo que garantiza que el estado se lea como un bloque y no
    // como cinco decisiones sueltas.
    final strong = on ? EditorialTheme.ink : EditorialTheme.grayText;
    final soft = on ? EditorialTheme.grayText : EditorialTheme.grayStrong;

    return Dismissible(
      key: Key('editorial_alarm_${alarm.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: _destructive,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
        ),
        child: const Icon(Icons.delete_outline, color: EditorialTheme.paper, size: 22),
      ),
      confirmDismiss: (_) async {
        return await confirmEditorial(
          context,
          title: 'ELIMINAR ALARMA',
          body: 'Se borra "${alarm.label}". No se puede deshacer.',
        );
      },
      onDismissed: (_) async {
        try {
          await ref.read(alarmsProvider.notifier).deleteAlarm(alarm.id);
        } catch (e) {
          if (context.mounted) {
            showEditorialSnack(context, 'No se pudo eliminar: $e', tone: _destructive);
          }
        }
      },
      child: EditorialPressable(
        onTap: onTap,
        scale: 0.985,
        child: AnimatedContainer(
          duration: EditorialTheme.motion,
          curve: EditorialTheme.curve,
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
          decoration: BoxDecoration(
            // Apagada, la tarjeta también baja de material: papel para lo que
            // va a sonar, gris para lo que está guardado.
            color: on ? EditorialTheme.paper : EditorialTheme.gray,
            borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    alarm.isSleepAlarm
                        ? _sleepRange(strong, soft)
                        : _time(strong, soft),
                    const SizedBox(height: 8),
                    Text(
                      alarm.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EditorialTheme.text(
                        15,
                        weight: FontWeight.w600,
                        color: strong,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      alarm.isSleepAlarm
                          ? '${alarm.daysLabel}  ·  ${alarm.sleepWindowLabel} en la cama'
                          : alarm.daysLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EditorialTheme.text(13, color: soft),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        // La cuenta atrás sólo tiene sentido si va a ocurrir:
                        // en una alarma apagada es un dato falso.
                        if (on && alarm.untilLabel != null)
                          _tag(Icons.schedule, alarm.untilLabel!, strong: true),
                        _tag(Icons.camera_alt_outlined, alarm.targetObject),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Switch.adaptive(
                value: on,
                activeThumbColor: EditorialTheme.paper,
                activeTrackColor: EditorialTheme.ink,
                inactiveThumbColor: EditorialTheme.paper,
                inactiveTrackColor: EditorialTheme.grayStrong,
                trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
                onChanged: (value) async {
                  try {
                    await ref.read(alarmsProvider.notifier).toggleAlarm(alarm.id, value);
                  } catch (e) {
                    if (context.mounted) {
                      showEditorialSnack(context, 'No se pudo actualizar: $e',
                          tone: _destructive);
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// La hora, que es el titular de la tarjeta. El AM/PM va en gris y a un
  /// tamaño que no compite: forma parte de la cifra, no es un dato aparte.
  Widget _time(Color strong, Color soft) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          alarm.time12,
          style: EditorialTheme.caps(
            44,
            color: strong,
            letterSpacing: -2,
            height: 1.0,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          alarm.amPm,
          style: EditorialTheme.text(15, weight: FontWeight.w600, color: soft),
        ),
      ],
    );
  }

  /// "11:00 PM → 7:00 AM": el rango entero, con el despertar grande porque es
  /// el único de los dos extremos que suena.
  Widget _sleepRange(Color strong, Color soft) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            '${alarm.bedtime12} ${alarm.bedtimeAmPm}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EditorialTheme.text(19, weight: FontWeight.w500, color: soft),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Icon(Icons.arrow_forward, size: 13, color: soft),
        ),
        Flexible(
          child: Text(
            '${alarm.time12} ${alarm.amPm}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EditorialTheme.caps(
              28,
              color: strong,
              letterSpacing: -1,
              height: 1.0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _tag(IconData icon, String text, {bool strong = false}) {
    final color = strong ? EditorialTheme.ink : EditorialTheme.grayText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        // Dentro de una tarjeta apagada (que ya es gris) la etiqueta sube a
        // papel para no desaparecer: el escalón se invierte, no se borra.
        color: alarm.enabled ? EditorialTheme.gray : EditorialTheme.paper,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: EditorialTheme.text(11.5, weight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
