import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/bento_theme.dart';
import 'pomodoro_palette.dart';
import 'pomodoro_screen.dart';
import 'providers/pomodoro_provider.dart';
import 'widgets/break_panels.dart';
import 'widgets/focus_task_card.dart';

/// Ritmos de partida. Un preajuste resuelve el 90 % de las veces y quita la
/// decisión de "¿cuántos minutos?" justo cuando lo único que se quiere es
/// empezar; los pasos finos siguen ahí para el 10 % restante.
class _Preset {
  final String name;
  final String hint;
  final int work;
  final int rest;
  final int longRest;

  const _Preset(this.name, this.hint, this.work, this.rest, this.longRest);
}

const _presets = <_Preset>[
  _Preset('Clásico', '25 · 5', 25, 5, 15),
  _Preset('Profundo', '50 · 10', 50, 10, 20),
  _Preset('Corto', '15 · 3', 15, 3, 10),
];

class PomodoroSetupSheet extends ConsumerStatefulWidget {
  const PomodoroSetupSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PomodoroSetupSheet(),
    );
  }

  @override
  ConsumerState<PomodoroSetupSheet> createState() => _PomodoroSetupSheetState();
}

class _PomodoroSetupSheetState extends ConsumerState<PomodoroSetupSheet> {
  late int workMin;
  late int breakMin;
  late int longBreakMin;
  late bool autoBreaks;
  late bool autoFocus;
  late int panelMode;

  String? taskId;
  String? taskTitle;

  @override
  void initState() {
    super.initState();
    // Se arranca desde lo último que usó: el ritmo propio es una preferencia,
    // no algo que reelegir cada día.
    final prefs = ref.read(pomodoroProvider).prefs;
    workMin = prefs.workDuration;
    breakMin = prefs.breakDuration;
    longBreakMin = prefs.longBreakDuration;
    autoBreaks = prefs.autoStartBreaks;
    autoFocus = prefs.autoStartFocus;
    panelMode = prefs.breakPanelMode;
  }

  bool _matchesPreset(_Preset p) =>
      workMin == p.work && breakMin == p.rest && longBreakMin == p.longRest;

  Future<void> _pickTask() async {
    final choice = await pickFocusTask(context, selectedId: taskId);
    if (choice == null) return;
    setState(() {
      taskId = choice.id;
      taskTitle = choice.title;
    });
  }

  void _start() {
    ref.read(pomodoroProvider.notifier).configure(
          workDuration: workMin,
          breakDuration: breakMin,
          longBreakDuration: longBreakMin,
          autoStartBreaks: autoBreaks,
          autoStartFocus: autoFocus,
          breakPanelMode: panelMode,
          focusedTaskId: taskId,
          focusedTaskTitle: taskTitle,
        );
    ref.read(pomodoroProvider.notifier).start();

    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PomodoroScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Container(
      // La hoja nunca pasa del 88 % de la pantalla y su cuerpo desliza: en
      // horizontal, donde el alto se queda en nada, sigue siendo usable.
      constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
      decoration: BoxDecoration(
        color: BentoTheme.neuSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: BentoTheme.neuFloating(elevation: 24),
      ),
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 14),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: BentoTheme.creamAlpha(0.18),
              borderRadius: BorderRadius.circular(100),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text('🍅', style: TextStyle(fontSize: 24)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Sesión de enfoque',
                          style: GoogleFonts.montserrat(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: BentoTheme.cream,
                            letterSpacing: -0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // ── Tarea ──
                  _SectionLabel('EN QUÉ TE ENFOCAS'),
                  const SizedBox(height: 9),
                  NeuCard(
                    borderRadius: 16,
                    distance: 3,
                    blur: 6,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    onTap: _pickTask,
                    child: Row(
                      children: [
                        Icon(
                          taskTitle == null
                              ? Icons.adjust_rounded
                              : Icons.center_focus_strong_rounded,
                          size: 18,
                          color: taskTitle == null
                              ? BentoTheme.creamAlpha(0.35)
                              : PomodoroPalette.focus,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            taskTitle ?? 'Elegir una tarea de hoy (opcional)',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: taskTitle == null
                                  ? FontWeight.w400
                                  : FontWeight.w600,
                              color: taskTitle == null
                                  ? BentoTheme.creamAlpha(0.45)
                                  : BentoTheme.creamAlpha(0.9),
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 20, color: BentoTheme.creamAlpha(0.3)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Ritmo ──
                  _SectionLabel('RITMO'),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      for (final preset in _presets) ...[
                        Expanded(
                          child: _PresetChip(
                            preset: preset,
                            selected: _matchesPreset(preset),
                            onTap: () => setState(() {
                              workMin = preset.work;
                              breakMin = preset.rest;
                              longBreakMin = preset.longRest;
                            }),
                          ),
                        ),
                        if (preset != _presets.last) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _DurationStepper(
                          title: 'ENFOQUE',
                          value: workMin,
                          color: PomodoroPalette.focus,
                          onChanged: (v) =>
                              setState(() => workMin = v.clamp(1, 120)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DurationStepper(
                          title: 'DESCANSO',
                          value: breakMin,
                          color: BentoTheme.successGreen,
                          onChanged: (v) =>
                              setState(() => breakMin = v.clamp(1, 60)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DurationStepper(
                          title: 'D. LARGO',
                          value: longBreakMin,
                          color: BentoTheme.accentPurple,
                          onChanged: (v) =>
                              setState(() => longBreakMin = v.clamp(1, 120)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Encadenado ──
                  _SectionLabel('ENCADENAR SOLO'),
                  const SizedBox(height: 9),
                  NeuCard(
                    borderRadius: 16,
                    distance: 3,
                    blur: 6,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        _SwitchRow(
                          title: 'El descanso empieza solo',
                          subtitle: 'Al acabar el enfoque, sin tocar nada',
                          value: autoBreaks,
                          onChanged: (v) => setState(() => autoBreaks = v),
                        ),
                        Divider(
                            color: BentoTheme.creamAlpha(0.07),
                            height: 1,
                            indent: 14,
                            endIndent: 14),
                        _SwitchRow(
                          title: 'El enfoque empieza solo',
                          subtitle: 'Volver a concentrarse sin decidirlo',
                          value: autoFocus,
                          onChanged: (v) => setState(() => autoFocus = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Panel de descanso ──
                  _SectionLabel('DURANTE EL DESCANSO'),
                  const SizedBox(height: 4),
                  Text(
                    'En el enfoque la pantalla se queda solo con el reloj y tu tarea.',
                    style: GoogleFonts.outfit(
                      fontSize: 11.5,
                      height: 1.4,
                      color: BentoTheme.creamAlpha(0.4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in BreakPanelMode.icons.entries)
                        _ModeChip(
                          icon: entry.value,
                          label: BreakPanelMode.labels[entry.key]!,
                          selected: panelMode == entry.key,
                          onTap: () => setState(() => panelMode = entry.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // ── Arranque ──
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              4,
              20,
              16 + media.viewPadding.bottom,
            ),
            child: NeuCard(
              borderRadius: 20,
              distance: 5,
              blur: 10,
              color: PomodoroPalette.focus.withValues(alpha: 0.16),
              padding: const EdgeInsets.symmetric(vertical: 17),
              onTap: _start,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow_rounded,
                      color: PomodoroPalette.focus, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Enfocar $workMin min',
                    style: GoogleFonts.montserrat(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: BentoTheme.cream,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.montserrat(
        fontSize: 9.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
        color: BentoTheme.creamAlpha(0.4),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final _Preset preset;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Column(
        children: [
          Text(
            preset.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.montserrat(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: selected ? BentoTheme.cream : BentoTheme.creamAlpha(0.6),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            preset.hint,
            style: GoogleFonts.outfit(
              fontSize: 10,
              color: selected
                  ? PomodoroPalette.focus
                  : BentoTheme.creamAlpha(0.35),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: selected
          ? NeuPressed(
              borderRadius: 14,
              lite: true,
              padding: EdgeInsets.zero,
              child: content,
            )
          : NeuCard(
              borderRadius: 14,
              distance: 2.5,
              blur: 5,
              padding: EdgeInsets.zero,
              child: content,
            ),
    );
  }
}

class _DurationStepper extends StatelessWidget {
  final String title;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;

  const _DurationStepper({
    required this.title,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      borderRadius: 16,
      distance: 3,
      blur: 6,
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
      child: Column(
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.montserrat(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: BentoTheme.creamAlpha(0.4),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Toque de 5 en 5, pulsación larga de 1 en 1: el ajuste fino
              // existe pero no estorba al ajuste normal.
              _StepButton(
                icon: Icons.remove_rounded,
                onTap: () => onChanged(value - 5),
                onLongPress: () => onChanged(value - 1),
              ),
              Text(
                '$value',
                style: GoogleFonts.outfit(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              _StepButton(
                icon: Icons.add_rounded,
                onTap: () => onChanged(value + 5),
                onLongPress: () => onChanged(value + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _StepButton({
    required this.icon,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: BentoTheme.neuSurfaceSunken,
          shape: BoxShape.circle,
          boxShadow: BentoTheme.neuRaisedLite(distance: 1.5, blur: 3),
        ),
        child: Icon(icon, size: 14, color: BentoTheme.creamAlpha(0.7)),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: BentoTheme.creamAlpha(0.88),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: BentoTheme.creamAlpha(0.38),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: PomodoroPalette.focus,
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? BentoTheme.neuSurfaceSunken : BentoTheme.neuSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? PomodoroPalette.focus
                : BentoTheme.creamAlpha(0.08),
            width: 1.5,
          ),
          boxShadow:
              selected ? const [] : BentoTheme.neuRaisedLite(distance: 2, blur: 4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color:
                  selected ? PomodoroPalette.focus : BentoTheme.creamAlpha(0.5),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.montserrat(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color:
                    selected ? BentoTheme.cream : BentoTheme.creamAlpha(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
