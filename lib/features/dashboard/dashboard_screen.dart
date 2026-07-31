import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/bento_theme.dart';
import '../alarm/alarm_tab.dart';
import '../habits/habits_tab.dart';
import '../notes/notes_tab.dart';
import '../chat/chat_tab.dart';
import '../finance/finance_tab.dart';
import '../reading/reading_tab.dart';
import '../reading/shared_books_handler.dart';
import '../agenda/agenda_tab.dart';
import '../news/news_tab.dart';
import '../character/character_screen.dart';
import '../auth/auth_screen.dart';
import '../settings/personalize_screen.dart';
import '../../core/models/app_destination.dart';
import '../../core/providers/dock_provider.dart';
import '../../core/providers/vault_provider.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/providers/tasks_provider.dart';
import '../../core/providers/books_provider.dart';
import '../../core/providers/book_bookmarks_provider.dart';
import '../../core/services/cache_service.dart';
import '../../core/widgets/lazy_indexed_stack.dart';
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
  final List<Widget> _tabs = [
    const HabitsTab(),
    const NotesTab(),
    const AlarmTab(),
    const FinanceTab(),
    const ChatTab(),
    const AgendaTab(),
    const ReadingTab(),
    const NewsTab(),
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

    // BentoBackground ya no reserva el inset inferior: lo consume el dock para
    // poder nacer del borde físico de la pantalla.
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
                  children: _tabs,
                ),
              ),
            ),

          // Dock de navegación — neumórfico / skeuomorph moderno: no flota,
          // nace del borde inferior como una pieza extruida del chasis, con
          // solo las esquinas superiores redondeadas. El tab activo se hunde
          // en su superficie.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: RepaintBoundary(
              child: NeuCard(
                radius: const BorderRadius.vertical(top: Radius.circular(28)),
                distance: 7,
                blur: 14,
                padding: EdgeInsets.only(
                  top: 12,
                  left: 10,
                  right: 10,
                  // El dock se extiende bajo la barra de gestos; los iconos se
                  // quedan por encima de ella.
                  bottom: 12 + bottomInset,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (final destination in dock.slots)
                      Expanded(child: _buildTabItem(destination)),
                    Expanded(child: _buildConfigItem()),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
     ),
    );
  }

  Widget _buildConfigItem() {
    return _AnimatedConfigItem(
      onTap: () => _showConfigSheet(context),
    );
  }

  void _showConfigSheet(BuildContext context) {
    final overflow = ref.read(dockProvider).overflow;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return ConstrainedBox(
          // Con el dock en 3 huecos la lista crece hasta 4 destinos extra: en
          // pantallas cortas tiene que poder desplazarse en vez de desbordar.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
          ),
          child: NeuCard(
          radius: const BorderRadius.vertical(top: Radius.circular(28)),
          elevation: 22,
          convex: false,
          padding: EdgeInsets.only(
            top: 10,
            bottom: 10 + MediaQuery.viewPaddingOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const NeuPressed(
                borderRadius: 3,
                distance: 2,
                blur: 3,
                child: SizedBox(width: 40, height: 5),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [

              // 1. Ir a — solo lo que no cabe en el dock: repetir aquí una
              // pestaña que ya está a un toque de distancia solo alarga la lista.
              if (overflow.isNotEmpty) ...[
                _SheetSection('Ir a'),
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
                const SizedBox(height: 4),
              ],

              // 2. Tuyo
              _SheetSection('Tu cuenta'),
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

              const SizedBox(height: 4),

              // 3. App
              _SheetSection('Aplicación'),
              _SheetTile(
                icon: Icons.system_update_outlined,
                color: BentoTheme.accentFinance,
                label: 'Buscar actualizaciones',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  UpdateChecker.check(context, silent: false);
                },
              ),

              // Cerrar sesión
              ListTile(
                leading: const Icon(Icons.logout_outlined, color: BentoTheme.errorRed),
                title: Text(
                  'Cerrar sesión',
                  style: GoogleFonts.montserrat(color: BentoTheme.errorRed, fontWeight: FontWeight.w600),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  
                  await CacheService.delete('habits');
                  await CacheService.delete('notes');
                  await CacheService.delete('tasks');
                  await CacheService.delete('books');
                  await CacheService.delete('book_bookmarks');

                  await Supabase.instance.client.auth.signOut();

                  ref.invalidate(vaultProvider);
                  ref.invalidate(vaultsProvider);
                  ref.invalidate(habitsProvider);
                  ref.invalidate(notesProvider);
                  ref.invalidate(tasksProvider);
                  ref.invalidate(booksProvider);
                  ref.invalidate(bookBookmarksProvider);
                  
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
        );
      },
    );
  }

  Widget _buildTabItem(AppDestination destination) {
    return _AnimatedTabItem(
      icon: destination.icon,
      isSelected: _currentIndex == destination.tabIndex,
      activeColor: destination.accent,
      onTap: () => setState(() => _currentIndex = destination.tabIndex),
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label.toUpperCase(),
          style: GoogleFonts.montserrat(
            color: BentoTheme.creamTertiary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
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

  const _SheetTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
    );
  }
}

class _AnimatedTabItem extends StatefulWidget {
  final IconData icon;
  final bool isSelected;
  final Color activeColor;
  final VoidCallback onTap;

  const _AnimatedTabItem({
    required this.icon,
    required this.isSelected,
    required this.activeColor,
    required this.onTap,
  });

  @override
  State<_AnimatedTabItem> createState() => _AnimatedTabItemState();
}

class _AnimatedTabItemState extends State<_AnimatedTabItem> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.80)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.80, end: 1.15)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.15, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 30,
      ),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(covariant _AnimatedTabItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.activeColor;
    
    final iconWidget = AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.isSelected ? _scaleAnimation.value : 1.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Icon(
              widget.icon,
              color: widget.isSelected ? activeColor : BentoTheme.creamAlpha(0.42),
              size: 22,
            ),
          ),
        );
      },
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!widget.isSelected) {
          widget.onTap();
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
        child: widget.isSelected
            ? NeuPressed(
                key: const ValueKey('selected'),
                borderRadius: 16,
                distance: 3,
                blur: 6,
                color: Color.alphaBlend(
                  activeColor.withValues(alpha: 0.10),
                  BentoTheme.neuSurfaceSunken,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: iconWidget,
                ),
              )
            : SizedBox(
                key: const ValueKey('unselected'),
                width: double.infinity,
                child: iconWidget,
              ),
      ),
    );
  }
}

class _AnimatedConfigItem extends StatefulWidget {
  final VoidCallback onTap;
  const _AnimatedConfigItem({required this.onTap});

  @override
  State<_AnimatedConfigItem> createState() => _AnimatedConfigItemState();
}

class _AnimatedConfigItemState extends State<_AnimatedConfigItem> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _controller.forward(from: 0.0);
        widget.onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: RotationTransition(
          turns: Tween<double>(begin: 0.0, end: 0.25).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
          ),
          child: Icon(
            Icons.menu_rounded,
            color: BentoTheme.creamAlpha(0.42),
            size: 22,
          ),
        ),
      ),
    );
  }
}
