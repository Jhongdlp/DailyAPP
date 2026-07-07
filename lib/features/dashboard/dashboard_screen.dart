import 'dart:ui' show ImageFilter;
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
import '../auth/auth_screen.dart';
import '../../core/providers/vault_provider.dart';
import '../../core/providers/vaults_provider.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/providers/notes_provider.dart';
import '../../core/providers/finance_provider.dart';
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
    return BentoBackground(
      backgroundColor: BentoTheme.darkBg,
      child: OrganicAnimatedBackground(
        child: Stack(
          children: [
            // Pantalla principal del Tab Actual — transparente para dejar ver las auroras animadas
            Positioned.fill(
              top: 12,
              child: Container(
                color: Colors.transparent,
                child: LazyIndexedStack(
                  index: _currentIndex,
                  children: _tabs,
                ),
              ),
            ),

          // Barra de Navegación Flotante — estilo de vidrio (glassmorphic) muy iPhone
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      color: BentoTheme.darkCard.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: BentoTheme.creamAlpha(0.12), width: 1.0),
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
                ],
              ),
            ),
          ),
        ],
      ),
     ),
    );
  }

  void _showConfigSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: BentoTheme.darkCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: BentoTheme.creamAlpha(0.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline, color: BentoTheme.accentChat),
                title: Text(
                  'Copiloto',
                  style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() => _currentIndex = 4);
                },
              ),
              ListTile(
                leading: const Icon(Icons.system_update_outlined, color: BentoTheme.accentLime),
                title: Text(
                  'Buscar actualizaciones',
                  style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  UpdateChecker.check(context, silent: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout_outlined, color: BentoTheme.errorRed),
                title: Text(
                  'Cerrar sesión',
                  style: GoogleFonts.montserrat(color: BentoTheme.errorRed, fontWeight: FontWeight.w600),
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  
                  // 1. Borrar caché local del usuario para privacidad y seguridad
                  await CacheService.delete('habits');
                  await CacheService.delete('notes');
                  
                  // 2. Cerrar sesión remota
                  await Supabase.instance.client.auth.signOut();
                  
                  // 3. Resetear proveedores para borrar estado en memoria
                  ref.invalidate(vaultProvider);
                  ref.invalidate(vaultsProvider);
                  ref.invalidate(habitsProvider);
                  ref.invalidate(notesProvider);
                  ref.invalidate(accountsProvider);
                  ref.invalidate(transactionsProvider);
                  
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
      default:
        return BentoTheme.accentLime;
    }
  }

  Widget _buildConfigItem() {
    return GestureDetector(
      onTap: () => _showConfigSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Icon(
          Icons.settings_outlined,
          color: BentoTheme.creamAlpha(0.42),
          size: 22,
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required IconData icon,
    required int index,
  }) {
    final isSelected = _currentIndex == index;
    final activeColor = _getTabColor(index);

    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isSelected ? activeColor.withValues(alpha: 0.12) : Colors.transparent,
        ),
        child: Icon(
          icon,
          color: isSelected ? activeColor : BentoTheme.creamAlpha(0.42),
          size: 22,
        ),
      ),
    );
  }
}
