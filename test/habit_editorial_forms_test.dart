import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_twemoji/flutter_twemoji.dart';
import 'package:sistem_daily/core/models/habit_model.dart';
import 'package:sistem_daily/features/habits/habit_form_editorial.dart';
import 'package:sistem_daily/features/habits/habit_template_picker_editorial.dart';

/// Estas dos hojas se pueden montar de verdad en un test —a diferencia de la
/// pestaña entera— porque no leen `habitsProvider` hasta que se pulsa guardar:
/// sólo escriben en él. Eso permite cubrir lo que el analizador no ve, que en
/// una hoja editorial es sobre todo el layout: dentro de `showEditorialSheet`
/// el contenido va en un `Flexible`, y el formulario mete un `Expanded` ahí
/// dentro para dejar el botón de guardar fuera del scroll. Esa combinación
/// revienta con constraints sin acotar, y revienta sólo en tiempo de ejecución.
void main() {
  /// Abre una hoja desde un botón, que es como se abren de verdad: montarlas
  /// sueltas les daría constraints que en la app no tienen.
  Future<void> openSheet(
    WidgetTester tester,
    void Function(BuildContext context, WidgetRef ref) open,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => open(context, ref),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  /// El ListView de la hoja es el PRIMER Scrollable del árbol —contiene a los
  /// demás, que son los internos de cada TextField—. Apuntar a `.last` agarra
  /// uno de esos y el desplazamiento no llega a ninguna parte.
  Future<void> scrollTo(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }

  testWidgets('el formulario de hábito monta con sus secciones', (tester) async {
    await openSheet(tester, (context, ref) => showHabitFormEditorial(context, ref));

    expect(find.text('NUEVO HÁBITO'), findsOneWidget);
    expect(find.text('ÍCONO'), findsOneWidget);
    // El botón vive fuera del scroll: tiene que verse sin desplazar nada.
    expect(find.text('Crear hábito'), findsOneWidget);

    // Lo de más abajo sí hay que ir a buscarlo — la lista es perezosa. Que
    // llegue significa además que el scroll interno funciona pese al Expanded.
    await scrollTo(tester, find.text('QUÉ DÍAS TOCA'));
    expect(find.text('QUÉ DÍAS TOCA'), findsOneWidget);
    // Los siete días de la semana, y el botón sigue en su sitio.
    expect(find.text('X'), findsOneWidget);
    expect(find.text('Crear hábito'), findsOneWidget);
  });

  testWidgets('editar un hábito prellena el nombre y dice que edita',
      (tester) async {
    final habit = Habit(
      id: 'h1',
      name: 'Correr al alba',
      icon: '🏃',
      color: '#FF8600',
      category: HabitCategory.health,
      daysOfWeek: const [1, 3, 5],
      completedDates: {},
    );

    await openSheet(
      tester,
      (context, ref) => showHabitFormEditorial(context, ref, existing: habit),
    );

    expect(find.text('EDITAR HÁBITO'), findsOneWidget);
    expect(find.text('Correr al alba'), findsOneWidget);
    expect(find.text('Guardar cambios'), findsOneWidget);
  });

  testWidgets('elegir la gota prellena el hábito de agua entero', (tester) async {
    await openSheet(tester, (context, ref) => showHabitFormEditorial(context, ref));

    // Arranca vacío: sin unidad y sin categoría de salud elegida.
    expect(find.text('L'), findsNothing);

    // El emoji se dibuja con Twemoji (una imagen), no hay texto que buscar. En
    // la rejilla mide 21px; el de la portada, 28 — de ahí el filtro.
    final drop = find.byWidgetPredicate(
      (w) => w is Twemoji && w.emoji == '💧' && w.height == 21,
    );
    expect(drop, findsOneWidget);
    await tester.tap(drop);
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate((w) => w is Twemoji && w.emoji == '💧' && w.height == 28),
      findsOneWidget,
      reason: 'la portadilla tiene que reflejar el ícono elegido',
    );

    // Meta prellenada en litros, y los avisos encendidos y repartidos por el
    // día: 2 L a 0.25 L por vaso son ocho.
    await scrollTo(tester, find.text('META DIARIA (OPCIONAL)'));
    expect(find.text('2'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);

    await scrollTo(tester, find.text('RECORDATORIOS'));
    expect(find.text('Otra hora'), findsOneWidget);
  });

  testWidgets('el catálogo de plantillas monta como índice', (tester) async {
    await openSheet(
      tester,
      (context, ref) => showHabitTemplatePickerEditorial(context, ref),
    );

    expect(find.text('ELIGE UN HÁBITO'), findsOneWidget);
    expect(find.text('Tomar agua'), findsOneWidget);
    expect(find.text('Meditar'), findsOneWidget);
  });
}
