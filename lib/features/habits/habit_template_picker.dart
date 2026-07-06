import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/habit_template.dart';
import '../../core/theme/bento_theme.dart';
import 'habit_form_dialog.dart';

/// Muestra una lista de hábitos preconfigurados. Al elegir uno, abre el formulario
/// de creación prellenado con nombre/ícono/meta/hora de recordatorio sugeridos.
Future<void> showHabitTemplatePicker(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: BentoTheme.cardBg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _HabitTemplateSheet(ref: ref),
  );
}

class _HabitTemplateSheet extends StatelessWidget {
  final WidgetRef ref;
  const _HabitTemplateSheet({required this.ref});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '✨ Elige un hábito',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: BentoTheme.textPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ya viene con meta y recordatorio sugeridos. Podrás ajustarlos antes de guardar.',
              style: TextStyle(fontSize: 12, color: BentoTheme.textSecondary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: kHabitTemplates.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final t = kHabitTemplates[index];
                  final color = Color(int.parse(t.color.replaceFirst('#', '0xFF')));
                  final subtitleParts = <String>[
                    if (t.goalValue != null)
                      'Meta: ${t.goalValue! % 1 == 0 ? t.goalValue!.toInt() : t.goalValue}${t.goalUnit != null ? ' ${t.goalUnit}' : ''}',
                    'Recordatorio ${TimeOfDay(hour: t.reminderHour, minute: t.reminderMinute).format(context)}',
                  ];
                  return BentoCard(
                    borderColor: color,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    onTap: () {
                      Navigator.pop(context);
                      showHabitFormDialog(context, ref, template: t);
                    },
                    child: Row(
                      children: [
                        Text(t.icon, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(t.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: BentoTheme.textPrimary)),
                              const SizedBox(height: 2),
                              Text(subtitleParts.join(' · '), style: const TextStyle(fontSize: 11, color: BentoTheme.textSecondary, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: BentoTheme.textSecondary),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
