import 'package:flutter_test/flutter_test.dart';
import 'package:sistem_daily/core/services/outbox_service.dart';

/// El outbox es la red que impide que un cambio hecho sin conexión se pierda,
/// así que su semántica se prueba aparte: un fallo aquí no rompe la pantalla,
/// borra datos del usuario en silencio.

OutboxOp _op(
  OutboxOpKind kind, {
  String table = 'habits',
  Map<String, dynamic> payload = const {},
  Map<String, dynamic> match = const {'id': 'h1'},
}) =>
    OutboxOp.create(table: table, kind: kind, payload: payload, match: match);

void main() {
  group('mergeOps', () {
    test('operaciones de filas distintas no se tocan', () {
      final ops = [
        _op(OutboxOpKind.update, payload: {'name': 'A'}),
      ];

      final out = OutboxService.mergeOps(
        ops,
        _op(OutboxOpKind.update, payload: {'name': 'B'}, match: {'id': 'h2'}),
      );

      expect(out, hasLength(2));
    });

    test('la misma tabla con distinta fila no colisiona por el tipo', () {
      final ops = [_op(OutboxOpKind.delete)];

      final out = OutboxService.mergeOps(
        ops,
        _op(OutboxOpKind.delete, table: 'tasks'),
      );

      expect(out, hasLength(2));
    });

    test('dos updates de la misma fila se funden en uno', () {
      final ops = [
        _op(OutboxOpKind.update, payload: {'name': 'A', 'icon': '🔥'}),
      ];

      final out = OutboxService.mergeOps(
        ops,
        _op(OutboxOpKind.update, payload: {'name': 'B'}),
      );

      expect(out, hasLength(1));
      expect(out.single.payload, {'name': 'B', 'icon': '🔥'});
    });

    test('un update sobre un alta pendiente sigue siendo un alta', () {
      // Si se degradara a update, el envío fallaría: la fila todavía no existe
      // en el servidor.
      final ops = [
        _op(OutboxOpKind.insert, payload: {'id': 'h1', 'name': 'A'}),
      ];

      final out = OutboxService.mergeOps(
        ops,
        _op(OutboxOpKind.update, payload: {'name': 'B'}),
      );

      expect(out, hasLength(1));
      expect(out.single.kind, OutboxOpKind.insert);
      expect(out.single.payload, {'id': 'h1', 'name': 'B'});
    });

    test('borrar algo que nació sin conexión no manda nada al servidor', () {
      final ops = [
        _op(OutboxOpKind.insert, payload: {'id': 'h1', 'name': 'A'}),
      ];

      final out = OutboxService.mergeOps(ops, _op(OutboxOpKind.delete));

      expect(out, isEmpty);
    });

    test('borrar una fila que sí existe en el servidor deja solo el delete', () {
      final ops = [
        _op(OutboxOpKind.update, payload: {'name': 'A'}),
      ];

      final out = OutboxService.mergeOps(ops, _op(OutboxOpKind.delete));

      expect(out, hasLength(1));
      expect(out.single.kind, OutboxOpKind.delete);
    });

    test('el upsert repetido de un día se queda con el último', () {
      final match = {'user_id': 'u1', 'plan_date': '2026-07-31'};
      final ops = [
        _op(OutboxOpKind.upsert,
            table: 'day_plans', payload: {'mood': 3}, match: match),
      ];

      final out = OutboxService.mergeOps(
        ops,
        _op(OutboxOpKind.upsert,
            table: 'day_plans', payload: {'mood': 5}, match: match),
      );

      expect(out, hasLength(1));
      expect(out.single.payload['mood'], 5);
    });

    test('la fusión conserva el sitio en la cola', () {
      // El orden es el orden de envío: adelantar una operación podría hacerla
      // llegar antes que otra de la que depende.
      final ops = [
        _op(OutboxOpKind.update, payload: {'name': 'A'}),
        _op(OutboxOpKind.insert, table: 'tasks', match: {'id': 't1'}),
      ];

      final out = OutboxService.mergeOps(
        ops,
        _op(OutboxOpKind.update, payload: {'name': 'B'}),
      );

      expect(out, hasLength(2));
      expect(out.first.table, 'habits');
      expect(out.last.table, 'tasks');
    });

    test('sin filtros no hay identidad: se encola tal cual', () {
      final ops = [_op(OutboxOpKind.insert, match: const {})];

      final out = OutboxService.mergeOps(
        ops,
        _op(OutboxOpKind.insert, match: const {}),
      );

      expect(out, hasLength(2));
    });
  });

  group('reconcileRows', () {
    test('sin nada pendiente devuelve lo del servidor', () {
      final rows = [
        {'id': 'h1', 'name': 'Correr'},
      ];

      expect(OutboxService.reconcileRows(rows, []), rows);
    });

    test('el update pendiente se reaplica encima del servidor', () {
      // Este es el fallo original: el servidor no sabe del cambio y su versión
      // vieja borraba lo que el usuario acababa de hacer.
      final rows = [
        {'id': 'h1', 'name': 'Correr', 'icon': '🏃'},
      ];

      final out = OutboxService.reconcileRows(
        rows,
        [_op(OutboxOpKind.update, payload: {'name': 'Nadar'})],
      );

      expect(out.single['name'], 'Nadar');
      expect(out.single['icon'], '🏃', reason: 'no toca lo que no cambió');
    });

    test('el alta pendiente aparece aunque el servidor no la tenga', () {
      final out = OutboxService.reconcileRows(
        [],
        [
          _op(OutboxOpKind.insert, payload: {'id': 'h1', 'name': 'Leer'}),
        ],
      );

      expect(out, hasLength(1));
      expect(out.single['name'], 'Leer');
    });

    test('el borrado pendiente no reaparece', () {
      final rows = [
        {'id': 'h1', 'name': 'Correr'},
        {'id': 'h2', 'name': 'Leer'},
      ];

      final out = OutboxService.reconcileRows(rows, [_op(OutboxOpKind.delete)]);

      expect(out, hasLength(1));
      expect(out.single['id'], 'h2');
    });

    test('reconcilia por clave compuesta, no solo por id', () {
      // `habit_logs` se identifica por hábito + día: casar solo por `id` dejaría
      // la marca del día fuera.
      final rows = [
        {'habit_id': 'h1', 'completed_on': '2026-07-30', 'progress_value': 1.0},
      ];

      final out = OutboxService.reconcileRows(rows, [
        _op(
          OutboxOpKind.upsert,
          table: 'habit_logs',
          payload: {'progress_value': 3.0},
          match: {'habit_id': 'h1', 'completed_on': '2026-07-31'},
        ),
      ]);

      expect(out, hasLength(2));
      expect(out.last['completed_on'], '2026-07-31');
      expect(out.last['progress_value'], 3.0);
    });

    test('las operaciones se aplican en orden', () {
      final rows = [
        {'id': 'h1', 'name': 'Correr'},
      ];

      final out = OutboxService.reconcileRows(rows, [
        _op(OutboxOpKind.update, payload: {'name': 'Nadar'}),
        _op(OutboxOpKind.delete),
      ]);

      expect(out, isEmpty);
    });

    test('no modifica la lista que recibe', () {
      final rows = [
        {'id': 'h1', 'name': 'Correr'},
      ];

      OutboxService.reconcileRows(rows, [_op(OutboxOpKind.delete)]);

      expect(rows, hasLength(1));
    });
  });

  group('serialización', () {
    test('una operación sobrevive al viaje por JSON', () {
      final op = OutboxOp.create(
        table: 'day_plans',
        kind: OutboxOpKind.upsert,
        payload: {'mood': 4, 'intention': 'terminar el outbox'},
        match: {'user_id': 'u1', 'plan_date': '2026-07-31'},
        onConflict: 'user_id,plan_date',
      );

      final restored = OutboxOp.fromJson(op.toJson());

      expect(restored.id, op.id);
      expect(restored.kind, OutboxOpKind.upsert);
      expect(restored.payload['intention'], 'terminar el outbox');
      expect(restored.match, op.match);
      expect(restored.onConflict, 'user_id,plan_date');
      expect(restored.createdAt, op.createdAt);
    });
  });
}
