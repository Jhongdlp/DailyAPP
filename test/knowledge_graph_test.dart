import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistem_daily/core/models/note_model.dart';
import 'package:sistem_daily/features/notes/knowledge_graph_view.dart';

void main() {
  Note note(String id, String title, {List<String> links = const []}) => Note(
        id: id,
        title: title,
        content: 'contenido de $title',
        linkedNoteIds: links,
      );

  testWidgets('el mundo del grafo tiene su tamaño real (no recortado al viewport)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KnowledgeGraphView(
            notes: [
              note('a', 'Nota A', links: ['b']),
              note('b', 'Nota B'),
              note('c', 'Nota C'),
            ],
            vaults: const [],
            onOpenNote: (_) {},
          ),
        ),
      ),
    );
    // Dejar correr algunos frames de la simulación de fuerzas
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // Regresión del bug "grafo vacío": sin OverflowBox, las restricciones
    // ajustadas del viewport forzaban el mundo al tamaño de pantalla y el
    // Stack recortaba todos los nodos (posicionados cerca de worldSize/2).
    final world = tester.getSize(find.byKey(const ValueKey('graph-world')));
    expect(world.width, 2400);
    expect(world.height, 2400);

    // Los nodos se renderizan con sus títulos
    expect(find.text('Nota A'), findsOneWidget);
    expect(find.text('Nota B'), findsOneWidget);
    expect(find.text('Nota C'), findsOneWidget);

    // Y quedan visibles dentro del viewport (mundo centrado por el pan inicial)
    final viewport = tester.getRect(find.byType(KnowledgeGraphView));
    final nodeCenter = tester.getCenter(find.text('Nota A'));
    expect(viewport.contains(nodeCenter), isTrue,
        reason: 'El nodo debe pintarse dentro del viewport visible');
  });

  testWidgets('tap en un nodo abre la mini-card de focus', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KnowledgeGraphView(
            notes: [note('a', 'Nota A', links: ['b']), note('b', 'Nota B')],
            vaults: const [],
            onOpenNote: (_) {},
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    await tester.tap(find.text('Nota A'), warnIfMissed: false);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.text('Abrir nota'), findsOneWidget);
  });
}
