import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/providers/tasks_provider.dart';
import '../../../core/models/task_model.dart';
import 'providers/pomodoro_provider.dart';

class PomodoroScreen extends ConsumerStatefulWidget {
  const PomodoroScreen({super.key});

  @override
  ConsumerState<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends ConsumerState<PomodoroScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  late AnimationController _breathingController;

  // Friendly celeste color instead of deep alarm blue
  static const Color celesteFriendly = Color(0xFF4EA8DE);

  // Unique seed generated per screen session so random images change every time the screen is opened
  final int _sessionSeed = DateTime.now().millisecondsSinceEpoch % 10000;

  // Track the last preloaded index to prevent redundant cache calls
  int? _lastPreloadedIndex;

  final List<String> _motivationalPhrases = const [
    "El único modo de hacer un gran trabajo es amar lo que haces. — Steve Jobs",
    "La concentración es el secreto de la fuerza. — Ralph Waldo Emerson",
    "No vigiles el reloj; haz lo que él hace: sigue adelante. — Sam Levenson",
    "Tus acciones de hoy determinan tu éxito de mañana. — Disciplina",
    "Un viaje de mil millas comienza con un solo paso. — Lao Tzu",
    "Haz de cada día tu obra maestra. — John Wooden",
    "El secreto para salir adelante es comenzar. — Mark Twain",
    "La disciplina es el puente entre las metas y los logros. — Jim Rohn",
    "Mantén tu enfoque en la meta, no en los obstáculos. — Foco",
    "Hazlo con pasión o no lo hagas. — Dirección",
    "La persistencia vence a la resistencia. — Constancia",
    "En medio del caos, reside la oportunidad. — Albert Einstein",
    "Tu mente está para tener ideas, no para almacenarlas. — David Allen",
    "El enfoque es un músculo, y lo estás fortaleciendo ahora. — Crecimiento",
    "Calma en la mente, fuerza en el alma. — Balance"
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable(); // Keep screen on

    // Pulse controller for breathing phase text status (2s duration)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    // Box breathing controller (16 seconds total)
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();

    // Preload the first two images immediately so they are ready on screen entry
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadImage(0);
      _preloadImage(1);
    });
  }

  void _preloadImage(int index) {
    if (!mounted) return;
    final queryUrl = _carouselQueries[index % _carouselQueries.length];
    final imageUrl = '$queryUrl?lock=${_sessionSeed + index}';
    
    // precacheImage downloads the network image and caches it in Flutter's global ImageCache
    precacheImage(NetworkImage(imageUrl), context).catchError((e) {
      debugPrint("Error preloading pomodoro image index $index: $e");
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable(); // Release wake lock
    _pulseController.dispose();
    _breathingController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(pomodoroProvider.notifier).syncWithBackground();
    }
  }

  Widget _buildBackButton(BuildContext context) {
    return _buildTactileButton(
      icon: Icons.arrow_back_ios_new_rounded,
      onTap: () {
        ref.read(pomodoroProvider.notifier).stop();
        Navigator.pop(context);
      },
      color: BentoTheme.creamAlpha(0.7),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pomState = ref.watch(pomodoroProvider);
    final tasks = ref.watch(tasksProvider);
    
    final todayOnly = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final todayTasks = tasks.where((t) => t.dueDate == todayOnly).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));

    // Schedule preloading of upcoming carousel images in background queue
    final nextIndex = pomState.carouselIndex + 1;
    if (_lastPreloadedIndex != nextIndex) {
      _lastPreloadedIndex = nextIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _preloadImage(nextIndex);
        _preloadImage(nextIndex + 1);
      });
    }

    return Scaffold(
      backgroundColor: BentoTheme.neuSurface, // App Neumorphic Background
      body: SafeArea(
        child: Stack(
          children: [
            // Floating Neumorphic Back Button (Top Left)
            Positioned(
              top: 16,
              left: 16,
              child: _buildBackButton(context),
            ),
            // Main Content Area
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(top: 60), // Avoid overlap with back button
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isLandscape = constraints.maxWidth > constraints.maxHeight;

                    if (isLandscape) {
                      return Row(
                        children: [
                          // Left Timer Column
                          Expanded(
                            flex: 6,
                            child: _buildTimerPanel(context, pomState),
                          ),
                          // Vertical separator shadow
                          Container(
                            width: 2,
                            color: BentoTheme.neuShadowDark.withValues(alpha: 0.3),
                            margin: const EdgeInsets.symmetric(vertical: 40),
                          ),
                          // Right Content Column
                          Expanded(
                            flex: 5,
                            child: _buildRightPanel(context, pomState, todayTasks),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          // Top Timer Section
                          Expanded(
                            flex: 5,
                            child: _buildTimerPanel(context, pomState),
                          ),
                          // Horizontal separator shadow
                          Container(
                            height: 2,
                            color: BentoTheme.neuShadowDark.withValues(alpha: 0.3),
                            margin: const EdgeInsets.symmetric(horizontal: 40),
                          ),
                          // Bottom Content Section
                          Expanded(
                            flex: 5,
                            child: _buildRightPanel(context, pomState, todayTasks),
                          ),
                        ],
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // LEFT PANEL - MINIMALIST VOLCANO RING CHRONOMETER
  // ----------------------------------------------------

  Widget _buildTimerPanel(BuildContext context, PomodoroState pomState) {
    // Focus = celeste, Long Break = purple, Short Break = green
    final themeColor = pomState.isFocusPhase 
        ? celesteFriendly 
        : (pomState.isLongBreak ? BentoTheme.accentPurple : BentoTheme.successGreen);
    final totalSeconds = pomState.isFocusPhase 
        ? pomState.workDuration * 60 
        : (pomState.isLongBreak ? pomState.longBreakDuration * 60 : pomState.breakDuration * 60);
    final progress = totalSeconds > 0 ? pomState.timeLeft / totalSeconds : 1.0;

    final minutes = (pomState.timeLeft ~/ 60).toString().padLeft(2, '0');
    final seconds = (pomState.timeLeft % 60).toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Static Phase Text at the top (no micro-animation)
          Text(
            pomState.isFocusPhase 
                ? 'ENFOQUE' 
                : (pomState.isLongBreak ? 'DESCANSO LARGO' : 'DESCANSO'),
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 4.0,
              color: themeColor,
              shadows: [
                Shadow(
                  color: themeColor.withValues(alpha: 0.2),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Minimalist Neumorphic Stopwatch Plate (Single Circular Plate)
          NeuCard(
            borderRadius: 100,
            distance: 6,
            blur: 12,
            padding: const EdgeInsets.all(11), // Slightly increased padding to make the dial smaller
            child: SizedBox(
              width: 180,
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Glowing ring painted on the absolute outer edge of the dial
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _NeumorphicGlowRingPainter(
                          progress: progress,
                          color: themeColor,
                        ),
                      ),
                    ),
                  ),
                  // Simple Digital Clock Numbers
                  Text(
                    '$minutes:$seconds',
                    style: GoogleFonts.shareTechMono(
                      fontSize: 44,
                      color: BentoTheme.cream,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Cycles Completed Green Light Bars Row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              final slotNumber = index + 1;
              
              bool isCompleted;
              bool isCurrent;
              
              if (pomState.isFocusPhase) {
                isCompleted = (pomState.cycleCount % 4) >= slotNumber;
                isCurrent = (pomState.cycleCount % 4) + 1 == slotNumber;
              } else {
                final completedThisBlock = (pomState.cycleCount % 4) == 0 ? 4 : (pomState.cycleCount % 4);
                isCompleted = completedThisBlock >= slotNumber;
                isCurrent = false;
              }

              // LED Bar properties
              Color barColor;
              List<BoxShadow> shadows = [];

              if (isCompleted) {
                barColor = BentoTheme.successGreen;
                shadows = [
                  BoxShadow(
                    color: BentoTheme.successGreen.withValues(alpha: 0.6),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ];
              } else if (isCurrent && pomState.isActive) {
                barColor = BentoTheme.successGreen.withValues(alpha: 0.55);
              } else {
                barColor = BentoTheme.creamAlpha(0.12);
              }

              final barWidget = AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 24,
                height: 6,
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: shadows,
                  border: isCurrent
                      ? Border.all(
                          color: BentoTheme.successGreen.withValues(alpha: 0.8),
                          width: 1,
                        )
                      : null,
                ),
              );

              if (isCurrent && pomState.isActive) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.9, end: 1.1).animate(
                      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
                    ),
                    child: barWidget,
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: barWidget,
              );
            }),
          ),
          const SizedBox(height: 20),

          // Tactile Neumorphic Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Stop Button
              _buildTactileButton(
                icon: Icons.stop_rounded,
                onTap: () {
                  ref.read(pomodoroProvider.notifier).stop();
                  Navigator.pop(context);
                },
                color: BentoTheme.creamAlpha(0.6),
              ),
              const SizedBox(width: 24),
              // Play/Pause Button (Celeste colored in Focus mode)
              _buildTactileButton(
                icon: pomState.isActive ? Icons.pause_rounded : Icons.play_arrow_rounded,
                onTap: () {
                  if (pomState.isActive) {
                    ref.read(pomodoroProvider.notifier).pause();
                  } else {
                    ref.read(pomodoroProvider.notifier).start();
                  }
                },
                color: themeColor,
                isLarge: true,
              ),
              const SizedBox(width: 24),
              // Skip Button
              _buildTactileButton(
                icon: Icons.skip_next_rounded,
                onTap: () {
                  ref.read(pomodoroProvider.notifier).skip();
                },
                color: BentoTheme.creamAlpha(0.6),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTactileButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
    bool isLarge = false,
  }) {
    final double size = isLarge ? 56.0 : 44.0;
    return NeuCard(
      borderRadius: size / 2,
      distance: isLarge ? 5 : 4,
      blur: isLarge ? 10 : 8,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          icon,
          color: color,
          size: isLarge ? 28 : 20,
        ),
      ),
    );
  }

  static const List<Map<String, String>> _techQuotes = [
    {
      "quote": "Cualquier tecnología suficientemente avanzada es indistinguible de la magia.",
      "author": "ARTHUR C. CLARKE"
    },
    {
      "quote": "Los mejores programas se escriben cuando los programadores están en estado de flujo.",
      "author": "CONCENTRACIÓN"
    },
    {
      "quote": "La tecnología es mejor cuando une a la gente.",
      "author": "MATT MULLENWEG"
    },
    {
      "quote": "El software es una gran combinación entre arte y ciencia.",
      "author": "BILL GATES"
    },
    {
      "quote": "Los ordenadores son inútiles. Solo pueden darte respuestas.",
      "author": "PABLO PICASSO"
    },
    {
      "quote": "La tecnología no es nada. Lo importante es que tengas fe en la gente.",
      "author": "STEVE JOBS"
    },
    {
      "quote": "La simplicidad es la máxima sofisticación.",
      "author": "LEONARDO DA VINCI"
    },
    {
      "quote": "Un programador es un creador de universos para los que él es la única ley.",
      "author": "JOSEPH WEIZENBAUM"
    },
    {
      "quote": "Primero, resuelve el problema. Entonces, escribe el código.",
      "author": "JOHN JOHNSON"
    },
    {
      "quote": "El código es como el humor. Cuando tienes que explicarlo, es malo.",
      "author": "CORY HOUSE"
    },
    {
      "quote": "No temas a las computadoras, teme a la falta de ellas.",
      "author": "ISAAC ASIMOV"
    },
    {
      "quote": "La función del buen software es hacer que lo complejo aparente ser simple.",
      "author": "DISEÑO"
    },
    {
      "quote": "El único error real es aquel del que no aprendemos nada.",
      "author": "HENRY FORD"
    },
    {
      "quote": "La mejor forma de predecir el futuro es inventarlo.",
      "author": "ALAN KAY"
    },
    {
      "quote": "Controlar la complejidad es la esencia de la programación informática.",
      "author": "BRIAN KERNIGHAN"
    },
    {
      "quote": "El software se come el mundo.",
      "author": "MARC ANDREESSEN"
    },
    {
      "quote": "La elegancia es un requerimiento del software, no un lujo adicional.",
      "author": "EDSGER DIJKSTRA"
    },
    {
      "quote": "No me importa si funciona en tu máquina, ¡no estamos vendiendo tu máquina!",
      "author": "LINUS TORVALDS"
    },
    {
      "quote": "La paciencia y perseverancia tienen un efecto mágico ante las dificultades.",
      "author": "ENFOQUE"
    },
    {
      "quote": "Si automatizas un caos, lo único que consigues es un caos automatizado.",
      "author": "INGENIERÍA"
    },
    {
      "quote": "Hablar es barato. Muéstrame el código.",
      "author": "LINUS TORVALDS"
    },
    {
      "quote": "La tecnología de la información y los negocios se están entrelazando.",
      "author": "BILL GATES"
    },
    {
      "quote": "Hacer las cosas difíciles es fácil. Hacer las cosas fáciles es difícil.",
      "author": "SIMPLICIDAD"
    },
    {
      "quote": "Las computadoras hacen lo que les dices que hagan, no lo que quieres que hagan.",
      "author": "LEY DE PROGRAMACIÓN"
    },
    {
      "quote": "Si no estás cometiendo errores, entonces no estás trabajando en problemas difíciles.",
      "author": "FRANK WILCZEK"
    }
  ];

  static const List<String> _carouselQueries = [
    'https://loremflickr.com/600/600/landscape,nature,forest',
    'https://loremflickr.com/600/600/supercar,sports-car,auto',
    'https://loremflickr.com/600/600/mountains,valleys,scenery',
    'https://loremflickr.com/600/600/classic-car,muscle-car,roadster',
    'https://loremflickr.com/600/600/ocean,beach,coast,sea',
  ];

  Widget _buildRightPanel(BuildContext context, PomodoroState pomState, List<Task> todayTasks) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Neumorphic Select Tabs Bar
          NeuCard(
            borderRadius: 16,
            distance: 3,
            blur: 6,
            padding: const EdgeInsets.all(6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildPanelTabIcon(0, Icons.format_quote, pomState.rightPanelMode),
                _buildPanelTabIcon(1, Icons.photo_library_outlined, pomState.rightPanelMode),
                _buildPanelTabIcon(2, Icons.check_box_outlined, pomState.rightPanelMode),
                _buildPanelTabIcon(3, Icons.lens_outlined, pomState.rightPanelMode),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Main Display Card
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _buildRightPanelContent(pomState, todayTasks),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelTabIcon(int mode, IconData icon, int currentMode) {
    final isSelected = mode == currentMode;
    return Expanded(
      child: isSelected
          ? NeuPressed(
              borderRadius: 12,
              lite: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Icon(
                icon,
                size: 18,
                color: celesteFriendly,
              ),
            )
          : GestureDetector(
              onTap: () {
                ref.read(pomodoroProvider.notifier).setRightPanelMode(mode);
              },
              child: Container(
                color: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Icon(
                  icon,
                  size: 18,
                  color: BentoTheme.creamAlpha(0.4),
                ),
              ),
            ),
    );
  }

  Widget _buildRightPanelContent(PomodoroState pomState, List<Task> todayTasks) {
    switch (pomState.rightPanelMode) {
      case 0:
        final quoteIndex = (pomState.carouselIndex + _sessionSeed) % _techQuotes.length;
        final quoteData = _techQuotes[quoteIndex];
        return _buildPhraseCard(quoteData['quote']!, quoteData['author']!, ValueKey('tech_quote_$quoteIndex'));
      case 1:
        return _buildImageCarouselCard(pomState.carouselIndex);
      case 2:
        return _buildTasksList(todayTasks);
      case 3:
        return _buildBreathingGuide();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildImageCarouselCard(int index) {
    final queryUrl = _carouselQueries[index % _carouselQueries.length];
    // loremflickr uses the 'lock' parameter to assign a specific image to a seed value
    final imageUrl = '$queryUrl?lock=${_sessionSeed + index}';

    return NeuCard(
      key: ValueKey('image_carousel_$index'),
      padding: const EdgeInsets.all(8), // Picture frame padding
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                    color: celesteFriendly,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off, size: 28, color: BentoTheme.creamAlpha(0.2)),
                      const SizedBox(height: 8),
                      Text(
                        'Sin conexión para cargar imagen',
                        style: GoogleFonts.outfit(fontSize: 11, color: BentoTheme.creamAlpha(0.35)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhraseCard(String phrase, String author, Key key) {
    return NeuCard(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Glowing vertical accent bar on the left
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: celesteFriendly,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: celesteFriendly.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              // Quote content
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Floating quotation mark icon (soft background detail)
                    Icon(
                      Icons.format_quote,
                      size: 26,
                      color: celesteFriendly.withValues(alpha: 0.18),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      phrase,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: BentoTheme.creamAlpha(0.85),
                        fontWeight: FontWeight.w500,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '— $author',
                      style: GoogleFonts.montserrat(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: celesteFriendly,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTasksList(List<Task> todayTasks) {
    final pendingCount = todayTasks.where((t) => !t.completed).length;

    return NeuCard(
      key: const ValueKey(2),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'ENFOQUES DEL DÍA',
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: BentoTheme.creamAlpha(0.4),
                ),
              ),
              Text(
                '$pendingCount pendientes',
                style: GoogleFonts.montserrat(
                  fontSize: 9,
                  color: BentoTheme.creamAlpha(0.3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: todayTasks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        '¡Excelente! No tienes tareas en tu agenda para hoy.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(fontSize: 13, color: BentoTheme.creamAlpha(0.4)),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: todayTasks.length,
                    separatorBuilder: (_, __) => Divider(color: BentoTheme.creamAlpha(0.08), height: 1),
                    itemBuilder: (context, index) {
                      final task = todayTasks[index];
                      return GestureDetector(
                        onTap: () {
                          ref.read(tasksProvider.notifier).toggleComplete(task.id);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              // Tactile Checkbox Button (Celeste colored)
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  border: Border.all(color: BentoTheme.creamAlpha(0.2), width: 1.5),
                                  borderRadius: BorderRadius.circular(6),
                                  color: task.completed ? celesteFriendly : Colors.transparent,
                                ),
                                child: task.completed
                                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  task.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: task.completed
                                        ? BentoTheme.creamAlpha(0.35)
                                        : BentoTheme.creamAlpha(0.8),
                                    decoration: task.completed
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                              if (task.isMit)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: celesteFriendly, width: 0.8),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'MIT',
                                    style: GoogleFonts.montserrat(
                                      fontSize: 7,
                                      fontWeight: FontWeight.bold,
                                      color: celesteFriendly,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreathingGuide() {
    return NeuCard(
      key: const ValueKey(3),
      padding: const EdgeInsets.all(16),
      child: AnimatedBuilder(
        animation: _breathingController,
        builder: (context, child) {
          final val = _breathingController.value;
          double scale = 0.5;
          String actionText = "Inhala";

          // Box breathing intervals (4 seconds each)
          if (val < 0.25) {
            final t = val / 0.25;
            scale = 0.6 + 0.5 * Curves.easeInOut.transform(t);
            actionText = "Inhala aire...";
          } else if (val < 0.50) {
            scale = 1.1;
            actionText = "Mantén el aire...";
          } else if (val < 0.75) {
            final t = (val - 0.50) / 0.25;
            scale = 1.1 - 0.5 * Curves.easeInOut.transform(t);
            actionText = "Exhala lento...";
          } else {
            scale = 0.6;
            actionText = "Mantén vacío...";
          }

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Neumorphic physical piston-diaphragm guide
              Center(
                child: SizedBox(
                  width: 130,
                  height: 130,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Sunken plate backdrop
                      Positioned.fill(
                        child: NeuPressed(
                          borderRadius: 80,
                          lite: true,
                          child: const SizedBox.shrink(),
                        ),
                      ),
                      // Physical expanding raised membrane button (using Celeste/Green details)
                      Transform.scale(
                        scale: scale,
                        child: NeuCard(
                          borderRadius: 50,
                          distance: 4,
                          blur: 8,
                          padding: EdgeInsets.zero,
                          color: BentoTheme.successGreen.withValues(alpha: 0.15),
                          child: SizedBox(
                            width: 90,
                            height: 90,
                            child: Center(
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: BentoTheme.successGreen,
                                  boxShadow: [
                                    BoxShadow(
                                      color: BentoTheme.successGreen.withValues(alpha: 0.4),
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Breathing prompt
              Text(
                actionText,
                style: GoogleFonts.montserrat(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: BentoTheme.cream,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Respiración Cuadrada (4s)',
                style: GoogleFonts.montserrat(
                  fontSize: 10,
                  color: BentoTheme.creamAlpha(0.35),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ----------------------------------------------------
// CUSTOM NEUMORPHIC ARCS PAINTER
// ----------------------------------------------------

class _NeumorphicGlowRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _NeumorphicGlowRingPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = size.width / 2;
    final center = Offset(radius, size.height / 2);
    final double arcRadius = radius - 0.5; // At the absolute outer edge
    final rect = Rect.fromCircle(center: center, radius: arcRadius);

    // Track path (subtle sunken circle guide inside card border)
    final trackPaint = Paint()
      ..color = BentoTheme.neuShadowDark.withValues(alpha: 0.3)
      ..strokeWidth = 4.5 // Thicker track
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, arcRadius, trackPaint);

    final double arcAngle = 2 * math.pi * progress;

    // Neon glow background halo
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 11.0 // Thicker glowing halo
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    canvas.drawArc(rect, -math.pi / 2, arcAngle, false, glowPaint);

    // Active progress arc
    final arcPaint = Paint()
      ..color = color
      ..strokeWidth = 4.5 // Thicker active line
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -math.pi / 2, arcAngle, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _NeumorphicGlowRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
