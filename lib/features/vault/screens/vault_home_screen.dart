import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/providers/vault_provider.dart';
import '../models/vault_item.dart';
import 'vault_entry_screen.dart';

class VaultHomeScreen extends ConsumerStatefulWidget {
  const VaultHomeScreen({super.key});

  @override
  ConsumerState<VaultHomeScreen> createState() => _VaultHomeScreenState();
}

class _VaultHomeScreenState extends ConsumerState<VaultHomeScreen> {
  String _searchQuery = '';
  String _selectedCategory = 'all'; // 'all', 'password', 'card', 'note', 'other'

  final Map<String, ({String label, IconData icon, Color color})> _categories = {
    'all': (label: 'Todos', icon: Icons.grid_view_outlined, color: BentoTheme.primaryDark),
    'password': (label: 'Contraseñas', icon: Icons.vpn_key_outlined, color: BentoTheme.accentOrange),
    'card': (label: 'Tarjetas', icon: Icons.credit_card_outlined, color: BentoTheme.accentPurple),
    'note': (label: 'Notas Seguras', icon: Icons.lock_outline, color: BentoTheme.accentBlue),
    'other': (label: 'Otros', icon: Icons.more_horiz_outlined, color: BentoTheme.textSecondary),
  };

  void _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copiado. Se borrará del portapapeles en 30 segundos.'),
        backgroundColor: BentoTheme.primaryDark,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    // Auto limpieza del portapapeles tras 30 segundos
    Future.delayed(const Duration(seconds: 30), () async {
      try {
        final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
        if (clipboardData?.text == text) {
          await Clipboard.setData(const ClipboardData(text: ''));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Portapapeles limpiado por seguridad ($label).'),
                backgroundColor: BentoTheme.textSecondary,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        }
      } catch (_) {}
    });
  }

  void _lockVault() {
    ref.read(vaultProvider.notifier).lock();
    Navigator.of(context).pop();
  }

  void _confirmDelete(VaultItem item, String decryptedTitle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Eliminar Elemento?'),
        content: Text('¿Estás seguro de que deseas eliminar "$decryptedTitle" de tu bóveda segura? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: BentoTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: BentoTheme.errorRed, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final success = await ref.read(vaultProvider.notifier).deleteVaultItem(item.id);
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Elemento eliminado correctamente.'), behavior: SnackBarBehavior.floating),
                );
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(vaultProvider);
    final vaultKey = vaultState.vaultKey;

    if (!vaultState.isUnlocked || vaultKey == null) {
      // Si por alguna razón se bloquea la bóveda (ej. vuelve de bg) volvemos a la pantalla de lock
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pop();
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Filtrar y descifrar elementos para la búsqueda
    final filteredItems = vaultState.items.where((item) {
      final decryptedTitle = item.getDecryptedTitle(vaultKey).toLowerCase();
      final matchesSearch = decryptedTitle.contains(_searchQuery.toLowerCase());
      
      final matchesCategory = _selectedCategory == 'all' || item.category == _selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();

    return PopScope(
      onPopInvoked: (_) {
        // Bloquear al salir de la pantalla
        ref.read(vaultProvider.notifier).lock();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Bóveda Segura',
            style: TextStyle(fontWeight: FontWeight.bold, color: BentoTheme.primaryDark),
          ),
          actions: [
            // Botón de Bloquear Bóveda
            IconButton(
              icon: const Icon(Icons.lock_open, color: BentoTheme.primaryDark),
              tooltip: 'Bloquear Bóveda',
              onPressed: _lockVault,
            ),
          ],
          elevation: 0,
          backgroundColor: BentoTheme.bgLight,
        ),
        backgroundColor: BentoTheme.bgLight,
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: BentoTheme.primaryDark,
          foregroundColor: Colors.white,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const VaultEntryScreen()),
            );
          },
          icon: const Icon(Icons.add),
          label: const Text('Agregar'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Buscador Bento
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Buscar en la bóveda...',
                    prefixIcon: const Icon(Icons.search, color: BentoTheme.textSecondary),
                    filled: true,
                    fillColor: BentoTheme.cardBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: BentoTheme.borderMuted, width: 2),
                    ),
                  ),
                ),
              ),

              // Chips de Categoría
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: _categories.entries.map((entry) {
                    final isSelected = _selectedCategory == entry.key;
                    final categoryInfo = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: FilterChip(
                        selected: isSelected,
                        label: Text(categoryInfo.label),
                        avatar: Icon(
                          categoryInfo.icon,
                          color: isSelected ? Colors.white : categoryInfo.color,
                          size: 16,
                        ),
                        selectedColor: BentoTheme.primaryDark,
                        checkmarkColor: Colors.white,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : BentoTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                        backgroundColor: BentoTheme.cardBg,
                        side: const BorderSide(color: BentoTheme.borderMuted, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onSelected: (selected) {
                          setState(() {
                            _selectedCategory = entry.key;
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 8),

              // Lista de registros
              Expanded(
                child: filteredItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_open_outlined, size: 64, color: BentoTheme.textSecondary.withOpacity(0.5)),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty ? 'Bóveda vacía' : 'Sin coincidencias',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: BentoTheme.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        itemCount: filteredItems.length,
                        itemBuilder: (ctx, index) {
                          final item = filteredItems[index];
                          final decryptedTitle = item.getDecryptedTitle(vaultKey);
                          final decryptedDesc = item.getDecryptedDescription(vaultKey);
                          final payload = item.getDecryptedPayload(vaultKey);
                          final catInfo = _categories[item.category] ?? _categories['other']!;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: BentoCard(
                              padding: const EdgeInsets.all(16),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => VaultEntryScreen(item: item),
                                  ),
                                );
                              },
                              child: Row(
                                children: [
                                  // Icono categoría
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: catInfo.color.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: catInfo.color.withOpacity(0.3), width: 1.5),
                                    ),
                                    child: Icon(catInfo.icon, color: catInfo.color),
                                  ),
                                  const SizedBox(width: 16),
                                  // Título e info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          decryptedTitle,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: BentoTheme.textPrimary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (decryptedDesc != null && decryptedDesc.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            decryptedDesc,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: BentoTheme.textSecondary,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                        if (payload.containsKey('username')) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Usuario: ${payload['username']}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: BentoTheme.textSecondary.withOpacity(0.8),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Acciones rápidas (ej. copiar contraseña)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (payload.containsKey('password')) ...[
                                        IconButton(
                                          icon: const Icon(Icons.copy_outlined, size: 20),
                                          color: BentoTheme.primaryDark,
                                          tooltip: 'Copiar Contraseña',
                                          onPressed: () => _copyToClipboard(payload['password']!, 'Contraseña'),
                                        ),
                                      ] else if (payload.containsKey('note_text')) ...[
                                        IconButton(
                                          icon: const Icon(Icons.copy_outlined, size: 20),
                                          color: BentoTheme.primaryDark,
                                          tooltip: 'Copiar Nota',
                                          onPressed: () => _copyToClipboard(payload['note_text']!, 'Nota'),
                                        ),
                                      ],
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 20),
                                        color: BentoTheme.errorRed,
                                        tooltip: 'Eliminar',
                                        onPressed: () => _confirmDelete(item, decryptedTitle),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
