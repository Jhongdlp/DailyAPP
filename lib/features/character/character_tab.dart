import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/providers/rpg_provider.dart';
import '../../core/providers/appearance_provider.dart';
import '../../core/services/cache_service.dart';
import '../../core/widgets/rpg_celebration.dart';
import '../settings/personalize_screen.dart';
import '../update/update_checker.dart';
import '../auth/auth_screen.dart';
import 'widgets/pixel_character.dart';
import 'widgets/hero_sprites.dart';
import 'widgets/hero_gallery.dart';
import 'widgets/cosmetic_shop.dart';
import 'widgets/achievements_panel.dart';

// Importación de providers para poder invalidar en logout
import '../../core/providers/vault_provider.dart';
import '../../core/providers/vaults_provider.dart';
import '../../core/providers/habits_provider.dart';
import '../../core/providers/notes_provider.dart';

class CharacterTab extends ConsumerStatefulWidget {
  final Function(int)? onNavigateToTab;

  const CharacterTab({
    super.key,
    this.onNavigateToTab,
  });

  @override
  ConsumerState<CharacterTab> createState() => _CharacterTabState();
}

class _CharacterTabState extends ConsumerState<CharacterTab> {
  final _rewardTitleCtrl = TextEditingController();
  final _rewardCostCtrl = TextEditingController();
  String _selectedEmoji = '🎮';

  String _getCharacterTitle(int level) {
    if (level >= 15) return 'Paladín Dorado';
    if (level >= 10) return 'Caballero de Mithril';
    if (level >= 5) return 'Guerrero de Acero';
    return 'Recluta Novato';
  }

  void _showAddRewardDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setModalState) {
            return AlertDialog(
              backgroundColor: BentoTheme.darkCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                'Crear Recompensa',
                style: GoogleFonts.montserrat(
                  fontWeight: FontWeight.bold,
                  color: BentoTheme.cream,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Emoji selection
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: ['🎮', '📺', '🍰', '🛍️', '🍺', '😴'].map((emoji) {
                      final isSelected = _selectedEmoji == emoji;
                      return GestureDetector(
                        onTap: () {
                          setModalState(() {
                            _selectedEmoji = emoji;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isSelected ? BentoTheme.accentLime.withValues(alpha: 0.18) : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? BentoTheme.accentLime : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Text(emoji, style: const TextStyle(fontSize: 24)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _rewardTitleCtrl,
                    style: TextStyle(color: BentoTheme.cream),
                    decoration: InputDecoration(
                      labelText: '¿Cuál es la recompensa?',
                      hintText: 'ej: Jugar 1 hora, ver serie...',
                      labelStyle: TextStyle(color: BentoTheme.creamSecondary),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: BentoTheme.creamAlpha(0.2))),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: BentoTheme.accentLime)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _rewardCostCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: BentoTheme.cream),
                    decoration: InputDecoration(
                      labelText: 'Costo (Oro 💰)',
                      hintText: 'ej: 50, 100...',
                      labelStyle: TextStyle(color: BentoTheme.creamSecondary),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: BentoTheme.creamAlpha(0.2))),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: BentoTheme.accentLime)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _rewardTitleCtrl.clear();
                    _rewardCostCtrl.clear();
                    Navigator.pop(ctx);
                  },
                  child: Text('Cancelar', style: TextStyle(color: BentoTheme.creamSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BentoTheme.accentLime,
                    foregroundColor: const Color(0xFF0C0C0D),
                  ),
                  onPressed: () {
                    final title = _rewardTitleCtrl.text.trim();
                    final cost = int.tryParse(_rewardCostCtrl.text.trim()) ?? 0;

                    if (title.isNotEmpty && cost > 0) {
                      ref.read(rpgProvider.notifier).addCustomReward(title, cost, _selectedEmoji);
                      _rewardTitleCtrl.clear();
                      _rewardCostCtrl.clear();
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Recompensa añadida con éxito'),
                          backgroundColor: BentoTheme.successGreen,
                        ),
                      );
                    }
                  },
                  child: const Text('Añadir'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _purchaseReward(String id, String title, int cost) {
    final success = ref.read(rpgProvider.notifier).purchaseReward(id);
    if (success) {
      RpgCelebration.show(
        context,
        xp: 0,
        gold: -cost,
        levelUp: false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No tienes suficiente oro 💰 para esta recompensa.'),
          backgroundColor: BentoTheme.errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rpgStats = ref.watch(rpgProvider);
    final hero = heroById(rpgStats.selectedHero);
    final characterTitle = _getCharacterTitle(rpgStats.level);
    final int xpNeeded = rpgStats.level * 100;
    final double xpPercentage = (rpgStats.xp / xpNeeded).clamp(0.0, 1.0);
    final double hpPercentage = (rpgStats.hp / 100.0).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
        children: [
          // ─── CABECERA DE LA PESTAÑA ───
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MI PERSONAJE',
                      style: GoogleFonts.montserrat(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: BentoTheme.cream,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      'Hoja de aventurero y configuración',
                      style: GoogleFonts.montserrat(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: BentoTheme.creamSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Indicador rápido de Oro en la barra superior
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: BentoTheme.darkCardAlt,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: BentoTheme.creamAlpha(0.12)),
                ),
                child: Row(
                  children: [
                    const Text('💰', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    Text(
                      '${rpgStats.gold}',
                      style: GoogleFonts.montserrat(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: BentoTheme.cream,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ─── CARTA DEL HÉROE (Ficha Técnica) ───
          GlassCard(
            borderRadius: 24,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Render del personaje Píxel Art
                    PixelCharacter(
                      level: rpgStats.level,
                      hp: rpgStats.hp,
                      size: 110,
                    ),
                    const SizedBox(width: 16),
                    // Estadísticas de Nivel y Rol
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: BentoTheme.accentLime.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              characterTitle.toUpperCase(),
                              style: GoogleFonts.montserrat(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: BentoTheme.accentLime,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            hero.name.toUpperCase(),
                            style: GoogleFonts.montserrat(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: BentoTheme.cream,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'Nivel ${rpgStats.level} · ${hero.className}',
                            style: GoogleFonts.montserrat(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: BentoTheme.creamSecondary,
                            ),
                          ),
                          const EquippedBadgesRow(),
                          const SizedBox(height: 10),
                          // Barra de HP
                          Row(
                            children: [
                              const Icon(Icons.favorite, color: BentoTheme.errorRed, size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LinearProgressIndicator(
                                    value: hpPercentage,
                                    minHeight: 8,
                                    backgroundColor: BentoTheme.creamAlpha(0.1),
                                    valueColor: const AlwaysStoppedAnimation(BentoTheme.errorRed),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${rpgStats.hp}/100',
                                style: GoogleFonts.montserrat(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: BentoTheme.creamSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Barra de XP
                          Row(
                            children: [
                              Icon(Icons.star, color: BentoTheme.accentLime, size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LinearProgressIndicator(
                                    value: xpPercentage,
                                    minHeight: 8,
                                    backgroundColor: BentoTheme.creamAlpha(0.1),
                                    valueColor: AlwaysStoppedAnimation(BentoTheme.accentLime),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${rpgStats.xp}/$xpNeeded',
                                style: GoogleFonts.montserrat(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: BentoTheme.creamSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ─── SALÓN DE HÉROES (elegir personaje) ───
          Text(
            'SALÓN DE HÉROES',
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: BentoTheme.creamSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          const HeroGallery(),
          const SizedBox(height: 28),

          // ─── BAZAR DE COSMÉTICOS (comprar con oro) ───
          Text(
            'BAZAR DE COSMÉTICOS',
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: BentoTheme.creamSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          const CosmeticShop(),
          const SizedBox(height: 28),

          // ─── LOGROS (badges equipables) ───
          Text(
            'LOGROS',
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: BentoTheme.creamSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Toca un logro desbloqueado para lucirlo en tu carta (máx. 3)',
            style: TextStyle(fontSize: 10, color: BentoTheme.creamTertiary),
          ),
          const SizedBox(height: 10),
          const AchievementsPanel(),
          const SizedBox(height: 28),

          // ─── TIENDA DE RECOMPENSAS (Canjear Oro) ───
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TIENDA DE RECOMPENSAS',
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: BentoTheme.creamSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                color: BentoTheme.accentLime,
                onPressed: _showAddRewardDialog,
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (rpgStats.customRewards.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No hay recompensas creadas.',
                  style: TextStyle(color: BentoTheme.creamTertiary, fontSize: 13),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.35,
              ),
              itemCount: rpgStats.customRewards.length,
              itemBuilder: (context, index) {
                final reward = rpgStats.customRewards[index];
                return NeuCard(
                  padding: const EdgeInsets.all(12),
                  borderRadius: 18,
                  onTap: () => _purchaseReward(reward.id, reward.title, reward.cost),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(reward.icon, style: const TextStyle(fontSize: 22)),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16),
                            color: BentoTheme.errorRed.withValues(alpha: 0.6),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              ref.read(rpgProvider.notifier).deleteCustomReward(reward.id);
                            },
                          ),
                        ],
                      ),
                      Text(
                        reward.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: BentoTheme.cream,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Costo: ${reward.cost} 💰',
                            style: GoogleFonts.montserrat(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: BentoTheme.accentLime,
                            ),
                          ),
                          Text(
                            'Canjeado: ${reward.timesRedeemed}',
                            style: TextStyle(
                              fontSize: 9,
                              color: BentoTheme.creamTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 28),

          // ─── OPCIONES DEL SISTEMA (Configuración consolidada) ───
          Text(
            'OPCIONES DEL SISTEMA',
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: BentoTheme.creamSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),

          // Grid de BentoCards de configuración
          Column(
            children: [
              // Fila 1: Tema Claro/Oscuro & Personalizar
              Row(
                children: [
                  // Tema
                  Expanded(
                    child: BentoCard(
                      borderRadius: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      onTap: () {
                        ref.read(appearanceProvider.notifier).toggleMode(BentoTheme.isDark);
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            BentoTheme.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                            color: BentoTheme.accentFinance,
                            size: 20,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            BentoTheme.isDark ? 'Modo Claro' : 'Modo Oscuro',
                            style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: BentoTheme.cream,
                            ),
                          ),
                          Text(
                            'Cambiar tema visual',
                            style: TextStyle(fontSize: 10, color: BentoTheme.creamTertiary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Personalizar
                  Expanded(
                    child: BentoCard(
                      borderRadius: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const PersonalizeScreen()),
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.palette_outlined, color: BentoTheme.accentPurple, size: 20),
                          const SizedBox(height: 8),
                          Text(
                            'Personalizar',
                            style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: BentoTheme.cream,
                            ),
                          ),
                          Text(
                            'Temas y paletas',
                            style: TextStyle(fontSize: 10, color: BentoTheme.creamTertiary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Fila 2: Copiloto & Actualizaciones
              Row(
                children: [
                  // Copiloto
                  Expanded(
                    child: BentoCard(
                      borderRadius: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      onTap: () {
                        if (widget.onNavigateToTab != null) {
                          widget.onNavigateToTab!(4); // Abre el Copiloto (ChatTab)
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.chat_bubble_outline, color: BentoTheme.accentChat, size: 20),
                          const SizedBox(height: 8),
                          Text(
                            'Copiloto',
                            style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: BentoTheme.cream,
                            ),
                          ),
                          Text(
                            'Chat con IA local',
                            style: TextStyle(fontSize: 10, color: BentoTheme.creamTertiary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Buscar actualizaciones
                  Expanded(
                    child: BentoCard(
                      borderRadius: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      onTap: () {
                        UpdateChecker.check(context, silent: false);
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.system_update_outlined, color: BentoTheme.accentLime, size: 20),
                          const SizedBox(height: 8),
                          Text(
                            'Buscar Actualizaciones',
                            style: GoogleFonts.montserrat(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: BentoTheme.cream,
                            ),
                          ),
                          Text(
                            'Verificar versión',
                            style: TextStyle(fontSize: 10, color: BentoTheme.creamTertiary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Botón de Cerrar Sesión (BentoCard rojo)
              BentoCard(
                borderRadius: 18,
                backgroundColor: BentoTheme.errorRed.withValues(alpha: 0.08),
                borderColor: BentoTheme.errorRed.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                onTap: () async {
                  // Confirmar
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: BentoTheme.darkCard,
                      title: Text('Cerrar Sesión', style: TextStyle(color: BentoTheme.cream)),
                      content: Text('¿Estás seguro de que quieres cerrar la sesión?', style: TextStyle(color: BentoTheme.creamSecondary)),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text('Cancelar', style: TextStyle(color: BentoTheme.creamSecondary)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Cerrar Sesión', style: TextStyle(color: BentoTheme.errorRed)),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true && mounted) {
                    // 1. Borrar caché local
                    await CacheService.delete('habits');
                    await CacheService.delete('notes');

                    // 2. Sign out
                    await Supabase.instance.client.auth.signOut();

                    // 3. Resetear providers
                    ref.invalidate(vaultProvider);
                    ref.invalidate(vaultsProvider);
                    ref.invalidate(habitsProvider);
                    ref.invalidate(notesProvider);

                    if (mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const AuthScreen()),
                      );
                    }
                  }
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.logout_outlined, color: BentoTheme.errorRed, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Cerrar sesión',
                      style: GoogleFonts.montserrat(
                        color: BentoTheme.errorRed,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
