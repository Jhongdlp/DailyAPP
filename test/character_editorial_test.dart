import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistem_daily/core/models/app_destination.dart';
import 'package:sistem_daily/features/character/character_tab_editorial.dart';

void main() {
  test('AppDestination enum contains character as the last destination', () {
    expect(AppDestination.values.last, AppDestination.character);
    expect(AppDestination.character.label, 'Personaje');
    expect(AppDestination.character.tabIndex, 10);
  });

  testWidgets('CharacterTabEditorial mounts and renders hero level and sections', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CharacterTabEditorial(animate: false),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Personaje'), findsOneWidget);
    expect(find.text('Atributos'), findsOneWidget);
    expect(find.text('Héroes'), findsOneWidget);
    expect(find.text('Bazar'), findsOneWidget);
    expect(find.text('Logros'), findsOneWidget);
    expect(find.text('Premios'), findsOneWidget);
    expect(find.text('ATRIBUTOS DEL HÉROE'), findsOneWidget);
  });

  testWidgets('CharacterTabEditorial switches to Heroes section', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CharacterTabEditorial(animate: false),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Héroes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('CATÁLOGO DE HÉROES'), findsOneWidget);
  });

  testWidgets('CharacterTabEditorial switches to Bazar section', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CharacterTabEditorial(animate: false),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Bazar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('BAZAR DE ACCESORIOS'), findsOneWidget);
  });

  testWidgets('CharacterTabEditorial switches to Rewards section', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CharacterTabEditorial(animate: false),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.ensureVisible(find.text('Premios'));
    await tester.tap(find.text('Premios'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('RECOMPENSAS PERSONALIZADAS'), findsOneWidget);
  });
}
