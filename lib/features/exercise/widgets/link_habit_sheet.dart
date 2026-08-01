import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/habit_model.dart';
import '../../../core/providers/exercise_habit_link_provider.dart';
import '../../../core/providers/habits_provider.dart';
import '../../../core/theme/bento_theme.dart';
import '../../habits/habit_form_dialog.dart';

/// Bottom sheet para vincular (o crear) el hábito que representa "hacer
/// ejercicio". Es el único punto de entrada al vínculo: tanto la pantalla de
/// gate de Ejercicio como el banner de auto-detección lo abren.
Future<void> showLinkHabitSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const _LinkHabitSheet(),
  );
}

class _LinkHabitSheet extends ConsumerWidget {
  const _LinkHabitSheet();

  Future<void> _createAndLink(BuildContext context, WidgetRef ref) async {
    final before = ref.read(habitsProvider).map((h) => h.id).toSet();
    await showHabitFormDialog(context, ref);
    if (!context.mounted) return;

    Habit? created;
    for (final h in ref.read(habitsProvider)) {
      if (!before.contains(h.id)) {
        created = h;
        break;
      }
    }
    if (created != null) {
      await ref.read(exerciseHabitLinkProvider.notifier).setLinkedHabit(created.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _link(BuildContext context, WidgetRef ref, Habit habit) async {
    await ref.read(exerciseHabitLinkProvider.notifier).setLinkedHabit(habit.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(habitsProvider).where((h) => !h.archived).toList();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: NeuCard(
        radius: const BorderRadius.vertical(top: Radius.circular(28)),
        elevation: 22,
        convex: false,
        padding: EdgeInsets.only(top: 10, bottom: 10 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NeuPressed(
              borderRadius: 3,
              distance: 2,
              blur: 3,
              child: SizedBox(width: 40, height: 5),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Vincula tu hábito de ejercicio',
                style: GoogleFonts.montserrat(color: BentoTheme.cream, fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Marcarlo como hecho en Hábitos te ofrecerá guardar tu progreso aquí.',
                style: GoogleFonts.montserrat(color: BentoTheme.creamAlpha(0.6), fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final habit in habits)
                      ListTile(
                        leading: Text(habit.icon, style: const TextStyle(fontSize: 22)),
                        title: Text(
                          habit.name,
                          style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
                        ),
                        onTap: () => _link(context, ref, habit),
                      ),
                    ListTile(
                      leading: Icon(Icons.add_circle_outline, color: BentoTheme.accentOrange),
                      title: Text(
                        'Crear hábito nuevo',
                        style: GoogleFonts.montserrat(color: BentoTheme.accentOrange, fontWeight: FontWeight.w700),
                      ),
                      onTap: () => _createAndLink(context, ref),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
