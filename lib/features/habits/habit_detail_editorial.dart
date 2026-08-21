import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';

import '../../core/models/habit_model.dart';
import '../../core/network/local_ai_client.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/utils/error_snackbar.dart';
import '../../core/widgets/editorial_kit.dart';
import 'habit_form_editorial.dart';

/// Ficha de un hábito, en el sistema editorial.
///
/// Es la pantalla que más cambió respecto de la versión neumórfica, y no por
/// gusto: aquella era una rejilla de cuatro tarjetitas de estadística donde
/// racha, mejor racha, cumplimiento y total pesaban exactamente lo mismo. Con
/// todo al mismo tamaño no hay ficha, hay panel de control.
///
/// Acá la jerarquía es explícita y de arriba abajo:
///
///  1. **La racha manda.** Es el número que la gente viene a mirar, y ocupa la
///     mitad de la primera lámina en tipografía de titular. Lo demás son notas
///     al pie de ese número.
///  2. **Lo de hoy es lo accionable.** Si el hábito tiene meta, el control de
///     progreso va inmediatamente después: es lo único de la pantalla que se
///     toca para cambiar algo.
///  3. **El año es contexto.** El mapa va abajo, en su propia lámina, porque
///     responde a una pregunta distinta ("cómo vengo") y con otro horizonte.
///
/// El color del hábito aparece **una sola vez**: en los cuadraditos del mapa,
/// donde es dato. Mismo criterio que en la tarjeta de la lista; ver la nota de
/// `habits_tab_editorial.dart`.
class HabitDetailEditorial extends ConsumerStatefulWidget {
  const HabitDetailEditorial({super.key, required this.habitId});

  final String habitId;

  @override
  ConsumerState<HabitDetailEditorial> createState() => _HabitDetailEditorialState();
}

class _HabitDetailEditorialState extends ConsumerState<HabitDetailEditorial> {
  bool _analyzing = false;
  String? _feedback;

  static const List<String> _monthLetters = [
    'E', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D',
  ];

  @override
  Widget build(BuildContext context) {
    final habit = ref
        .watch(habitsProvider)
        .where((h) => h.id == widget.habitId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: EditorialTheme.canvas,
      body: SafeArea(
        bottom: false,
        child: habit == null ? _gone() : _content(habit),
      ),
    );
  }

  /// El hábito se borró desde esta misma pantalla (o desde otro dispositivo).
  /// Se muestra el hueco en vez de cerrar solo: un pop automático mientras el
  /// usuario está mirando se lee como un fallo.
  Widget _gone() {
    return Padding(
      padding: const EdgeInsets.all(EditorialTheme.margin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Este hábito ya no está',
            style: EditorialTheme.text(
              20,
              weight: FontWeight.w600,
              color: EditorialTheme.paper,
            ),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: EditorialCircleButton(
              icon: Icons.arrow_back,
              tooltip: 'Volver',
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(Habit habit) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        EditorialTheme.margin,
        8,
        EditorialTheme.margin,
        40,
      ),
      children: [
        _header(habit),
        const SizedBox(height: 20),
        _streakPanel(habit),
        if (habit.goalValue != null) ...[
          const SizedBox(height: 12),
          _progressPanel(habit),
        ],
        const SizedBox(height: 12),
        _yearPanel(habit),
        const SizedBox(height: 12),
        _coachPanel(habit),
      ],
    );
  }

  Widget _header(Habit habit) {
    return Row(
      children: [
        EditorialPressable(
          onTap: () => Navigator.of(context).pop(),
          scale: 0.88,
          child: Padding(
            padding: const EdgeInsets.only(right: 12, top: 6, bottom: 6),
            child: Icon(Icons.arrow_back,
                size: 21, color: EditorialTheme.paperAlpha(0.7)),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                habit.category.label.toUpperCase(),
                style: EditorialTheme.label(10.5, color: EditorialTheme.muted),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Twemoji(emoji: habit.icon, height: 22, width: 22),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      habit.name.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: EditorialTheme.caps(
                        27,
                        color: EditorialTheme.paper,
                        letterSpacing: -0.8,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        EditorialCircleButton(
          icon: Icons.more_horiz,
          tooltip: 'Opciones',
          size: 38,
          onTap: () => _showOptions(habit),
        ),
      ],
    );
  }

  /// Lámina principal: la racha en grande y el resto de cifras como pie.
  Widget _streakPanel(Habit habit) {
    final streak = habit.currentStreak();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EditorialSectionLabel('Racha actual'),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$streak',
                style: EditorialTheme.caps(
                  64,
                  color: EditorialTheme.ink,
                  letterSpacing: -3,
                  height: 0.9,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                streak == 1 ? 'día' : 'días',
                style: EditorialTheme.text(
                  18,
                  weight: FontWeight.w500,
                  color: EditorialTheme.grayText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const EditorialRule(),
          const SizedBox(height: 14),
          Row(
            children: [
              _footStat('Mejor', '${habit.bestStreak()}'),
              _footDivider(),
              _footStat('30 días', '${(habit.completionRate(days: 30) * 100).round()}%'),
              _footDivider(),
              _footStat('7 días', '${(habit.completionRate(days: 7) * 100).round()}%'),
              _footDivider(),
              _footStat('Total', '${habit.completedDates.length}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footStat(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: EditorialTheme.text(
                19,
                weight: FontWeight.w600,
                color: EditorialTheme.ink,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label.toUpperCase(),
              style: EditorialTheme.label(9.5, color: EditorialTheme.grayText),
            ),
          ],
        ),
      );

  Widget _footDivider() => Container(
        width: 1,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: EditorialTheme.grayStrong,
      );

  /// Control de progreso del día. Lo único de la ficha que escribe.
  Widget _progressPanel(Habit habit) {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final progress = habit.dailyProgress[today] ?? 0;
    final goal = habit.goalValue!;
    final ratio = (progress / goal).clamp(0.0, 1.0);
    final step = _incrementFor(habit.goalUnit);
    final unit = habit.goalUnit ?? '';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EditorialSectionLabel('Hoy'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _fmt(progress),
                        style: EditorialTheme.caps(
                          38,
                          color: EditorialTheme.ink,
                          letterSpacing: -1.4,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'de ${_fmt(goal)} $unit',
                        style: EditorialTheme.text(
                          15,
                          weight: FontWeight.w500,
                          color: EditorialTheme.grayText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _stepButton(Icons.remove, () => _bump(habit, today, -step)),
              const SizedBox(width: 8),
              _stepButton(Icons.add, () => _bump(habit, today, step), filled: true),
            ],
          ),
          const SizedBox(height: 16),
          // Barra de una sola pieza, sin radio interior: en un sistema plano el
          // relleno redondeado dentro de una pista redondeada crea dos siluetas
          // que compiten. Aquí la pista ES la forma y el relleno la recorre.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: EditorialTheme.gray)),
                  FractionallySizedBox(
                    widthFactor: ratio,
                    child: const ColoredBox(color: EditorialTheme.ink),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _bump(Habit habit, DateTime day, double delta) =>
      ref.read(habitsProvider.notifier).updateHabitProgress(habit.id, day, delta);

  Widget _stepButton(IconData icon, VoidCallback onTap, {bool filled = false}) {
    return EditorialPressable(
      onTap: onTap,
      scale: 0.88,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? EditorialTheme.ink : EditorialTheme.gray,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 19,
          color: filled ? EditorialTheme.paper : EditorialTheme.ink,
        ),
      ),
    );
  }

  /// Mapa del año: 53 columnas de 7 días, como un calendario de contribuciones.
  ///
  /// Aquí sí entra el color del hábito, y es el único sitio de la ficha donde
  /// aparece. Va normalizado con [EditorialTheme.accentAt] a la lightness del
  /// papel: el hex crudo viene de una paleta hecha para el diseño anterior y a
  /// plena viveza arrasa un sistema de tres tonos.
  Widget _yearPanel(Habit habit) {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    // La rejilla arranca en el lunes de la semana de hace 52 semanas: así la
    // fila 0 es siempre lunes y las columnas caen alineadas al calendario.
    final start = today
        .subtract(Duration(days: today.weekday - 1))
        .subtract(const Duration(days: 7 * 52));
    final accent = EditorialTheme.accentAt(habit.colorValue, 0.54);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EditorialSectionLabel('Último año'),
          const SizedBox(height: 14),
          // Se desplaza en su propio carril: 53 columnas no entran en un
          // teléfono, y encogerlas hasta que quepan deja celdas de 2px.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _monthRuler(start),
                const SizedBox(height: 4),
                Column(
                  children: [
                    for (var row = 0; row < 7; row++) ...[
                      if (row > 0) const SizedBox(height: 3),
                      Row(
                        children: [
                          for (var col = 0; col < 53; col++) ...[
                            if (col > 0) const SizedBox(width: 3),
                            _yearCell(
                              habit,
                              start.add(Duration(days: col * 7 + row)),
                              today,
                              accent,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'MENOS',
                style: EditorialTheme.label(9, color: EditorialTheme.grayText),
              ),
              const SizedBox(width: 6),
              for (final on in [false, true]) ...[
                Container(
                  width: 11,
                  height: 11,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: on ? accent : EditorialTheme.gray,
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                ),
              ],
              const SizedBox(width: 3),
              Text(
                'MÁS',
                style: EditorialTheme.label(9, color: EditorialTheme.grayText),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Inicial del mes sobre la columna donde ese mes empieza. Sin la regla, un
  /// año de cuadraditos no dice cuándo pasó nada.
  Widget _monthRuler(DateTime start) {
    return Row(
      children: [
        for (var col = 0; col < 53; col++) ...[
          if (col > 0) const SizedBox(width: 3),
          SizedBox(
            width: 11,
            child: Builder(
              builder: (_) {
                final weekStart = start.add(Duration(days: col * 7));
                // Sólo la primera columna cuyo lunes cae en los primeros siete
                // días del mes: así cada mes aparece una vez y no siete.
                final isFirstOfMonth = weekStart.day <= 7;
                return Text(
                  isFirstOfMonth ? _monthLetters[weekStart.month - 1] : '',
                  textAlign: TextAlign.center,
                  style: EditorialTheme.label(8.5, color: EditorialTheme.grayText),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _yearCell(Habit habit, DateTime day, DateTime today, Color accent) {
    final future = day.isAfter(today);
    final done = !future && habit.isCompletedOn(day);
    final scheduled = !future && habit.isActiveOn(day);

    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2.5),
        // Tres estados y no dos: "no tocaba" tiene que verse distinto de
        // "tocaba y no lo hice", o el mapa culpa por días libres.
        color: done
            ? accent
            : future
                ? EditorialTheme.paper
                : scheduled
                    ? EditorialTheme.gray
                    : EditorialTheme.paperAlpha(0),
      ),
      foregroundDecoration: !done && !future && !scheduled
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(2.5),
              border: Border.all(color: EditorialTheme.gray),
            )
          : null,
    );
  }

  /// Coach. Se pinta como una lámina aparte y no dentro del panel de racha: es
  /// texto para leer, y mezclarlo con cifras haría que ninguno de los dos se
  /// lea bien.
  Widget _coachPanel(Habit habit) {
    if (_feedback == null) {
      return EditorialPressable(
        onTap: _analyzing ? null : () => _analyze(habit),
        scale: 0.98,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: EditorialTheme.surface,
            borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
          ),
          child: _analyzing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: EditorialTheme.paper,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.psychology_outlined,
                        size: 18, color: EditorialTheme.paperAlpha(0.8)),
                    const SizedBox(width: 9),
                    Text(
                      'Analizar con IA',
                      style: EditorialTheme.text(
                        14.5,
                        weight: FontWeight.w600,
                        color: EditorialTheme.paperAlpha(0.85),
                      ),
                    ),
                  ],
                ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorialSectionLabel(
            'Coach',
            trailing: EditorialPressable(
              onTap: () => setState(() => _feedback = null),
              scale: 0.85,
              child: Icon(Icons.close, size: 17, color: EditorialTheme.grayText),
            ),
          ),
          const SizedBox(height: 10),
          MarkdownBody(
            data: _feedback!,
            shrinkWrap: true,
            styleSheet: MarkdownStyleSheet(
              p: EditorialTheme.text(15,
                  color: EditorialTheme.inkAlpha(0.85), height: 1.5),
              strong: EditorialTheme.text(15,
                  weight: FontWeight.w700, color: EditorialTheme.ink, height: 1.5),
              listBullet:
                  EditorialTheme.text(15, color: EditorialTheme.grayText),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── acciones ───────────────────────────

  void _showOptions(Habit habit) {
    showEditorialSheet<void>(
      context: context,
      title: habit.name,
      maxHeightFactor: 0.5,
      builder: (sheetContext, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EditorialRow(
              icon: Icons.edit_outlined,
              label: 'Editar hábito',
              active: true,
              onTap: () {
                Navigator.of(sheetContext).pop();
                showHabitFormEditorial(context, ref, existing: habit);
              },
            ),
            const SizedBox(height: 8),
            EditorialRow(
              icon: Icons.inventory_2_outlined,
              label: 'Archivar',
              active: true,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await ref.read(habitsProvider.notifier).archiveHabit(habit.id);
                if (mounted) Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 8),
            EditorialRow(
              icon: Icons.delete_outline,
              label: 'Eliminar',
              active: true,
              accent: _destructive,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final ok = await confirmEditorial(
                  context,
                  title: 'ELIMINAR HÁBITO',
                  body: 'Se borra "${habit.name}" y todo su historial. '
                      'No se puede deshacer.',
                );
                if (!ok || !mounted) return;
                await ref.read(habitsProvider.notifier).deleteHabit(habit.id);
                if (mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _analyze(Habit habit) async {
    setState(() {
      _analyzing = true;
      _feedback = null;
    });

    final settings = ref.read(settingsProvider);
    final prompt = StringBuffer()
      ..writeln('Hábito: "${habit.name}" (categoría: ${habit.category.label}).')
      ..writeln('Racha actual: ${habit.currentStreak()} días.')
      ..writeln('Mejor racha histórica: ${habit.bestStreak()} días.')
      ..writeln('Cumplimiento últimos 30 días: ${(habit.completionRate(days: 30) * 100).round()}%.')
      ..writeln('Cumplimiento últimos 7 días: ${(habit.completionRate(days: 7) * 100).round()}%.')
      ..writeln('Total de días completados: ${habit.completedDates.length}.')
      ..writeln(
        '\nAnaliza mi tendencia (mejorando, estancada o empeorando) y dame un '
        'consejo específico y motivador como coach de vida para sostener o '
        'mejorar este hábito.',
      );

    try {
      final client = LocalAIClient(
        baseUrl: settings.localAiUrl,
        textModelName: settings.textModel,
      );
      final response = await client.askText(
        prompt.toString(),
        systemPrompt: 'Eres un coach de productividad amigable y analítico. '
            'Responde en español de forma directa, breve, estructurada y en un '
            'tono motivador.',
      );
      if (mounted) setState(() => _feedback = response);
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, message: 'Error al conectar con la IA Local: $e');
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  // ─────────────────────────── helpers ───────────────────────────

  /// Rojo fijo, no el acento del tema: "esto destruye" tiene que decir lo mismo
  /// con cualquier paleta elegida.
  static final Color _destructive =
      EditorialTheme.accentAt(const Color(0xFFE5484D), 0.52);

  /// Cuánto suma cada toque del botón, según la unidad. Un vaso de agua, mil
  /// pasos, cinco minutos: sumar de a uno en esas unidades no sirve de nada.
  static double _incrementFor(String? unit) => switch ((unit ?? '').toLowerCase()) {
        'l' => 0.25,
        'ml' => 250,
        'pasos' || 'steps' => 1000,
        'min' || 'minutos' => 5,
        _ => 1,
      };

  static String _fmt(double v) => v % 1 == 0
      ? v.toInt().toString()
      : v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}
