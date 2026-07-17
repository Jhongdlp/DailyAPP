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
import '../character/character_screen.dart';
import '../auth/auth_screen.dart';
import '../../core/providers/appearance_provider.dart';
import '../settings/personalize_screen.dart';
import '../../core/providers/vault_provider.dart';
import '../../core/providers/habits_provider.dart';
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

  final List<Widget> _tabs = [
    const HabitsTab(),
    const NotesTab(),
    const AlarmTab(),
    const FinanceTab(),
    const ChatTab(),
  ];

  @override
  Widget build(BuildContext context) {
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
                    Expanded(child: _buildTabItem(icon: Icons.check_circle_outline, index: 0)),
                    Expanded(child: _buildTabItem(icon: Icons.psychology_outlined, index: 1)),
                    Expanded(child: _buildTabItem(icon: Icons.alarm_outlined, index: 2)),
                    Expanded(child: _buildTabItem(icon: Icons.account_balance_wallet_outlined, index: 3)),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return NeuCard(
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
              
              // Mi Personaje / Mi Perfil
              ListTile(
                leading: Icon(Icons.person_outline, color: BentoTheme.accentLime),
                title: Text(
                  'Mi Personaje',
                  style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CharacterScreen()),
                  );
                },
              ),

              // Modo claro / oscuro
              ListTile(
                leading: Icon(
                  BentoTheme.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                  color: BentoTheme.accentFinance,
                ),
                title: Text(
                  BentoTheme.isDark ? 'Modo claro' : 'Modo oscuro',
                  style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  ref.read(appearanceProvider.notifier).toggleMode(BentoTheme.isDark);
                },
              ),

              // Personalizar
              ListTile(
                leading: Icon(Icons.palette_outlined, color: BentoTheme.accentPurple),
                title: Text(
                  'Personalizar',
                  style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PersonalizeScreen()),
                  );
                },
              ),

              // Copiloto
              ListTile(
                leading: Icon(Icons.chat_bubble_outline, color: BentoTheme.accentChat),
                title: Text(
                  'Copiloto',
                  style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() => _currentIndex = 4);
                },
              ),

              // Buscar actualizaciones
              ListTile(
                leading: Icon(Icons.system_update_outlined, color: BentoTheme.accentLime),
                title: Text(
                  'Buscar actualizaciones',
                  style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
                ),
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
                  
                  await Supabase.instance.client.auth.signOut();
                  
                  ref.invalidate(vaultProvider);
                  ref.invalidate(vaultsProvider);
                  ref.invalidate(habitsProvider);
                  ref.invalidate(notesProvider);
                  
                  if (context.mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getTabColor(int index) {
    switch (index) {
      case 0:
        return BentoTheme.accentHabits;
      case 1:
        return BentoTheme.accentBrain;
      case 2:
        return BentoTheme.accentAlarm;
      case 3:
        return BentoTheme.accentFinance;
      case 4:
        return BentoTheme.accentChat;
      case 5:
        return BentoTheme.accentLime;
      default:
        return BentoTheme.accentLime;
    }
  }

  Widget _buildTabItem({
    required IconData icon,
    required int index,
  }) {
    final isSelected = _currentIndex == index;
    final activeColor = _getTabColor(index);
    return _AnimatedTabItem(
      icon: icon,
      isSelected: isSelected,
      activeColor: activeColor,
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
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
