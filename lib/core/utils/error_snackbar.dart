import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/bento_theme.dart';

void showErrorSnackBar(
  BuildContext context, {
  required String message,
  Duration duration = const Duration(seconds: 5),
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: message));
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Error copiado al portapapeles'),
                    backgroundColor: BentoTheme.successGreen,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy, color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
      backgroundColor: BentoTheme.errorRed,
      duration: duration,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
    ),
  );
}

void showSuccessSnackBar(
  BuildContext context, {
  required String message,
  Duration duration = const Duration(seconds: 3),
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: BentoTheme.successGreen,
      duration: duration,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
    ),
  );
}
