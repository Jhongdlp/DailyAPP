import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistem_daily/core/providers/appearance_provider.dart';
import 'package:sistem_daily/core/theme/app_palette.dart';
import 'package:sistem_daily/features/settings/personalize_screen.dart';

/// La pantalla de personalizar no depende de Supabase ni de red, así que sí se
/// puede montar de verdad en un test (a diferencia del smoke test del
/// dashboard). Esto cubre lo que el analizador no ve: que construya, que los
/// controles cambien el estado y que la vista previa siga a la elección.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PersonalizeScreen()),
      ),
    );
    await tester.pump();
    return container;
  }

  /// El viewport del test mide 600px y la pantalla es bastante más larga, así
  /// que hacen falta los dos pasos y en este orden:
  ///
  /// - Lo que cae MUY abajo ni siquiera está construido (la ListView es
  ///   perezosa), y un finder no encuentra lo que no existe: hay que desplazar
  ///   a ciegas con scrollUntilVisible hasta que aparezca.
  /// - Lo que cae justo debajo del borde SÍ está construido (entra en el cache
  ///   extent), así que scrollUntilVisible se da por satisfecho sin mover nada
  ///   y el toque caería fuera de pantalla: ahí hace falta ensureVisible.
  Future<void> tapText(WidgetTester tester, String label) async {
    final finder = find.text(label);
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 120, scrollable: find.byType(Scrollable).first);
    }
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('monta sin errores', (tester) async {
    await pump(tester);
    expect(find.text('Personalizar'), findsOneWidget);
    expect(find.text('Vívida'), findsOneWidget);
    expect(find.text('La tuya'), findsOneWidget);
  });

  testWidgets('elegir el modo sistema lo guarda', (tester) async {
    final container = await pump(tester);
    expect(container.read(appearanceProvider).mode, ThemeMode.dark);

    await tapText(tester, 'Sistema');

    expect(container.read(appearanceProvider).mode, ThemeMode.system);
  });

  testWidgets('elegir un preset cambia la paleta activa', (tester) async {
    final container = await pump(tester);

    await tapText(tester, 'Océano');

    expect(container.read(appearanceProvider).palette.presetId, 'ocean');
  });

  testWidgets('la paleta propia despliega sus controles y responde al esquema',
      (tester) async {
    final container = await pump(tester);

    // Los controles de semilla solo existen cuando la paleta propia está
    // elegida: no tiene sentido ajustar una paleta que no se está usando.
    expect(find.text('Tu color'), findsNothing);

    await tapText(tester, 'La tuya');

    expect(container.read(appearanceProvider).palette.isCustom, isTrue);
    expect(find.text('Tu color'), findsOneWidget);

    await tapText(tester, 'Tríada');

    expect(container.read(appearanceProvider).palette.scheme, PaletteScheme.triad);
  });

  testWidgets('restablecer vuelve a fábrica sin tocar el modo', (tester) async {
    final container = await pump(tester);
    final notifier = container.read(appearanceProvider.notifier);

    notifier.setMode(ThemeMode.light);
    notifier.setPreset('neon');
    notifier.setMaterial(const MaterialSpec(hue: 30, chroma: 0.03));
    await tester.pump();

    await tapText(tester, 'Restablecer colores');

    final state = container.read(appearanceProvider);
    expect(state.palette.presetId, 'vivid');
    expect(state.material, isNull);
    expect(state.mode, ThemeMode.light, reason: 'restablecer colores no es cambiar de modo');
  });

  testWidgets('la elección sobrevive a reabrir la app', (tester) async {
    final first = await pump(tester);
    first.read(appearanceProvider.notifier).setPreset('forest');
    await tester.pumpAndSettle();

    // Un contenedor nuevo = un arranque nuevo leyendo las preferencias.
    final second = ProviderContainer();
    addTearDown(second.dispose);
    second.read(appearanceProvider);
    await tester.pumpAndSettle();

    expect(second.read(appearanceProvider).palette.presetId, 'forest');
  });
}
