import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/update_service.dart';
import '../../core/theme/bento_theme.dart';

/// Punto único para buscar y aplicar actualizaciones desde la UI.
///
/// - [check] con `silent: true` (al iniciar la app) no muestra nada si ya está
///   al día ni si falla la comprobación.
/// - [check] con `silent: false` (botón manual) avisa "estás al día" o el error.
class UpdateChecker {
  /// Comprueba si hay actualización y, si la hay, ofrece instalarla.
  static Future<void> check(BuildContext context, {bool silent = true}) async {
    final info = await UpdateService.checkForUpdate();

    if (!context.mounted) return;

    if (info == null) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ya tienes la última versión.')),
        );
      }
      return;
    }

    _showUpdateDialog(context, info);
  }

  static void _showUpdateDialog(BuildContext context, UpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: BentoTheme.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: BentoTheme.creamAlpha(0.1)),
          ),
          title: Row(
            children: [
              const Icon(Icons.system_update, color: BentoTheme.accentLime),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Actualización disponible',
                  style: GoogleFonts.montserrat(
                    color: BentoTheme.cream,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Versión ${info.version}',
                style: GoogleFonts.montserrat(
                  color: BentoTheme.accentLime,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (info.releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Text(
                      info.releaseNotes,
                      style: GoogleFonts.montserrat(
                        color: BentoTheme.creamSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Ahora no',
                style: GoogleFonts.montserrat(color: BentoTheme.creamTertiary),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: BentoTheme.accentLime,
                foregroundColor: BentoTheme.darkBg,
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _showDownloadDialog(context, info);
              },
              child: Text(
                'Actualizar',
                style: GoogleFonts.montserrat(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }

  static void _showDownloadDialog(BuildContext context, UpdateInfo info) {
    final progress = ValueNotifier<double>(0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        // Iniciar la descarga una sola vez cuando se construye el diálogo.
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            await UpdateService.downloadAndInstall(
              info,
              onProgress: (p) => progress.value = p,
            );
            if (ctx.mounted) Navigator.of(ctx).pop();
          } catch (e) {
            if (ctx.mounted) Navigator.of(ctx).pop();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('No se pudo descargar la actualización: $e'),
                  backgroundColor: BentoTheme.errorRed,
                ),
              );
            }
          }
        });

        return AlertDialog(
          backgroundColor: BentoTheme.darkCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: BentoTheme.creamAlpha(0.1)),
          ),
          content: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, value, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Descargando actualización…',
                    style: GoogleFonts.montserrat(
                      color: BentoTheme.cream,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: value > 0 ? value : null,
                      minHeight: 8,
                      backgroundColor: BentoTheme.creamAlpha(0.12),
                      color: BentoTheme.accentLime,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    value > 0 ? '${(value * 100).toStringAsFixed(0)}%' : '',
                    style: GoogleFonts.montserrat(
                      color: BentoTheme.creamSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
