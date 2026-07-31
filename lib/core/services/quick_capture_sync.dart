import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/note_model.dart';
import '../models/transaction_model.dart';
import '../providers/finance_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/tasks_provider.dart';
import 'quick_capture_parser.dart';
import 'quick_capture_queue.dart';

/// Resultado de un drenaje. `pending` no es un error: son capturas que todavía
/// no se pueden convertir (p.ej. un gasto cuando aún no hay ninguna cuenta
/// creada) y que se quedan en la cola para el siguiente intento.
typedef DrainResult = ({int saved, int pending});

/// Vuelca a Supabase lo que el modal de captura rápida dejó en
/// [QuickCaptureQueue].
///
/// El modal no puede escribir directamente: corre en un engine sin sesión ni
/// Supabase, precisamente para poder abrirse en dos segundos. Esta es la otra
/// mitad del trato.
class QuickCaptureSync {
  const QuickCaptureSync._();

  static bool _running = false;

  /// Drena la cola completa. Es seguro llamarla de más (arranque, cada vuelta a
  /// primer plano): sin nada pendiente sale en una lectura de SharedPreferences.
  static Future<DrainResult> drain(WidgetRef ref) async {
    // El drenaje se dispara al volver a primer plano, y Android puede encadenar
    // dos de esos avisos: sin este cerrojo la misma captura se guardaría dos
    // veces, porque la cola no se limpia hasta el final.
    if (_running) return (saved: 0, pending: 0);
    _running = true;

    try {
      final entries = await QuickCaptureQueue.readAll();
      if (entries.isEmpty) return (saved: 0, pending: 0);

      // Sin sesión no hay dónde guardar. Se deja todo en la cola: la captura
      // hecha antes de iniciar sesión no se pierde, entra al autenticarse.
      if (Supabase.instance.client.auth.currentUser == null) {
        return (saved: 0, pending: entries.length);
      }

      final done = <String>[];
      for (final entry in entries) {
        try {
          final applied = await _apply(ref, entry);
          if (applied) done.add(entry.id);
        } catch (e) {
          // Un fallo puntual (red, RLS) no debe tumbar el resto del lote ni
          // borrar la entrada: se reintenta en el siguiente drenaje.
          debugPrint('QuickCaptureSync: no pude guardar ${entry.id}: $e');
        }
      }

      await QuickCaptureQueue.removeAll(done);
      return (saved: done.length, pending: entries.length - done.length);
    } finally {
      _running = false;
    }
  }

  /// Devuelve false si la captura todavía no se puede convertir y debe seguir
  /// esperando en la cola.
  static Future<bool> _apply(WidgetRef ref, QuickCaptureEntry entry) async {
    final draft = entry.draft;

    switch (draft.kind) {
      case CaptureKind.expense:
      case CaptureKind.income:
        return _applyTransaction(ref, entry);

      case CaptureKind.task:
        await _applyTask(ref, entry);
        return true;

      case CaptureKind.note:
        await _applyNote(ref, entry);
        return true;
    }
  }

  static Future<bool> _applyTransaction(WidgetRef ref, QuickCaptureEntry entry) async {
    final draft = entry.draft;

    // Red de seguridad: el modal ya impide guardar un gasto sin importe, pero
    // una cola vieja podría traerlo. Antes que perder lo escrito, se convierte
    // en nota.
    if (draft.amount == null) {
      await _applyNote(ref, entry);
      return true;
    }

    final accounts = await ref.read(accountsProvider.future);
    if (accounts.isEmpty) return false; // aún no hay dónde imputarlo

    await ref.read(transactionsProvider.notifier).addTransaction(
          TransactionModel(
            // id, userId y createdAt los pone Supabase al insertar; addTransaction
            // solo serializa el resto.
            id: '',
            userId: '',
            accountId: accounts.first.id,
            type: draft.kind == CaptureKind.income
                ? TransactionType.income
                : TransactionType.expense,
            amount: draft.amount!,
            category: draft.categoryId ?? 'other',
            description: draft.title,
            // La fecha es la de la captura, no la del volcado: un gasto anotado
            // el viernes sin conexión sigue siendo del viernes.
            occurredAt: entry.capturedAt,
            createdAt: entry.capturedAt,
          ),
        );

    return true;
  }

  static Future<void> _applyTask(WidgetRef ref, QuickCaptureEntry entry) async {
    final draft = entry.draft;
    final when = draft.scheduledAt ?? entry.capturedAt;

    await ref.read(tasksProvider.notifier).addTask(
          title: draft.title.isEmpty ? draft.rawText : draft.title,
          dueDate: DateTime(when.year, when.month, when.day),
          startAt: when,
          // Solo se programa recordatorio si se dijo una hora: avisar a las
          // 00:00 de un "revisar el contrato el lunes" sería ruido.
          remindAt: draft.hasExplicitTime && when.isAfter(DateTime.now()) ? when : null,
          plannedAt: entry.capturedAt,
        );
  }

  static Future<void> _applyNote(WidgetRef ref, QuickCaptureEntry entry) async {
    final draft = entry.draft;
    final body = draft.rawText.trim();

    await ref.read(notesProvider.notifier).addNote(
          _titleFrom(draft.title.isEmpty ? body : draft.title),
          body,
          priority: NotePriority.normal,
        );
  }

  /// Un título de nota es una línea corta; el texto íntegro va al cuerpo, así
  /// que aquí se puede cortar sin perder nada.
  static String _titleFrom(String text) {
    final firstLine = text.split('\n').first.trim();
    if (firstLine.length <= 60) return firstLine.isEmpty ? 'Captura rápida' : firstLine;

    final cut = firstLine.substring(0, 60);
    final lastSpace = cut.lastIndexOf(' ');
    return '${lastSpace > 30 ? cut.substring(0, lastSpace) : cut}…';
  }
}
