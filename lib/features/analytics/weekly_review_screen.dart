import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/models/metric_model.dart';
import '../../core/network/local_ai_client.dart';
import '../../core/providers/analytics_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/weekly_review_provider.dart';
import '../../core/services/metrics_service.dart';
import '../../core/theme/bento_theme.dart';
import 'steps/step_ai_summary.dart';
import 'steps/step_numbers.dart';
import 'steps/step_prompt.dart';

/// Ritual de revisión semanal: cuatro pasos para cerrar la semana.
///
/// Es una pantalla aparte y no una pestaña por lo mismo que la planeación
/// nocturna: el valor está en el cierre. Un panel de métricas siempre abierto
/// se mira de reojo; un ritual con principio y final obliga a sacar una
/// conclusión y a escribirla.
class WeeklyReviewScreen extends ConsumerStatefulWidget {
  /// Semana a revisar. Por defecto, la que está en curso.
  final DateTime? weekStart;

  const WeeklyReviewScreen({super.key, this.weekStart});

  @override
  ConsumerState<WeeklyReviewScreen> createState() => _WeeklyReviewScreenState();
}

class _WeeklyReviewScreenState extends ConsumerState<WeeklyReviewScreen> {
  final _pageController = PageController();
  int _step = 0;

  String _wins = '';
  String _frictions = '';
  String _nextFocus = '';
  String _aiSummary = '';

  static const _stepCount = 4;

  late final DateTime _weekStart = MetricsService.startOfWeek(
    widget.weekStart ?? DateTime.now(),
  );

  @override
  void initState() {
    super.initState();

    // Reabrir una revisión ya empezada debe continuarla, no pedirlo todo otra
    // vez desde cero.
    final existing = ref.read(weeklyReviewProvider.notifier).forWeek(_weekStart);
    if (existing != null) {
      _wins = existing.wins;
      _frictions = existing.frictions;
      _nextFocus = existing.nextFocus;
      _aiSummary = existing.aiSummary;
    }
  }

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

  /// Resúmenes de la semana revisada, no de la ventana elegida en analíticas.
  List<MetricSummary> get _weekSummaries {
    final snapshot = ref.read(metricsSnapshotProvider);
    final to = _weekStart.add(const Duration(days: 7));

    return [
      for (final metric in snapshot.available)
        MetricsService.summarize(metric, snapshot[metric], _weekStart, to),
    ];
  }

  /// Pide a Ollama que lea los números y lo escrito, y devuelva una lectura
  /// corta. Se le pasan los datos ya resumidos: el modelo redacta, no calcula.
  Future<String> _generateSummary() async {
    final settings = ref.read(settingsProvider);
    final client = LocalAIClient(
      baseUrl: settings.localAiUrl,
      textModelName: settings.textModel,
    );

    final lines = <String>[];
    for (final s in _weekSummaries) {
      if (!s.hasData) continue;
      final change = s.change;
      final delta = change == null
          ? 'sin comparación con la semana anterior'
          : '${change >= 0 ? '+' : ''}${(change * 100).round()}% vs. la semana anterior';
      lines.add('- ${s.metric.label}: ${s.metric.format(s.value!)} ($delta)');
    }

    final prompt = StringBuffer()
      ..writeln('Estos son mis números de la semana:')
      ..writeln(lines.isEmpty ? '(sin datos registrados)' : lines.join('\n'));

    if (_wins.trim().isNotEmpty) {
      prompt
        ..writeln()
        ..writeln('Lo que digo que funcionó: ${_wins.trim()}');
    }
    if (_frictions.trim().isNotEmpty) {
      prompt
        ..writeln()
        ..writeln('Lo que digo que estorbó: ${_frictions.trim()}');
    }

    return client.askText(
      prompt.toString(),
      systemPrompt:
          'Eres un coach personal que revisa la semana de alguien. Escribe en '
          'español, en segunda persona y en tono directo, sin alabanzas vacías '
          'ni lenguaje motivacional genérico. Máximo 120 palabras. Señala UNA '
          'cosa que está funcionando y UNA que conviene ajustar, apoyándote en '
          'los números concretos que te doy. No inventes datos que no estén '
          'en la lista.',
    );
  }

  Future<void> _finish() async {
    await ref.read(weeklyReviewProvider.notifier).save(
          weekStart: _weekStart,
          wins: _wins,
          frictions: _frictions,
          nextFocus: _nextFocus,
          aiSummary: _aiSummary,
        );
    if (mounted) Navigator.pop(context, true);
  }

  String get _weekLabel {
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    final end = _weekStart.add(const Duration(days: 6));
    return '${_weekStart.day} ${months[_weekStart.month - 1]} — '
        '${end.day} ${months[end.month - 1]}';
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
                // Solo se avanza con los botones: cada paso pide algo concreto
                // y deslizar sin querer se lo saltaría.
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  StepNumbers(
                    summaries: _weekSummaries,
                    onNext: () => _goTo(1),
                  ),
                  StepPrompt(
                    key: const ValueKey('wins'),
                    title: '¿Qué funcionó?',
                    subtitle:
                        'Lo que sí salió, por pequeño que sea. Sé concreto: '
                        'un hábito, un día, una decisión.',
                    hint: 'Esta semana…',
                    initialValue: _wins,
                    accent: BentoTheme.accentLime,
                    onNext: (value) {
                      setState(() => _wins = value);
                      _goTo(2);
                    },
                  ),
                  StepPrompt(
                    key: const ValueKey('frictions'),
                    title: '¿Qué estorbó?',
                    subtitle:
                        'Lo que te frenó. No hace falta resolverlo ahora: '
                        'nombrarlo ya es la mitad.',
                    hint: 'Lo que me costó…',
                    initialValue: _frictions,
                    accent: BentoTheme.accentOrange,
                    onNext: (value) {
                      setState(() => _frictions = value);
                      _goTo(3);
                    },
                  ),
                  StepAiSummary(
                    initialSummary: _aiSummary,
                    initialFocus: _nextFocus,
                    generate: _generateSummary,
                    onSummaryChanged: (value) => _aiSummary = value,
                    onFocusChanged: (value) => _nextFocus = value,
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
                onTap: () =>
                    _step == 0 ? Navigator.pop(context) : _goTo(_step - 1),
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
                      'Revisión semanal',
                      style: GoogleFonts.montserrat(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: BentoTheme.cream,
                      ),
                    ),
                    Text(
                      _weekLabel,
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
                        color: i <= _step
                            ? BentoTheme.accentBlue
                            : BentoTheme.creamAlpha(0.12),
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
