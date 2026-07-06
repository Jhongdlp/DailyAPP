import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/models/account_model.dart';
import '../../core/models/transaction_model.dart';
import '../../core/providers/finance_provider.dart';
import '../../core/theme/bento_theme.dart';
import 'account_form.dart';
import 'transaction_form.dart';

class FinanceTab extends ConsumerStatefulWidget {
  const FinanceTab({super.key});

  @override
  ConsumerState<FinanceTab> createState() => _FinanceTabState();
}

class _FinanceTabState extends ConsumerState<FinanceTab> {
  String? _selectedAccountId;
  TransactionType? _selectedType;
  String _searchQuery = '';
  bool _isSearching = false;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final txsAsync = ref.watch(transactionsProvider);
    final balances = ref.watch(accountBalancesProvider);
    final summary = ref.watch(monthSummaryProvider);

    final accounts = accountsAsync.value ?? [];
    final txs = txsAsync.value ?? [];
    final totalBalance = balances.values.fold<double>(0, (a, b) => a + b);

    // Filtrar transacciones según cuenta, tipo y búsqueda
    final filteredTxs = txs.where((tx) {
      if (_selectedAccountId != null &&
          tx.accountId != _selectedAccountId &&
          tx.transferAccountId != _selectedAccountId) {
        return false;
      }
      if (_selectedType != null && tx.type != _selectedType) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final descMatch = tx.description.toLowerCase().contains(query);
        final catMatch = tx.categoryInfo.label.toLowerCase().contains(query);
        if (!descMatch && !catMatch) return false;
      }
      return true;
    }).toList();

    // Calcular distribución de gastos del mes actual y del filtro actual de cuenta
    final now = DateTime.now();
    final monthExpenses = txs.where((tx) {
      if (tx.type != TransactionType.expense) return false;
      if (tx.occurredAt.year != now.year || tx.occurredAt.month != now.month) return false;
      if (_selectedAccountId != null && tx.accountId != _selectedAccountId) return false;
      return true;
    }).toList();

    final categoryTotals = <String, double>{};
    double totalMonthExpenses = 0;
    for (final tx in monthExpenses) {
      categoryTotals[tx.category] = (categoryTotals[tx.category] ?? 0) + tx.amount;
      totalMonthExpenses += tx.amount;
    }

    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Stack(
      children: [
        RefreshIndicator(
          color: BentoTheme.primaryDark,
          onRefresh: () async {
            ref.invalidate(accountsProvider);
            ref.invalidate(transactionsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '💰 Mi Dinero',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: BentoTheme.textPrimary,
                    ),
                  ),
                  IconButton(
                    onPressed: () => showAccountForm(context),
                    icon: const Icon(Icons.add_card_outlined, color: BentoTheme.primaryDark),
                    tooltip: 'Nueva cuenta',
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Tarjeta de saldo total + resumen del mes
              BentoCard(
                borderColor: BentoTheme.primaryDark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Saldo Total',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: BentoTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      usdFormat.format(totalBalance),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: BentoTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _MonthStat(
                          label: 'Entró este mes',
                          amount: summary.income,
                          color: BentoTheme.successGreen,
                          icon: Icons.arrow_downward_rounded,
                        ),
                        const SizedBox(width: 12),
                        _MonthStat(
                          label: 'Salió este mes',
                          amount: summary.expense,
                          color: BentoTheme.errorRed,
                          icon: Icons.arrow_upward_rounded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Cuentas
              if (accounts.isNotEmpty) ...[
                SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: accounts.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final account = accounts[i];
                      final balance = balances[account.id] ?? 0;
                      final isSelected = _selectedAccountId == account.id;
                      final isDimmed = _selectedAccountId != null && _selectedAccountId != account.id;
                      return _AccountCard(
                        account: account,
                        balance: balance,
                        isSelected: isSelected,
                        isDimmed: isDimmed,
                        onTap: () {
                          setState(() {
                            if (_selectedAccountId == account.id) {
                              _selectedAccountId = null;
                            } else {
                              _selectedAccountId = account.id;
                            }
                          });
                        },
                        onLongPress: () => showAccountForm(context, account: account),
                      );
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6, bottom: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 12, color: BentoTheme.textSecondary),
                      SizedBox(width: 4),
                      Text(
                        'Toca una cuenta para filtrar · Mantén presionado para editar',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: BentoTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Distribución de gastos (este mes)
              if (totalMonthExpenses > 0) ...[
                _buildCategoryBreakdown(sortedCategories, totalMonthExpenses),
                const SizedBox(height: 16),
              ],

              // Cabecera de movimientos y Búsqueda
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _selectedAccountId == null
                        ? 'Movimientos'
                        : 'Movimientos (${accounts.firstWhere((a) => a.id == _selectedAccountId, orElse: () => accounts.first).name})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: BentoTheme.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded,
                        color: BentoTheme.primaryDark),
                    onPressed: () {
                      setState(() {
                        if (_isSearching) {
                          _searchController.clear();
                          _searchQuery = '';
                        }
                        _isSearching = !_isSearching;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),

              if (_isSearching) ...[
                TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded, color: BentoTheme.textSecondary),
                    hintText: 'Buscar por descripción o categoría...',
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Chips de filtro por tipo
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTypeChip(
                      'Todos',
                      _selectedType == null,
                      BentoTheme.primaryDark,
                      () => setState(() => _selectedType = null),
                    ),
                    const SizedBox(width: 8),
                    ...TransactionType.values.map((type) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildTypeChip(
                          type.label,
                          _selectedType == type,
                          type.color,
                          () => setState(() => _selectedType = type),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (accountsAsync.isLoading || txsAsync.isLoading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: CircularProgressIndicator(color: BentoTheme.primaryDark),
                  ),
                )
              else if (accounts.isEmpty)
                _EmptyState(
                  icon: Icons.account_balance_wallet_outlined,
                  message: 'Crea tu primera cuenta para empezar\na gestionar tu dinero.',
                  buttonLabel: 'Crear Cuenta',
                  onPressed: () => showAccountForm(context),
                )
              else if (txs.isEmpty)
                _EmptyState(
                  icon: Icons.receipt_long_outlined,
                  message: 'Aún no tienes movimientos.\nRegistra tu primer ingreso o gasto.',
                  buttonLabel: 'Registrar Movimiento',
                  onPressed: () => showTransactionForm(context),
                )
              else if (filteredTxs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: Text(
                      'No se encontraron movimientos con los filtros aplicados.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: BentoTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
              else
                ..._buildGroupedTransactions(context, ref, filteredTxs, accounts),

              const SizedBox(height: 80), // espacio para el FAB
            ],
          ),
        ),

        // FAB para agregar movimiento
        Positioned(
          bottom: 16,
          right: 4,
          child: FloatingActionButton(
            heroTag: 'finance_fab',
            onPressed: () => showTransactionForm(context),
            backgroundColor: BentoTheme.primaryDark,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: BentoTheme.primaryDark, width: 2),
            ),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeChip(String label, bool isSelected, Color activeColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? activeColor : BentoTheme.borderMuted,
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? activeColor : BentoTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdown(List<MapEntry<String, double>> sortedCategories, double totalExpenses) {
    return BentoCard(
      borderColor: BentoTheme.primaryDark.withOpacity(0.3),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.pie_chart_outline_rounded, size: 16, color: BentoTheme.primaryDark),
              SizedBox(width: 6),
              Text(
                'Gastos por Categoría (Este Mes)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: BentoTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...sortedCategories.take(3).map((entry) {
            final cat = FinanceCategories.byId(entry.key);
            final amount = entry.value;
            final pct = totalExpenses > 0 ? amount / totalExpenses : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(cat.icon, size: 14, color: cat.color),
                          const SizedBox(width: 6),
                          Text(
                            cat.label,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: BentoTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${usdFormat.format(amount)} (${(pct * 100).toStringAsFixed(0)}%)',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: BentoTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 6,
                      backgroundColor: BentoTheme.borderMuted,
                      valueColor: AlwaysStoppedAnimation<Color>(cat.color),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedTransactions(
    BuildContext context,
    WidgetRef ref,
    List<TransactionModel> txs,
    List<AccountModel> accounts,
  ) {
    final widgets = <Widget>[];
    String? lastDate;

    for (final tx in txs) {
      final dateStr = DateFormat('yyyy-MM-dd').format(tx.occurredAt);
      if (dateStr != lastDate) {
        lastDate = dateStr;
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 6),
          child: Text(
            _friendlyDate(tx.occurredAt),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: BentoTheme.textSecondary,
            ),
          ),
        ));
      }
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _TransactionTile(tx: tx, accounts: accounts),
      ));
    }
    return widgets;
  }

  String _friendlyDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Hoy';
    if (d == today.subtract(const Duration(days: 1))) return 'Ayer';
    return DateFormat('d MMM yyyy').format(date);
  }
}

class _MonthStat extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const _MonthStat({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.4), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              usdFormat.format(amount),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  final AccountModel account;
  final double balance;
  final bool isSelected;
  final bool isDimmed;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _AccountCard({
    required this.account,
    required this.balance,
    required this.isSelected,
    required this.isDimmed,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isDimmed ? 0.55 : 1.0,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: BentoCard(
          width: 160,
          padding: const EdgeInsets.all(14),
          borderColor: isSelected ? account.type.color : BentoTheme.borderMuted,
          borderWidth: isSelected ? 2.5 : 1.5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(account.type.icon, size: 18, color: account.type.color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      account.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: BentoTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      usdFormat.format(balance),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: balance < 0 ? BentoTheme.errorRed : BentoTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: account.type.color,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionTile extends ConsumerWidget {
  final TransactionModel tx;
  final List<AccountModel> accounts;

  const _TransactionTile({required this.tx, required this.accounts});

  String _accountName(String? id) {
    if (id == null) return '?';
    final match = accounts.where((a) => a.id == id);
    return match.isEmpty ? '?' : match.first.name;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTransfer = tx.type == TransactionType.transfer;
    final cat = tx.categoryInfo;
    final color = tx.type.color;
    final icon = isTransfer ? Icons.swap_horiz_rounded : cat.icon;

    final title = tx.description.isNotEmpty
        ? tx.description
        : (isTransfer ? 'Transferencia' : cat.label);
    final subtitle = isTransfer
        ? '${_accountName(tx.accountId)} → ${_accountName(tx.transferAccountId)}'
        : '${cat.label} · ${_accountName(tx.accountId)}';

    final amountText = isTransfer
        ? usdFormat.format(tx.amount)
        : '${tx.type == TransactionType.income ? '+' : '−'}${usdFormat.format(tx.amount)}';

    return BentoCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => showTransactionForm(context, transaction: tx),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.4), width: 1.5),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: BentoTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: BentoTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amountText,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: BentoTheme.cardBg,
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: BentoTheme.primaryDark, width: 2),
                  ),
                  title: const Text('¿Eliminar movimiento?',
                      style: TextStyle(color: BentoTheme.textPrimary, fontWeight: FontWeight.bold)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar',
                          style: TextStyle(color: BentoTheme.textSecondary, fontWeight: FontWeight.bold)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Eliminar',
                          style: TextStyle(color: BentoTheme.errorRed, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                ref.read(transactionsProvider.notifier).deleteTransaction(tx.id);
              }
            },
            child: const Icon(Icons.close_rounded, size: 18, color: BentoTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(icon, size: 48, color: BentoTheme.textSecondary.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: BentoTheme.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onPressed, child: Text(buttonLabel)),
        ],
      ),
    );
  }
}
