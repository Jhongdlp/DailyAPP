import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/models/account_model.dart';
import '../../core/models/transaction_model.dart';
import '../../core/providers/finance_provider.dart';
import '../../core/theme/bento_theme.dart';
import '../habits/widgets/habit_blob_header.dart';
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

  Widget _buildHeaderIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: BentoTheme.creamAlpha(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: BentoTheme.creamAlpha(0.14)),
          ),
          child: Icon(icon, size: 17, color: onPressed == null ? BentoTheme.creamAlpha(0.3) : BentoTheme.cream),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SizedBox(
      height: 92,
      child: Stack(
        children: [
          const Positioned.fill(child: HabitBlobHeader(accentColor: BentoTheme.successGreen)),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Dinero',
                  style: GoogleFonts.montserrat(
                    fontWeight: FontWeight.w800,
                    fontSize: 42,
                    height: 0.92,
                    letterSpacing: -1.4,
                    color: BentoTheme.cream,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _buildHeaderIconButton(
                    icon: Icons.add_card_outlined,
                    tooltip: 'Nueva cuenta',
                    onPressed: () => showAccountForm(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [BentoTheme.darkBgTop, BentoTheme.darkBg],
          stops: [0.0, 0.6],
        ),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              Expanded(
                child: RefreshIndicator(
                  color: BentoTheme.accentLime,
                  backgroundColor: BentoTheme.darkCard,
                  onRefresh: () async {
                    ref.invalidate(accountsProvider);
                    ref.invalidate(transactionsProvider);
                  },
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    children: [
                      const SizedBox(height: 4),

                      // Tarjeta de saldo total + resumen del mes
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: BentoTheme.darkCard,
                          border: Border.all(color: BentoTheme.creamAlpha(0.08)),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Saldo Total',
                              style: GoogleFonts.montserrat(
                                fontSize: 11,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w600,
                                color: BentoTheme.creamAlpha(0.5),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              usdFormat.format(totalBalance),
                              style: GoogleFonts.montserrat(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.7,
                                color: BentoTheme.cream,
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
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.info_outline_rounded, size: 12, color: BentoTheme.creamAlpha(0.45)),
                              const SizedBox(width: 4),
                              Text(
                                'Toca una cuenta para filtrar · Mantén presionado para editar',
                                style: GoogleFonts.montserrat(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: BentoTheme.creamAlpha(0.45),
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
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: BentoTheme.cream,
                            ),
                          ),
                          IconButton(
                            icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded,
                                color: BentoTheme.creamAlpha(0.7)),
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
                          style: const TextStyle(color: BentoTheme.cream),
                          onChanged: (val) => setState(() => _searchQuery = val),
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.search_rounded, color: BentoTheme.creamAlpha(0.5)),
                            hintText: 'Buscar por descripción o categoría...',
                            hintStyle: TextStyle(color: BentoTheme.creamAlpha(0.3)),
                            filled: true,
                            fillColor: BentoTheme.darkCardAlt,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: BentoTheme.creamAlpha(0.14)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: BentoTheme.creamAlpha(0.14)),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(16)),
                              borderSide: BorderSide(color: BentoTheme.accentLime, width: 2),
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear_rounded, color: BentoTheme.creamAlpha(0.55)),
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
                              BentoTheme.accentLime,
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
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (accountsAsync.isLoading || txsAsync.isLoading)
                        const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(
                            child: CircularProgressIndicator(color: BentoTheme.accentLime),
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
                        Padding(
                          padding: const EdgeInsets.all(40),
                          child: Center(
                            child: Text(
                              'No se encontraron movimientos con los filtros aplicados.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.montserrat(
                                color: BentoTheme.creamAlpha(0.55),
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
              ),
            ],
          ),

          // FAB para agregar movimiento
          Positioned(
            bottom: 16,
            right: 4,
            child: FloatingActionButton(
              heroTag: 'finance_fab',
              onPressed: () => showTransactionForm(context),
              backgroundColor: BentoTheme.accentLime,
              foregroundColor: const Color(0xFF0C0C0D),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String label, bool isSelected, Color activeColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? activeColor : BentoTheme.creamAlpha(0.14),
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? activeColor : BentoTheme.creamAlpha(0.55),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdown(List<MapEntry<String, double>> sortedCategories, double totalExpenses) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BentoTheme.darkCard,
        border: Border.all(color: BentoTheme.creamAlpha(0.1)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_outline_rounded, size: 16, color: BentoTheme.accentLime),
              const SizedBox(width: 6),
              Text(
                'Gastos por Categoría (Este Mes)',
                style: GoogleFonts.montserrat(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: BentoTheme.cream,
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
                            style: GoogleFonts.montserrat(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: BentoTheme.cream,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${usdFormat.format(amount)} (${(pct * 100).toStringAsFixed(0)}%)',
                        style: GoogleFonts.montserrat(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: BentoTheme.creamAlpha(0.55),
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
                      backgroundColor: BentoTheme.creamAlpha(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(cat.color),
                    ),
                  ),
                ],
              ),
            );
          }),
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
            style: GoogleFonts.montserrat(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: BentoTheme.creamAlpha(0.55),
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
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
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
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: BentoTheme.darkCardAlt,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? account.type.color : BentoTheme.creamAlpha(0.1),
              width: isSelected ? 2 : 1.5,
            ),
          ),
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
                      style: GoogleFonts.montserrat(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: BentoTheme.cream,
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
                      style: GoogleFonts.montserrat(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: balance < 0 ? BentoTheme.errorRed : BentoTheme.cream,
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

    return GestureDetector(
      onTap: () => showTransactionForm(context, transaction: tx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: BentoTheme.darkCardAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: BentoTheme.creamAlpha(0.07)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
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
                    style: GoogleFonts.montserrat(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: BentoTheme.cream,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.montserrat(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: BentoTheme.creamAlpha(0.5),
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
                    backgroundColor: BentoTheme.darkCard,
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: BentoTheme.creamAlpha(0.14), width: 1.5),
                    ),
                    title: Text('¿Eliminar movimiento?',
                        style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w700)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: TextButton.styleFrom(foregroundColor: BentoTheme.creamAlpha(0.7)),
                        child: const Text('Cancelar'),
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
              child: Icon(Icons.close_rounded, size: 18, color: BentoTheme.creamAlpha(0.5)),
            ),
          ],
        ),
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
          Icon(icon, size: 48, color: BentoTheme.creamAlpha(0.3)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              color: BentoTheme.creamAlpha(0.55),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              foregroundColor: BentoTheme.accentLime,
              side: const BorderSide(color: BentoTheme.accentLime, width: 2),
            ),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}
