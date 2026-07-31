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

  /// Bloque cuya hora ya pasó sin marcarse. Se apaga para que el ojo se vaya a
  /// lo que queda por delante, que es donde todavía se puede decidir algo.
  final bool isPast;

  /// El reloj está dentro de este bloque ahora mismo. Es la única tarjeta que
  /// merece destacar de todo el día.
  final bool isNow;

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
    this.isPast = false,
    this.isNow = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = task.isHabitBlock ? BlockType.habit.color : task.priority.color;
    final compact = height < 46;

    // Tres estados y un solo mando: la opacidad general. Completado y pasado
    // retroceden, "ahora" avanza, y todo lo demás se queda en el medio.
    final double faceAlpha = completed ? 0.05 : (isPast ? 0.06 : (isNow ? 0.20 : 0.13));
    final double contentOpacity = completed ? 0.55 : (isPast ? 0.5 : 1.0);

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
            accent.withValues(alpha: faceAlpha),
            BentoTheme.neuSurface,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              color: isPast && !completed ? accent.withValues(alpha: 0.35) : accent,
              width: isNow ? 4 : 3,
            ),
          ),
        ),
        padding: EdgeInsets.symmetric(horizontal: 11, vertical: compact ? 3 : 7),
        child: Opacity(
          opacity: contentOpacity,
          child: Row(
            crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              Expanded(child: compact ? _buildCompact(accent) : _buildFull(accent)),
              const SizedBox(width: 4),
              _buildCheck(accent, compact),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompact(Color accent) {
    return Row(
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
              height: 1.1,
              decoration: completed ? TextDecoration.lineThrough : null,
              decorationColor: BentoTheme.creamAlpha(0.5),
              color: completed ? BentoTheme.creamAlpha(0.55) : BentoTheme.cream,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          timeLabel.split(' – ').first,
          style: GoogleFonts.montserrat(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: BentoTheme.creamAlpha(0.45),
          ),
        ),
      ],
    );
  }

  Widget _buildFull(Color accent) {
    return Column(
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
                  height: 1.15,
                  letterSpacing: -0.1,
                  decoration: completed ? TextDecoration.lineThrough : null,
                  decorationColor: BentoTheme.creamAlpha(0.5),
                  color: completed ? BentoTheme.creamAlpha(0.55) : BentoTheme.cream,
                ),
              ),
            ),
            // Marca de "esto es lo que toca ahora". Es la única señal de
            // urgencia del timeline, por eso solo la lleva un bloque.
            if (isNow && !completed) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  'AHORA',
                  style: GoogleFonts.montserrat(
                    fontSize: 8.5,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Text(
              timeLabel,
              style: GoogleFonts.montserrat(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
                color: BentoTheme.creamAlpha(0.45),
              ),
            ),
            if (task.location != null) ...[
              const SizedBox(width: 7),
              Icon(Icons.place_outlined, size: 11, color: BentoTheme.creamAlpha(0.45)),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  task.location!,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.montserrat(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: BentoTheme.creamAlpha(0.45),
                  ),
                ),
              ),
            ],
            if (task.hasReminder) ...[
              const SizedBox(width: 7),
              Icon(Icons.notifications_none_rounded, size: 11, color: BentoTheme.creamAlpha(0.45)),
            ],
          ],
        ),
      ],
    );
  }

  /// Objetivo de toque generoso: marcar hecho es la acción más repetida del
  /// timeline y no puede depender de acertar en un icono de 16px.
  Widget _buildCheck(Color accent, bool compact) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggleComplete,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: compact ? 2 : 4),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: Icon(
            completed ? Icons.check_circle_rounded : Icons.circle_outlined,
            key: ValueKey(completed),
            size: compact ? 17 : 21,
            color: completed ? accent : BentoTheme.creamAlpha(0.3),
          ),
        ),
      ),
    );
  }
}
