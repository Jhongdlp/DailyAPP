import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/task_model.dart';
import '../../../core/theme/bento_theme.dart';

/// Tarjeta de un bloque de tiempo del timeline diario.
///
/// Deliberadamente NO se posiciona a sí misma: quien la usa la envuelve en el
/// `Positioned` correspondiente como hijo *directo* del `Stack`. Devolver un
/// `Positioned` desde aquí obligaba al llamador a no interponer ningún widget,
/// y cualquier `Padding` intermedio rompía el árbol (`Positioned` es un
/// `ParentDataWidget` que exige `Stack` como padre de render).
class TimelineTaskCard extends StatelessWidget {
  final Task task;

  /// Alto disponible en píxeles, para decidir el layout compacto.
  final double height;

  /// Estado de completado ya resuelto por quien la usa. Para los bloques de
  /// hábito no coincide con `task.completed`: la verdad vive en el hábito.
  final bool completed;

  /// Rango horario ya formateado. Durante un arrastre refleja la posición en
  /// curso, no la guardada, para que el bloque diga la hora a la que va a
  /// quedar mientras lo mueves.
  final String timeLabel;

  final VoidCallback onTap;
  final VoidCallback onToggleComplete;

  const TimelineTaskCard({
    super.key,
    required this.task,
    required this.height,
    required this.timeLabel,
    required this.onTap,
    required this.onToggleComplete,
    this.completed = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = task.isHabitBlock ? BlockType.habit.color : task.priority.color;
    final compact = height < 44;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        // El alto lo fija el `Positioned` del timeline, así que un bloque muy
        // corto puede quedar más pequeño que su contenido: recortamos en vez
        // de desbordar.
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            accent.withValues(alpha: completed ? 0.05 : 0.12),
            BentoTheme.neuSurface,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 4 : 8),
        child: Row(
          crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Expanded(
              child: compact
                  ? Row(
                      children: [
                        if (task.isMit) ...[
                          Icon(Icons.star_rounded, size: 13, color: BentoTheme.accentOrange),
                          const SizedBox(width: 3),
                        ],
                        Expanded(
                          child: Text(
                            task.title,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.montserrat(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              decoration: completed ? TextDecoration.lineThrough : null,
                              color: completed ? BentoTheme.creamAlpha(0.4) : BentoTheme.cream,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          timeLabel.split(' – ').first,
                          style: GoogleFonts.montserrat(fontSize: 10, color: BentoTheme.creamAlpha(0.5)),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            if (task.isMit) ...[
                              Icon(Icons.star_rounded, size: 14, color: BentoTheme.accentOrange),
                              const SizedBox(width: 3),
                            ],
                            Expanded(
                              child: Text(
                                task.title,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: GoogleFonts.montserrat(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  decoration: completed ? TextDecoration.lineThrough : null,
                                  color: completed ? BentoTheme.creamAlpha(0.4) : BentoTheme.cream,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              timeLabel,
                              style: GoogleFonts.montserrat(fontSize: 11, color: BentoTheme.creamAlpha(0.5)),
                            ),
                            if (task.location != null) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.place_outlined, size: 12, color: BentoTheme.creamAlpha(0.5)),
                              const SizedBox(width: 2),
                              Flexible(
                                child: Text(
                                  task.location!,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.montserrat(fontSize: 11, color: BentoTheme.creamAlpha(0.5)),
                                ),
                              ),
                            ],
                            if (task.hasReminder) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.notifications_outlined, size: 12, color: BentoTheme.creamAlpha(0.5)),
                            ],
                          ],
                        ),
                      ],
                    ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleComplete,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  completed ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: compact ? 16 : 20,
                  color: completed ? accent : BentoTheme.creamAlpha(0.35),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
