import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/alarms_provider.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/widgets/editorial_kit.dart';
import '../pomodoro/widgets/tomato_button.dart';
import 'alarm_card_editorial.dart';
import 'alarm_form_editorial.dart';
import 'sleep/sleep_alarm_form_editorial.dart';
import 'sleep/sleep_summary_editorial.dart';

/// Pestaña de Alarma en el sistema editorial.
///
/// La composición sigue el mismo orden que la versión neumórfica —resumen de
/// sueño arriba, acción del ciclo debajo, lista de alarmas al pie— porque ese
/// orden es correcto: el sueño es contexto y las alarmas son lo que se
/// administra. Lo que cambia es el reparto de peso.
///
/// La cabecera anterior era un "Alarma" de 42px sobre un fondo con manchas de
/// color, seguido de una fila de tres controles distintos (diagnóstico,
/// pomodoro, "Nueva") apretados en la esquina. Ahora el titular incorpora el
/// dato —cuántas alarmas hay y cuándo suena la próxima—, y sólo quedan dos
/// acciones: el temporizador y crear.
///
/// El botón de diagnóstico de notificaciones no existe en esta versión: era
/// una herramienta de depuración en la pantalla que más se mira a diario.
class AlarmTabEditorial extends ConsumerWidget {
  const AlarmTabEditorial({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarmsAsync = ref.watch(alarmsProvider);
    final alarms = alarmsAsync.value ?? const [];

    return ColoredBox(
      color: EditorialTheme.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, ref, alarms.length, _nextRing(ref)),
          // El sueño vive aquí y no en una pestaña propia: la hora de dormir y
          // la de despertar son los dos extremos del mismo ciclo, y la alarma
          // ya es el único punto donde el usuario piensa en él.
          const SleepSummaryEditorial(),
          // "Voy a dormir" cuando se acerca la hora y "Ya desperté" mientras
          // haya una noche abierta. Es la vía que no depende de que la
          // notificación siga en la bandeja.
          const SleepActionEditorial(),
          Expanded(
            child: alarmsAsync.when(
              loading: () => const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: EditorialTheme.paper,
                  ),
                ),
              ),
              error: (e, _) => _error(ref),
              data: (list) => list.isEmpty ? _empty(context) : _list(context, list),
            ),
          ),
        ],
      ),
    );
  }

  /// Texto de la próxima alarma que va a sonar. Recorre sólo las encendidas y
  /// se queda con la que antes dispare — que no tiene por qué ser la primera
  /// de la lista, porque la lista va por orden de creación.
  String? _nextRing(WidgetRef ref) {
    final alarms = ref.read(alarmsProvider).value ?? const [];
    DateTime? soonest;
    for (final alarm in alarms) {
      if (!alarm.enabled) continue;
      final next = alarm.nextTrigger();
      if (next == null) continue;
      if (soonest == null || next.isBefore(soonest)) soonest = next;
    }
    if (soonest == null) return null;

    final diff = soonest.difference(DateTime.now());
    if (diff.inDays > 0) return 'PRÓXIMA EN ${diff.inDays} D ${diff.inHours % 24} H';
    if (diff.inHours > 0) {
      return 'PRÓXIMA EN ${diff.inHours} H ${diff.inMinutes % 60} MIN';
    }
    return 'PRÓXIMA EN ${diff.inMinutes} MIN';
  }

  Widget _header(BuildContext context, WidgetRef ref, int count, String? nextRing) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EditorialTheme.margin,
        10,
        EditorialTheme.margin,
        16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ALARMAS',
                  style: EditorialTheme.caps(
                    36,
                    color: EditorialTheme.paper,
                    letterSpacing: -1.2,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  // El dato útil es cuándo suena la siguiente; el total sólo
                  // sirve cuando no hay ninguna programada.
                  nextRing ??
                      (count == 0
                          ? 'NINGUNA TODAVÍA'
                          : count == 1
                              ? '1 ALARMA, NINGUNA ACTIVA'
                              : '$count ALARMAS, NINGUNA ACTIVA'),
                  style: EditorialTheme.label(10.5, color: EditorialTheme.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // El pomodoro vive aquí porque es lo otro que cuenta tiempo. Va con
          // su propio widget y no se repinta: es una pieza compartida con la
          // pestaña de enfoque.
          const Padding(
            padding: EdgeInsets.only(top: 8, right: 12),
            child: TomatoButton(size: 26),
          ),
          EditorialCircleButton(
            icon: Icons.add,
            tooltip: 'Nueva alarma',
            onTap: () => _pickKind(context, ref),
          ),
        ],
      ),
    );
  }

  /// "Nueva" significa dos cosas y hay que elegir. Sin este paso, el horario de
  /// sueño sólo se podría crear desde su propio panel y quedaría escondido para
  /// quien vive en esta pestaña.
  void _pickKind(BuildContext context, WidgetRef ref) {
    final existingSleep = ref.read(sleepAlarmProvider);

    showEditorialSheet<void>(
      context: context,
      title: 'Nueva',
      maxHeightFactor: 0.5,
      builder: (sheetContext, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _KindOption(
              icon: Icons.alarm,
              title: 'Alarma',
              subtitle: 'Suena a una hora y se apaga con una foto.',
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AlarmFormEditorial()),
                );
              },
            ),
            const SizedBox(height: 10),
            _KindOption(
              icon: Icons.bedtime_outlined,
              title: 'Horario de sueño',
              subtitle: existingSleep != null
                  ? 'Ya tienes uno: se abrirá para editarlo.'
                  : 'De la hora de dormir a la de despertar. Sólo suena por la '
                      'mañana y registra cuánto duermes.',
              onTap: () {
                Navigator.of(sheetContext).pop();
                SleepAlarmFormEditorial.open(context, alarm: existingSleep);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List list) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        EditorialTheme.margin,
        14,
        EditorialTheme.margin,
        130,
      ),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => AlarmCardEditorial(
        alarm: list[i],
        onTap: () => list[i].isSleepAlarm
            ? SleepAlarmFormEditorial.open(context, alarm: list[i])
            : Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AlarmFormEditorial(alarm: list[i]),
                ),
              ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(EditorialTheme.margin, 24, EditorialTheme.margin, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ninguna alarma todavía',
            style: EditorialTheme.text(
              20,
              weight: FontWeight.w600,
              color: EditorialTheme.paper,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'La alarma no se apaga sola: para callarla tienes que fotografiar '
            'un objeto que elijas tú, y la IA comprueba que sea el correcto.',
            style: EditorialTheme.text(15, color: EditorialTheme.muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _error(WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(EditorialTheme.margin),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No pude cargar las alarmas',
              textAlign: TextAlign.center,
              style: EditorialTheme.text(
                17,
                weight: FontWeight.w600,
                color: EditorialTheme.paper,
              ),
            ),
            const SizedBox(height: 16),
            EditorialPressable(
              onTap: () => ref.invalidate(alarmsProvider),
              scale: 0.95,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: EditorialTheme.paper,
                  borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
                ),
                child: Text(
                  'Reintentar',
                  style: EditorialTheme.text(
                    14,
                    weight: FontWeight.w600,
                    color: EditorialTheme.ink,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Una de las dos cosas que puede crear "Nueva".
class _KindOption extends StatelessWidget {
  const _KindOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return EditorialPressable(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 15, 14, 15),
        decoration: BoxDecoration(
          color: EditorialTheme.gray,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: EditorialTheme.ink),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: EditorialTheme.text(
                      15.5,
                      weight: FontWeight.w600,
                      color: EditorialTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: EditorialTheme.text(
                      12.5,
                      color: EditorialTheme.grayText,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, size: 16, color: EditorialTheme.inkAlpha(0.3)),
          ],
        ),
      ),
    );
  }
}
