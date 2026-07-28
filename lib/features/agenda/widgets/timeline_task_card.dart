import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/task_model.dart';
import '../../../core/theme/bento_theme.dart';

/// Tarjeta de bloque de tiempo posicionada dentro del timeline diario
/// (Stack). [top]/[height] ya vienen calculados en píxeles por el llamador.
class TimelineTaskCard extends StatelessWidget {
  final Task task;
  final double top;
  final double height;
  final VoidCallback onTap;
  final VoidCallback onToggleComplete;
  final VoidCallback? onLongPress;

  const TimelineTaskCard({
    super.key,
    required this.task,
    required this.top,
    required this.height,
    required this.onTap,
    required this.onToggleComplete,
    this.onLongPress,
  });

  String _fmtTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final accent = task.priority.color;
    final compact = height < 44;

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      height: height,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.only(bottom: 3),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              accent.withValues(alpha: task.completed ? 0.05 : 0.12),
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
                          Expanded(
                            child: Text(
                              task.title,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.montserrat(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                decoration: task.completed ? TextDecoration.lineThrough : null,
                                color: task.completed ? BentoTheme.creamAlpha(0.4) : BentoTheme.cream,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _fmtTime(task.startAt),
                            style: GoogleFonts.montserrat(fontSize: 10, color: BentoTheme.creamAlpha(0.5)),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            task.title,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              decoration: task.completed ? TextDecoration.lineThrough : null,
                              color: task.completed ? BentoTheme.creamAlpha(0.4) : BentoTheme.cream,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                task.endAt != null
                                    ? '${_fmtTime(task.startAt)} – ${_fmtTime(task.endAt!)}'
                                    : _fmtTime(task.startAt),
                                style: GoogleFonts.montserrat(fontSize: 11, color: BentoTheme.creamAlpha(0.5)),
                              ),
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
                    task.completed ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: compact ? 16 : 20,
                    color: task.completed ? accent : BentoTheme.creamAlpha(0.35),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
