import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistem_daily/core/models/app_destination.dart';
import 'package:sistem_daily/core/widgets/liquid_glass_dock.dart';

void main() {
  testWidgets('el dock flotante monta, marca el hueco y viaja', (tester) async {
    var current = AppDestination.habits.tabIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Stack(
              children: [
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: LiquidGlassDock(
                    slots: const [
                      AppDestination.habits,
                      AppDestination.notes,
                      AppDestination.alarm,
                      AppDestination.finance,
                    ],
                    currentIndex: current,
                    onSelect: (d) => setState(() => current = d.tabIndex),
                    onMenu: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(AppDestination.finance.icon), findsOneWidget);

    await tester.tap(find.byIcon(AppDestination.finance.icon));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // a mitad del viaje
    await tester.pumpAndSettle();

    expect(current, AppDestination.finance.tabIndex);
  });

  testWidgets('sin hueco marcado (destino fuera del dock) no revienta', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiquidGlassDock(
            slots: const [AppDestination.habits, AppDestination.notes, AppDestination.alarm],
            currentIndex: AppDestination.news.tabIndex,
            overflowActive: AppDestination.news,
            onSelect: (_) {},
            onMenu: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
  });
}
