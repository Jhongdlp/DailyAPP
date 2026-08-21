import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/alarm_model.dart';
import '../../../core/models/sleep_model.dart';
import '../../../core/providers/alarms_provider.dart';
import '../../../core/providers/sleep_provider.dart';
import '../../../core/theme/editorial_theme.dart';
import '../../../core/widgets/editorial_kit.dart';
import 'sleep_alarm_form_editorial.dart';
import 'sleep_check_in_screen.dart';
import 'sleep_dashboard_screen.dart';
import 'widgets/sleep_chart_shell.dart';

/// El sueño dentro de la pestaña Alarma, en el sistema editorial: la tarjeta de
/// resumen y el botón que cierra el ciclo a mano.
///
/// Van en el mismo archivo porque son una sola pieza partida en dos: la tarjeta
/// dice en qué punto del ciclo estás y el botón es lo que haces al respecto.
/// Tenerlos separados hacía que cada uno decidiera por su cuenta cómo llamar al
/// mismo estado.
///
/// **La barra de catorce noches deja de ser un semáforo.** En la versión
/// anterior cada noche se pintaba de verde, naranja o rojo según la meta, y con
/// catorce en fila el resultado era una tira de colores donde la información
/// —cuánto dormiste— quedaba enterrada bajo un juicio. Aquí la altura de cada
/// barra ES la duración y el tono sólo separa "llegué a la meta" de "no
/// llegué": se lee el dato primero y la valoración después.
class SleepSummaryEditorial extends ConsumerWidget {
  const SleepSummaryEditorial({super.key});

  static const _nights = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(sleepProvider);
    final analytics = ref.watch(sleepAnalyticsProvider);
    final sleepAlarm = ref.watch(sleepAlarmProvider);

    // El horario existe si existe su alarma. Quien venga de la versión con
    // horario suelto ve el aviso de configuración con su hora ya puesta.
    if (sleepAlarm == null && !analytics.hasData) return const _SetupPrompt();

    final nights = data.lastNights(_nights);
    final goal = data.schedule.goalMinutes;
    final debt = analytics.sleepDebtMinutes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(EditorialTheme.margin, 4, EditorialTheme.margin, 0),
      child: EditorialPressable(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SleepDashboardScreen()),
        ),
        // Atajo de desarrollo para poder ver los gráficos con datos.
        onLongPress: kDebugMode
            ? () => ref.read(sleepProvider.notifier).seedDemoNights(30)
            : null,
        scale: 0.985,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
          decoration: BoxDecoration(
            // Superficie y no papel: la tarjeta de sueño convive con la lista
            // de alarmas, que sí es de papel. Si las dos fueran del mismo
            // material, el resumen competiría con lo que hay que accionar.
            color: EditorialTheme.surface,
            borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.bedtime_outlined, size: 15, color: EditorialTheme.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _status(data, sleepAlarm),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EditorialTheme.text(
                        13,
                        weight: FontWeight.w600,
                        color: EditorialTheme.paperAlpha(0.9),
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward, size: 15, color: EditorialTheme.muted),
                ],
              ),
              const SizedBox(height: 14),
              _NightBars(nights: nights, goal: goal),
              const SizedBox(height: 14),
              Row(
                children: [
                  _metric(formatSleepMinutes(analytics.avg7), 'media 7'),
                  _metric(
                    debt == 0 ? '0' : '−${formatSleepMinutes(debt)}',
                    'deuda 14',
                  ),
                  _metric('${analytics.goalStreak}', 'racha en meta'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(String value, String label) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: EditorialTheme.text(
                15,
                weight: FontWeight.w600,
                color: EditorialTheme.paper,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label.toUpperCase(),
              style: EditorialTheme.label(9, color: EditorialTheme.muted),
            ),
          ],
        ),
      );

  /// Una sola frase que responde "¿en qué punto del ciclo estoy?".
  ///
  /// El orden de los casos es de urgencia: una comprobación de vigilia en pie
  /// manda sobre todo lo demás, porque significa que acabas de levantarte y
  /// todavía no está claro que sigas despierto.
  String _status(SleepData data, AlarmModel? sleepAlarm) {
    final check = data.wakeCheck;
    if (check != null) {
      final mins = check.dueAt.difference(DateTime.now()).inMinutes;
      return mins > 0
          ? 'Comprobación de vigilia en $mins min'
          : 'Comprobación de vigilia en marcha';
    }

    final open = data.openNight;
    if (open?.lightsOutAt != null) {
      final at = open!.lightsOutAt!;
      return 'Durmiendo desde las ${_hhmm(at)}';
    }

    final last = data.lastCompleteNight;
    if (last != null && last.nightKey == nightKeyFor(DateTime.now())) {
      final quality = last.quality;
      return 'Anoche: ${formatSleepMinutes(last.sleepMinutes)}'
          '${quality == null ? '' : '  ·  calidad $quality/5'}';
    }

    final next = sleepAlarm?.nextBedtime();
    if (next != null) {
      final diff = next.difference(DateTime.now());
      final hours = diff.inHours;
      final mins = diff.inMinutes % 60;
      return 'Te toca dormir en ${hours > 0 ? '$hours h $mins min' : '$mins min'}';
    }

    return 'Calidad de sueño';
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Catorce noches como barras de altura variable.
///
/// La altura la fija la duración contra un techo de diez horas, no contra la
/// noche más larga: con un máximo relativo, dormir cinco horas catorce noches
/// seguidas dibujaría barras llenas y el gráfico mentiría.
class _NightBars extends StatelessWidget {
  const _NightBars({required this.nights, required this.goal});

  final List<({DateTime day, SleepSession? session})> nights;
  final int goal;

  /// Techo de la escala, en minutos. Diez horas: por encima de eso la barra se
  /// satura, que es información suficiente ("dormiste muchísimo").
  static const int _ceiling = 600;

  static const double _height = 34;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < nights.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Tooltip(
                message: '${shortDayLabel(nights[i].day)}: '
                    '${formatSleepMinutes(nights[i].session?.sleepMinutes)}',
                child: _bar(nights[i].session?.sleepMinutes),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bar(int? minutes) {
    // Noche sin dato: una marca mínima al pie. No es cero horas de sueño, es
    // una noche sin registrar, y tiene que verse distinto de una mala.
    if (minutes == null) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 3,
          decoration: BoxDecoration(
            color: EditorialTheme.paperAlpha(0.12),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
    }

    final ratio = (minutes / _ceiling).clamp(0.12, 1.0);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: _height * ratio,
        decoration: BoxDecoration(
          // Dos tonos, no tres: llegaste a la meta o no. El "casi" de la
          // versión anterior no cambiaba ninguna decisión y añadía un color.
          color: minutes >= goal
              ? EditorialTheme.paper
              : EditorialTheme.paperAlpha(0.30),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _SetupPrompt extends StatelessWidget {
  const _SetupPrompt();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(EditorialTheme.margin, 4, EditorialTheme.margin, 0),
      child: EditorialPressable(
        onTap: () => SleepAlarmFormEditorial.open(context),
        scale: 0.985,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          decoration: BoxDecoration(
            color: EditorialTheme.surface,
            borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
          ),
          child: Row(
            children: [
              Icon(Icons.bedtime_outlined, size: 20, color: EditorialTheme.muted),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Calidad de sueño',
                      style: EditorialTheme.text(
                        14.5,
                        weight: FontWeight.w600,
                        color: EditorialTheme.paper,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Pon tu hora de dormir y empieza a medir cuánto descansas.',
                      style: EditorialTheme.text(
                        12.5,
                        color: EditorialTheme.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, size: 15, color: EditorialTheme.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// **Voy a dormir** / **Ya desperté**: las dos acciones que cierran el ciclo a
/// mano, sin depender de que la notificación siga en la bandeja.
class SleepActionEditorial extends ConsumerStatefulWidget {
  const SleepActionEditorial({super.key, this.alwaysVisible = false});

  /// En el panel de Calidad de sueño se muestra siempre (deja acostarse antes
  /// de hora); en la pestaña de alarmas sólo cuando toca, para no dejar un
  /// botón grande ocupando sitio todo el día.
  final bool alwaysVisible;

  @override
  ConsumerState<SleepActionEditorial> createState() => _SleepActionEditorialState();
}

class _SleepActionEditorialState extends ConsumerState<SleepActionEditorial> {
  bool _busy = false;
  Timer? _ticker;

  /// Cuánto antes de la hora de dormir aparece el botón solo.
  static const _windowBefore = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    // El botón depende de la hora actual y no sólo del estado: sin este latido
    // no aparecería hasta que algo más provocara un rebuild.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _goToSleep() async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    await ref.read(sleepProvider.notifier).confirmBedtime();
    if (!mounted) return;
    setState(() => _busy = false);
    showEditorialSnack(context, 'Buenas noches. Ciclo de sueño iniciado.');
  }

  Future<void> _wakeUp() async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();

    // Pasar la alarma de sueño arranca la comprobación de vigilia, igual que
    // apagar la alarma con la foto.
    final session = await ref
        .read(sleepProvider.notifier)
        .registerWake(alarmId: ref.read(sleepAlarmProvider)?.id);

    if (!mounted) return;
    setState(() => _busy = false);

    if (session?.timeInBed != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SleepCheckInScreen(nightKey: session!.nightKey),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(sleepProvider);
    final sleepAlarm = ref.watch(sleepAlarmProvider);

    final open = data.openNight;
    final sleeping = open?.lightsOutAt != null && open?.wokeAt == null;

    if (sleeping) {
      final since = open!.lightsOutAt!;
      return _ActionButton(
        icon: Icons.wb_sunny_outlined,
        label: 'Ya desperté',
        caption: 'Dormiste desde las '
            '${since.hour.toString().padLeft(2, '0')}:'
            '${since.minute.toString().padLeft(2, '0')}',
        busy: _busy,
        onTap: _wakeUp,
      );
    }

    final todayDone = data.sessions[nightKeyFor(DateTime.now())]?.wokeAt != null;
    final untilBedtime = sleepAlarm?.nextBedtime()?.difference(DateTime.now());
    final nearBedtime = untilBedtime != null && untilBedtime <= _windowBefore;

    if (!widget.alwaysVisible && !nearBedtime) return const SizedBox.shrink();
    if (widget.alwaysVisible && sleepAlarm == null) return const SizedBox.shrink();

    String? caption;
    if (untilBedtime != null) {
      final mins = untilBedtime.inMinutes;
      if (mins <= 0) {
        caption = 'Ya pasó tu hora de dormir';
      } else if (mins < 60) {
        caption = 'Te toca dormir en $mins min';
      } else if (todayDone || widget.alwaysVisible) {
        caption = 'Tu hora es a las ${sleepAlarm!.formattedBedtime}';
      }
    }

    return _ActionButton(
      icon: Icons.bedtime_outlined,
      label: 'Voy a dormir',
      caption: caption,
      busy: _busy,
      onTap: _goToSleep,
    );
  }
}

/// Papel pleno sobre el lienzo: es la inversión máxima del sistema, y esta es
/// la única acción de la pantalla que tiene hora. Los dos botones comparten
/// aspecto a propósito — son el mismo gesto en los dos extremos de la noche, y
/// darles colores distintos los convertiría en dos funciones sin relación.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onTap,
    this.caption,
  });

  final IconData icon;
  final String label;
  final String? caption;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(EditorialTheme.margin, 10, EditorialTheme.margin, 0),
      child: EditorialPressable(
        onTap: busy ? null : onTap,
        scale: 0.97,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          decoration: BoxDecoration(
            color: EditorialTheme.paper,
            borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
          ),
          child: Row(
            children: [
              if (busy)
                const SizedBox(
                  width: 21,
                  height: 21,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: EditorialTheme.ink,
                  ),
                )
              else
                Icon(icon, size: 21, color: EditorialTheme.ink),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: EditorialTheme.text(
                        17,
                        weight: FontWeight.w600,
                        color: EditorialTheme.ink,
                        height: 1.1,
                      ),
                    ),
                    if (caption != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        caption!,
                        style: EditorialTheme.text(12, color: EditorialTheme.grayText),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
