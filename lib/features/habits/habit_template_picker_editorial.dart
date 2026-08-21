import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';

import '../../core/models/habit_template.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/widgets/editorial_kit.dart';
import 'habit_form_editorial.dart';

/// Catálogo de hábitos prearmados, en el sistema editorial.
///
/// La versión anterior era una lista de tarjetas con borde, todas del mismo
/// peso. Aquí es un **índice**: filas separadas por filete, sin caja propia,
/// con el emoji como viñeta. Es la forma correcta para un catálogo que se
/// escanea de arriba abajo y del que se elige uno — la tarjeta sugiere que cada
/// elemento es una pieza en sí misma, y no lo es: es una entrada de menú.
Future<void> showHabitTemplatePickerEditorial(BuildContext context, WidgetRef ref) {
  return showEditorialSheet<void>(
    context: context,
    title: 'Elige un hábito',
    maxHeightFactor: 0.8,
    builder: (sheetContext, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Text(
            'Vienen con meta y recordatorio sugeridos. Podrás ajustarlo todo '
            'antes de guardar.',
            style: EditorialTheme.text(
              14,
              color: EditorialTheme.grayText,
              height: 1.4,
            ),
          ),
        ),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 4),
            itemCount: kHabitTemplates.length,
            // El filete va entrado hasta el texto, no de canto a canto: es lo
            // que hace que una lista se lea como índice y no como tabla.
            separatorBuilder: (_, _) => const EditorialRule(indent: 66),
            itemBuilder: (_, i) => _TemplateRow(
              template: kHabitTemplates[i],
              onTap: () {
                Navigator.of(sheetContext).pop();
                showHabitFormEditorial(context, ref, template: kHabitTemplates[i]);
              },
            ),
          ),
        ),
      ],
    ),
  );
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({required this.template, required this.onTap});

  final HabitTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (template.goalValue != null)
        'Meta ${_fmt(template.goalValue!)}${template.goalUnit != null ? ' ${template.goalUnit}' : ''}',
      'Aviso ${TimeOfDay(hour: template.reminderHour, minute: template.reminderMinute).format(context)}',
    ];

    return EditorialPressable(
      onTap: onTap,
      scale: 0.985,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: EditorialTheme.gray,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Twemoji(emoji: template.icon, height: 18, width: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    template.name,
                    style: EditorialTheme.text(
                      15.5,
                      weight: FontWeight.w600,
                      color: EditorialTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    details.join('  ·  '),
                    style: EditorialTheme.text(12.5, color: EditorialTheme.grayText),
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

  String _fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toString();
}
