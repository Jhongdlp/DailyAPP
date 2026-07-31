import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/bento_theme.dart';
import '../pomodoro_palette.dart';
import '../providers/pomodoro_provider.dart';

/// Hoja de captura rápida de una interrupción.
///
/// El objetivo es que anotar cueste menos que ceder: se abre, se escribe y se
/// cierra sin tocar el temporizador ni salir de la sesión.
Future<void> showDistractionCapture(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _DistractionCaptureSheet(),
  );
}

class _DistractionCaptureSheet extends ConsumerStatefulWidget {
  const _DistractionCaptureSheet();

  @override
  ConsumerState<_DistractionCaptureSheet> createState() =>
      _DistractionCaptureSheetState();
}

class _DistractionCaptureSheetState
    extends ConsumerState<_DistractionCaptureSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    ref.read(pomodoroProvider.notifier).captureDistraction(text);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final captured =
        ref.watch(pomodoroProvider.select((s) => s.distractions.length));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: BentoTheme.neuSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: BentoTheme.neuFloating(elevation: 24),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: BentoTheme.creamAlpha(0.18),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(Icons.bolt_rounded,
                    size: 20, color: BentoTheme.accentOrange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Aparcar la distracción',
                    style: GoogleFonts.montserrat(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: BentoTheme.cream,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                if (captured > 0)
                  Text(
                    '$captured en la bandeja',
                    style: GoogleFonts.montserrat(
                      fontSize: 10,
                      color: BentoTheme.creamAlpha(0.35),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Escríbelo y suéltalo. Lo revisas en el descanso.',
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                color: BentoTheme.creamAlpha(0.5),
              ),
            ),
            const SizedBox(height: 16),
            NeuPressed(
              borderRadius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _controller,
                autofocus: true,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  color: BentoTheme.cream,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Responder el correo de Ana…',
                  hintStyle: GoogleFonts.outfit(
                    fontSize: 15,
                    color: BentoTheme.creamAlpha(0.28),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            NeuCard(
              borderRadius: 18,
              distance: 4,
              blur: 8,
              padding: const EdgeInsets.symmetric(vertical: 15),
              color: BentoTheme.accentOrange.withValues(alpha: 0.14),
              onTap: _submit,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_rounded,
                      size: 18, color: BentoTheme.accentOrange),
                  const SizedBox(width: 8),
                  Text(
                    'Aparcar y seguir',
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: BentoTheme.cream,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La bandeja ya capturada, con la opción de volcarla a una nota. Se muestra
/// en el descanso, que es cuando revisar interrupciones no rompe nada.
class DistractionInbox extends ConsumerWidget {
  const DistractionInbox({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final distractions =
        ref.watch(pomodoroProvider.select((s) => s.distractions));
    if (distractions.isEmpty) return const SizedBox.shrink();

    return NeuCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.inbox_rounded,
                  size: 15, color: BentoTheme.accentOrange),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'APARCADO (${distractions.length})',
                  style: GoogleFonts.montserrat(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: BentoTheme.creamAlpha(0.45),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  final saved = await ref
                      .read(pomodoroProvider.notifier)
                      .saveDistractionsAsNote();
                  if (saved && context.mounted) {
                    HapticFeedback.selectionClick();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Guardado en Notas'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: Text(
                  'Guardar en notas',
                  style: GoogleFonts.montserrat(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: PomodoroPalette.focus,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Tope en vez de `Flexible`: así la bandeja funciona igual dentro de
          // un hueco medido que dentro de una columna que hace scroll, donde
          // un hijo flexible reventaría por altura no acotada.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 148),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: distractions.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: BentoTheme.accentOrange.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        distractions[i].text,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          height: 1.35,
                          color: BentoTheme.creamAlpha(0.8),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () =>
                          ref.read(pomodoroProvider.notifier).removeDistraction(i),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Icon(Icons.close_rounded,
                            size: 14, color: BentoTheme.creamAlpha(0.3)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
