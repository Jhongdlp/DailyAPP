import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/habit_template.dart';
import '../../core/theme/bento_theme.dart';
import 'habit_form_dialog.dart';

/// Muestra una lista de hábitos preconfigurados. Al elegir uno, abre el formulario
/// de creación prellenado con nombre/ícono/meta/hora de recordatorio sugeridos.
Future<void> showHabitTemplatePicker(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => _HabitTemplateSheet(ref: ref),
  );
}

class _HabitTemplateSheet extends StatelessWidget {
  final WidgetRef ref;
  const _HabitTemplateSheet({required this.ref});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BentoTheme.darkCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: BentoTheme.creamAlpha(0.2), borderRadius: BorderRadius.circular(100)),
                ),
              ),
              Text(
                'Elige un hábito',
                style: GoogleFonts.montserrat(fontSize: 18, fontWeight: FontWeight.w800, color: BentoTheme.cream),
              ),
              const SizedBox(height: 4),
              Text(
                'Ya viene con meta y recordatorio sugeridos. Podrás ajustarlos antes de guardar.',
                style: GoogleFonts.montserrat(fontSize: 12, color: BentoTheme.creamAlpha(0.5), fontWeight: FontWeight.w500),
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
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        showHabitFormDialog(context, ref, template: t);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: BentoTheme.darkCardAlt,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: BentoTheme.creamAlpha(0.07)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color.withValues(alpha: 0.16),
                              ),
                              child: Text(t.icon, style: const TextStyle(fontSize: 18)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    t.name,
                                    style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w700, color: BentoTheme.cream),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitleParts.join(' · '),
                                    style: GoogleFonts.montserrat(fontSize: 11, color: BentoTheme.creamAlpha(0.45), fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: BentoTheme.creamAlpha(0.4)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
