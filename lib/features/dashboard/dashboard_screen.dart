import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/bento_theme.dart';
import '../alarm/alarm_tab.dart';
import '../alarm/alarm_tab_editorial.dart';
// Las pestañas con dos versiones importan las dos: cuál se monta lo decide
// [designLanguageProvider] en `_tabsFor`, no el import. El piloto de
// `habits_tab_minimal.dart` sigue en la carpeta, sin enchufar.
import '../habits/habits_tab.dart';
import '../habits/habits_tab_editorial.dart';
import '../notes/notes_tab.dart';
import '../notes/notes_tab_editorial.dart';
import '../chat/chat_tab.dart';
import '../finance/finance_tab.dart';
import '../finance/finance_tab_editorial.dart';
import '../reading/reading_tab.dart';
import '../reading/reading_tab_editorial.dart';
import '../reading/shared_books_handler.dart';
import '../agenda/agenda_tab.dart';
import '../news/news_tab.dart';
import '../analytics/analytics_tab.dart';
import '../analytics/analytics_tab_editorial.dart';
import '../exercise/exercise_tab.dart';
import '../exercise/exercise_tab_editorial.dart';
import '../character/character_tab.dart';
import '../character/character_tab_editorial.dart';
import '../character/character_screen.dart';
import '../auth/auth_screen.dart';
import '../settings/personalize_screen.dart';
import '../../core/models/app_destination.dart';
import '../../core/providers/appearance_provider.dart';
import '../../core/providers/dock_provider.dart';
import '../../core/providers/vault_provider.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/providers/tasks_provider.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/book_bookmarks_provider.dart';
import '../../core/providers/exercise_provider.dart';
import '../../core/services/cache_service.dart';
import '../../core/theme/design_language.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/widgets/glass_surface.dart';
import '../../core/widgets/lazy_indexed_stack.dart';
import '../../core/widgets/liquid_glass_dock.dart';
import '../../core/widgets/sync_indicator.dart';
import '../update/update_checker.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _currentIndex = 0;

  /// En el mismo orden que [AppDestination]: el índice del enum ES el índice
  /// del stack.
  ///
  /// Se arma en cada build y no una vez en el estado porque las pestañas con
  /// dos implementaciones dependen del lenguaje activo. Es una lista de
  /// widgets `const`: rearmarla no cuesta nada y [LazyIndexedStack] conserva
  /// los subárboles ya montados mientras el tipo del hijo no cambie.
  List<Widget> _tabsFor(DesignLanguage design) => [
    design.isEditorial ? const HabitsTabEditorial() : const HabitsTab(),
    design.isEditorial ? const NotesTabEditorial() : const NotesTab(),
    design.isEditorial ? const AlarmTabEditorial() : const AlarmTab(),
    design.isEditorial ? const FinanceTabEditorial() : const FinanceTab(),
    const ChatTab(),
    const AgendaTab(),
    design.isEditorial ? const ReadingTabEditorial() : const ReadingTab(),
    const NewsTab(),
    design.isEditorial ? const AnalyticsTabEditorial() : const AnalyticsTab(),
    design.isEditorial ? const ExerciseTabEditorial() : const ExerciseTab(),
    design.isEditorial ? const CharacterTabEditorial() : const CharacterTab(),
  ];

  SharedBooksHandler? _sharedBooks;

  @override
  void initState() {
    super.initState();
    _sharedBooks = SharedBooksHandler(
      ref: ref,
      onImported: (count) {
        if (!mounted) return;
        setState(() => _currentIndex = AppDestination.reading.tabIndex);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(count == 1
                ? 'Libro añadido a tu biblioteca'
                : '$count libros añadidos a tu biblioteca'),
          ),
        );
      },
    )..start();
  }

  @override
  void dispose() {
    _sharedBooks?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dock = ref.watch(dockProvider);
    final design = ref.watch(designLanguageProvider);

    // BentoBackground no reserva el inset inferior: lo administra el dock, que
    // flota por encima de la barra de gestos y se separa de ella por su cuenta.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return BentoBackground(
      backgroundColor: BentoTheme.darkBg,
      bottomSafeArea: false,
      child: OrganicAnimatedBackground(
        child: Stack(
          children: [
            // Pantalla principal del Tab Actual — transparente para dejar ver las auroras animadas
            Positioned.fill(
              top: 12,
              bottom: bottomInset,
              child: Container(
                color: Colors.transparent,
                child: LazyIndexedStack(
                  index: _currentIndex,
                  children: _tabsFor(design),
                ),
              ),
            ),

            // Aviso de sincronización pendiente. Va en el stack y no dentro de
            // cada tab porque la cola es de toda la app: da igual en qué
            // pantalla estés cuando se cae la red.
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SyncIndicator(),
                ),
              ),
            ),

            // Dock de navegación — flotante y de vidrio. Ver
            // [LiquidGlassDock]: despegado del borde para que se lea como una
            // capa que viaja sobre el contenido y no como una hoja modal
            // abierta al pie de la pantalla.
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: LiquidGlassDock(
                slots: dock.slots,
                currentIndex: _currentIndex,
                overflowActive: dock.slots.any((d) => d.tabIndex == _currentIndex)
                    ? null
                    : AppDestination.values[_currentIndex],
                onSelect: (destination) =>
                    setState(() => _currentIndex = destination.tabIndex),
                onMenu: () => _showConfigSheet(context),
              ),
            ),
        ],
      ),
     ),
    );
  }

  /// Menú de la app: lo que no es navegación de todos los días.
  ///
  /// Sigue siendo una hoja que sube desde abajo —es el gesto correcto para algo
  /// que se invoca y se descarta— pero ahora es un panel flotante del mismo
  /// vidrio que el dock, con márgenes a los cuatro lados. Así el dock deja de
  /// ser la única pieza despegada de la pantalla y las dos se leen como el
  /// mismo material.
  void _showConfigSheet(BuildContext context) {
    final overflow = ref.read(dockProvider).overflow;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            0,
            12,
            MediaQuery.viewPaddingOf(sheetContext).bottom + 12,
          ),
          child: ConstrainedBox(
            // Con el dock en 3 huecos la lista crece hasta 7 destinos extra: en
            // pantallas cortas tiene que poder desplazarse en vez de desbordar.
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
            ),
            child: GlassSurface(
              borderRadius: BorderRadius.circular(30),
              blur: 26,
              // Más opaco que el dock: acá hay texto largo que leer, y el
              // contenido de la pantalla filtrándose por detrás lo ensucia.
              tint: EditorialTheme.canvas.withValues(alpha: 0.78),
              // Ya está apoyado sobre el velo del modal; la sombra no separaría
              // nada y sólo emborronaría el canto.
              lift: false,
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: EditorialTheme.paperAlpha(0.22),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 1. Ir a — sólo lo que no cabe en el dock: repetir
                          // aquí una pestaña que ya está a un toque de
                          // distancia sólo alarga la lista.
                          if (overflow.isNotEmpty) ...[
                            const _SheetSection('Ir a'),
                            for (final destination in overflow)
                              _SheetTile(
                                icon: destination.icon,
                                color: destination.accent,
                                label: destination.label,
                                onTap: () {
                                  Navigator.of(sheetContext).pop();
                                  setState(() => _currentIndex = destination.tabIndex);
                                },
                              ),
                            const SizedBox(height: 6),
                          ],

                          // 2. Tuyo
                          const _SheetSection('Tu cuenta'),
                          _SheetTile(
                            icon: Icons.person_outline,
                            color: BentoTheme.accentLime,
                            label: 'Mi Personaje',
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const CharacterScreen()),
                              );
                            },
                          ),
                          _SheetTile(
                            icon: Icons.palette_outlined,
                            color: BentoTheme.accentPurple,
                            label: 'Personalizar',
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const PersonalizeScreen()),
                              );
                            },
                          ),

                          const SizedBox(height: 6),

                          // 3. App
                          const _SheetSection('Aplicación'),
                          _SheetTile(
                            icon: Icons.system_update_outlined,
                            color: BentoTheme.accentFinance,
                            label: 'Buscar actualizaciones',
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              UpdateChecker.check(context, silent: false);
                            },
                          ),
                          _SheetTile(
                            icon: Icons.logout_outlined,
                            color: BentoTheme.errorRed,
                            label: 'Cerrar sesión',
                            danger: true,
                            onTap: () async {
                              Navigator.of(sheetContext).pop();

                              await CacheService.delete('habits');
                              await CacheService.delete('notes');
                              await CacheService.delete('tasks');
                              await CacheService.delete('books');
                              await CacheService.delete('book_bookmarks');
                              await CacheService.delete('exercise');

                              await Supabase.instance.client.auth.signOut();

                              ref.invalidate(vaultProvider);
                              ref.invalidate(vaultsProvider);
                              ref.invalidate(habitsProvider);
                              ref.invalidate(notesProvider);
                              ref.invalidate(tasksProvider);
                              ref.invalidate(booksProvider);
                              ref.invalidate(bookBookmarksProvider);
                              ref.invalidate(exerciseProvider);

                              if (context.mounted) {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Encabezado de grupo del menú. Sin él las ocho filas se leen como una lista
/// plana donde "Cerrar sesión" está a la misma altura visual que "Agenda".
class _SheetSection extends StatelessWidget {
  final String label;
  const _SheetSection(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label.toUpperCase(),
          style: EditorialTheme.label(11, color: EditorialTheme.paperAlpha(0.38)),
        ),
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  /// Acción destructiva: el color pasa del icono al texto. Es el único lugar
  /// del sistema donde una etiqueta va coloreada, y por eso se ve.
  final bool danger;

  const _SheetTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    // Sobre el vidrio oscuro manda la variante clara del acento: la misma
    // receta que usa el resto del sistema editorial para pintar sobre lienzo.
    final tone = EditorialTheme.accent(color, onDark: true);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusChip),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: EditorialTheme.paperAlpha(0.06),
          highlightColor: EditorialTheme.paperAlpha(0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            child: Row(
              children: [
                Icon(icon, color: tone, size: 21),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: EditorialTheme.text(
                      15,
                      weight: FontWeight.w600,
                      color: danger ? tone : EditorialTheme.paper,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
