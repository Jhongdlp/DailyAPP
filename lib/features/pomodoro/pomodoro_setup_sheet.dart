import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/bento_theme.dart';
import 'providers/pomodoro_provider.dart';
import 'pomodoro_screen.dart';

class PomodoroSetupSheet extends ConsumerStatefulWidget {
  const PomodoroSetupSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PomodoroSetupSheet(),
    );
  }

  @override
  ConsumerState<PomodoroSetupSheet> createState() => _PomodoroSetupSheetState();
}

class _PomodoroSetupSheetState extends ConsumerState<PomodoroSetupSheet> {
  int workMin = 25;
  int breakMin = 5;
  int longBreakMin = 15;
  int rightMode = 0; // 0: frase, 1: carrusel, 2: tareas, 3: respiración

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: BentoTheme.neuSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: BentoTheme.neuFloating(elevation: 24),
      ),
      padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + bottomInset + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: BentoTheme.creamAlpha(0.2),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Row(
            children: [
              const Text(
                '🍅',
                style: TextStyle(fontSize: 28),
              ),
              const SizedBox(width: 12),
              Text(
                'Configurar Pomodoro',
                style: GoogleFonts.montserrat(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: BentoTheme.cream,
                  letterSpacing: -0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Durations Selectors Row (3 Columns)
          Row(
            children: [
              // Work Duration
              Expanded(
                child: _buildDurationSelector(
                  title: 'ENFOQUE',
                  value: workMin,
                  color: const Color(0xFF4EA8DE), // Friendly Celeste
                  onChanged: (val) {
                    setState(() {
                      workMin = val.clamp(1, 120);
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              // Short Break Duration
              Expanded(
                child: _buildDurationSelector(
                  title: 'DESC. CORTO',
                  value: breakMin,
                  color: BentoTheme.successGreen, // soothing green
                  onChanged: (val) {
                    setState(() {
                      breakMin = val.clamp(1, 60);
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              // Long Break Duration
              Expanded(
                child: _buildDurationSelector(
                  title: 'DESC. LARGO',
                  value: longBreakMin,
                  color: BentoTheme.accentPurple, // deep purple for long rest
                  onChanged: (val) {
                    setState(() {
                      longBreakMin = val.clamp(1, 120);
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Right Panel Display Selectors
          Text(
            'PANEL DERECHO (PANTALLA SALVAPANTALLAS)',
            style: GoogleFonts.montserrat(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: BentoTheme.creamAlpha(0.4),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildRightModeTile(0, 'Frase Fija', Icons.format_quote),
              _buildRightModeTile(1, 'Carrusel Frases', Icons.slideshow),
              _buildRightModeTile(2, 'Tareas del Día', Icons.check_box_outlined),
              _buildRightModeTile(3, 'Respiración', Icons.lens_outlined),
            ],
          ),
          const SizedBox(height: 32),

          // Start Button
          GestureDetector(
            onTap: () {
              ref.read(pomodoroProvider.notifier).configure(
                    workDuration: workMin,
                    breakDuration: breakMin,
                    longBreakDuration: longBreakMin,
                    rightPanelMode: rightMode,
                  );
              ref.read(pomodoroProvider.notifier).start();

              Navigator.pop(context); // Close sheet
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PomodoroScreen(),
                ),
              );
            },
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: const Color(0xFF4EA8DE), // Friendly Celeste
                boxShadow: BentoTheme.neuRaised(distance: 4, blur: 8),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF4EA8DE),
                            Color(0xFF0077B6),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                      const SizedBox(width: 8),
                      Text(
                        'Iniciar Enfoque',
                        style: GoogleFonts.montserrat(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationSelector({
    required String title,
    required int value,
    required Color color,
    required ValueChanged<int> onChanged,
  }) {
    return NeuCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      child: Column(
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.montserrat(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: BentoTheme.creamAlpha(0.4),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Decrease Button
              GestureDetector(
                onTap: () => onChanged(value - 5),
                onLongPress: () => onChanged(value - 1),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: BentoTheme.neuSurfaceSunken,
                    shape: BoxShape.circle,
                    boxShadow: BentoTheme.neuRaisedLite(distance: 1.5, blur: 3),
                  ),
                  child: Icon(Icons.remove, size: 14, color: BentoTheme.cream),
                ),
              ),
              // Value Display
              Text(
                '$value',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              // Increase Button
              GestureDetector(
                onTap: () => onChanged(value + 5),
                onLongPress: () => onChanged(value + 1),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: BentoTheme.neuSurfaceSunken,
                    shape: BoxShape.circle,
                    boxShadow: BentoTheme.neuRaisedLite(distance: 1.5, blur: 3),
                  ),
                  child: Icon(Icons.add, size: 14, color: BentoTheme.cream),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'minutos',
            style: GoogleFonts.montserrat(
              fontSize: 9,
              color: BentoTheme.creamAlpha(0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightModeTile(int mode, String title, IconData icon) {
    final isSelected = rightMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          rightMode = mode;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? BentoTheme.neuSurfaceSunken : BentoTheme.neuSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFF4EA8DE) : BentoTheme.creamAlpha(0.08),
            width: 1.5,
          ),
          boxShadow: isSelected
              ? []
              : BentoTheme.neuRaisedLite(distance: 2, blur: 4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? const Color(0xFF4EA8DE) : BentoTheme.creamAlpha(0.55),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: GoogleFonts.montserrat(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? BentoTheme.cream : BentoTheme.creamAlpha(0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
