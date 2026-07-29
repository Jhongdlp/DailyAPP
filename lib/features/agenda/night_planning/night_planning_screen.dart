import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/providers/day_plan_provider.dart';
import '../../../core/theme/bento_theme.dart';
import 'steps/step_commit.dart';
import 'steps/step_habits.dart';
import 'steps/step_mits.dart';
import 'steps/step_review_today.dart';
import 'steps/step_timeline.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Ritual nocturno: cinco pasos para cerrar hoy y dejar mañana decidido.
///
/// Es una pantalla aparte y no una pestaña más por una razón concreta: el
/// valor de planear de noche está en el cierre. Escribir el plan del día
/// siguiente descarga las tareas pendientes de la cabeza y apaga los
/// pensamientos intrusivos; una lista siempre abierta no cierra nada, un
/// ritual con principio y final sí.
class NightPlanningScreen extends ConsumerStatefulWidget {
  /// Día que se planea. Por defecto, mañana.
  final DateTime? planDay;

  const NightPlanningScreen({super.key, this.planDay});

  @override
  ConsumerState<NightPlanningScreen> createState() => _NightPlanningScreenState();
}

class _NightPlanningScreenState extends ConsumerState<NightPlanningScreen> {
  final _pageController = PageController();
  int _step = 0;

  /// Estado que se acumula a lo largo del ritual y se guarda al final.
  int? _mood;
  String? _reflection;
  String? _intention;

  static const _stepCount = 5;

  late final DateTime _planDay =
      _dateOnly(widget.planDay ?? DateTime.now().add(const Duration(days: 1)));
  late final DateTime _today = _dateOnly(DateTime.now());

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int step) {
    if (step < 0 || step >= _stepCount) return;
    setState(() => _step = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    await ref.read(dayPlansProvider.notifier).savePlan(
          day: _planDay,
          intention: _intention,
          reflection: _reflection,
          mood: _mood,
          ritualCompleted: true,
        );
    if (mounted) Navigator.pop(context, true);
  }

  String get _planDayLabel {
    const days = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${days[_planDay.weekday - 1]} ${_planDay.day} ${months[_planDay.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BentoTheme.darkBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: PageView(
                controller: _pageController,
                // Solo se avanza con los botones: cada paso tiene una acción
                // concreta y deslizar sin querer se los saltaría.
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  StepReviewToday(
                    day: _today,
                    onNext: (mood, reflection) {
                      setState(() {
                        _mood = mood;
                        _reflection = reflection;
                      });
                      _goTo(1);
                    },
                  ),
                  StepMits(
                    today: _today,
                    planDay: _planDay,
                    onNext: () => _goTo(2),
                  ),
                  StepHabits(planDay: _planDay, onNext: () => _goTo(3)),
                  StepTimeline(planDay: _planDay, onNext: () => _goTo(4)),
                  StepCommit(
                    planDay: _planDay,
                    onIntentionChanged: (value) => _intention = value,
                    onFinish: _finish,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _step == 0 ? Navigator.pop(context) : _goTo(_step - 1),
                child: Padding(
                  padding: const EdgeInsets.only(right: 12, top: 4, bottom: 4),
                  child: Icon(
                    _step == 0 ? Icons.close : Icons.arrow_back,
                    size: 20,
                    color: BentoTheme.creamAlpha(0.7),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Planear mañana',
                      style: GoogleFonts.montserrat(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: BentoTheme.cream,
                      ),
                    ),
                    Text(
                      _planDayLabel,
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: BentoTheme.creamAlpha(0.45),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${_step + 1}/$_stepCount',
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: BentoTheme.creamAlpha(0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < _stepCount; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == _stepCount - 1 ? 0 : 5),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      height: 3,
                      decoration: BoxDecoration(
                        color: i <= _step ? BentoTheme.accentLime : BentoTheme.creamAlpha(0.12),
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Botón principal compartido por los pasos del ritual.
class NightStepButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;

  const NightStepButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? BentoTheme.accentLime : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
          border: primary ? null : Border.all(color: BentoTheme.creamAlpha(0.2)),
        ),
        child: Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: primary ? const Color(0xFF0C0C0D) : BentoTheme.creamAlpha(0.7),
          ),
        ),
      ),
    );
  }
}

/// Cabecera de un paso: pregunta grande + una línea de porqué.
class NightStepHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const NightStepHeading({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.montserrat(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -0.5,
            color: BentoTheme.cream,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: GoogleFonts.montserrat(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.45,
            color: BentoTheme.creamAlpha(0.5),
          ),
        ),
      ],
    );
  }
}
