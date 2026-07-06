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
import '../setup/setup_screen.dart';
import '../auth/auth_screen.dart';

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
      child: Stack(
        children: [
          // Pantalla principal del Tab Actual — fondo claro de respaldo para las
          // pestañas aún no rediseñadas (Notas, Alarma, Dinero, Copiloto); Hábitos
          // pinta su propio fondo oscuro de borde a borde encima de este.
          Positioned.fill(
            top: 12,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 95.0), // Espacio para el navbar flotante
              child: Container(
                color: BentoTheme.bgLight,
                child: IndexedStack(
                  index: _currentIndex,
                  children: _tabs,
                ),
              ),
            ),
          ),

          // Barra de Navegación Flotante — chrome oscuro/lima del rediseño
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: BentoTheme.darkCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: BentoTheme.creamAlpha(0.1)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Expanded(child: _buildTabItem(icon: Icons.check_circle_outline, index: 0, label: 'Hábitos')),
                  Expanded(child: _buildTabItem(icon: Icons.psychology_outlined, index: 1, label: 'Cerebro')),
                  Expanded(child: _buildTabItem(icon: Icons.alarm_outlined, index: 2, label: 'Alarma')),
                  Expanded(child: _buildTabItem(icon: Icons.account_balance_wallet_outlined, index: 3, label: 'Dinero')),
                  Expanded(child: _buildTabItem(icon: Icons.chat_bubble_outline, index: 4, label: 'Copiloto')),
                  Expanded(child: _buildConfigItem()),
                ],
              ),
            ),
          ),
        ],
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
                leading: Icon(Icons.settings_outlined, color: BentoTheme.creamAlpha(0.85)),
                title: Text(
                  'Ajustes',
                  style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SetupScreen()),
                  );
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
                  await Supabase.instance.client.auth.signOut();
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
    required String label,
  }) {
    final isSelected = _currentIndex == index;
    const activeColor = BentoTheme.accentLime;

    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(horizontal: isSelected ? 10 : 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isSelected ? activeColor.withValues(alpha: 0.12) : Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? activeColor : BentoTheme.creamAlpha(0.42),
              size: 22,
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.montserrat(
                    color: activeColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
