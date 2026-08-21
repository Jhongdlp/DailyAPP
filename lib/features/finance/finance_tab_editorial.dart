import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/account_model.dart';
import '../../core/models/transaction_model.dart';
import '../../core/providers/finance_provider.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/widgets/editorial_kit.dart';
import 'account_form_editorial.dart';
import 'transaction_form_editorial.dart';
import 'finance_tab.dart' show AnimatedBalanceText;

class FinanceTabEditorial extends ConsumerStatefulWidget {
  const FinanceTabEditorial({super.key});

  @override
  ConsumerState<FinanceTabEditorial> createState() => _FinanceTabEditorialState();
}

class _FinanceTabEditorialState extends ConsumerState<FinanceTabEditorial> {
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

  Widget _buildHeader(BuildContext context, int accountCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EditorialTheme.margin,
        10,
        EditorialTheme.margin,
        18,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'FINANZAS',
                  style: EditorialTheme.caps(
                    34,
                    color: EditorialTheme.paper,
                    letterSpacing: -1.0,
                    height: 0.94,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  accountCount == 1 ? '1 CUENTA REGISTRADA' : '$accountCount CUENTAS REGISTRADAS',
                  style: EditorialTheme.label(10.5, color: EditorialTheme.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          EditorialCircleButton(
            icon: Icons.add_card_outlined,
            tooltip: 'Nueva cuenta',
            onTap: () => showAccountFormEditorial(context, ref),
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

    return ColoredBox(
      color: EditorialTheme.canvas,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context, accounts.length),
                  Expanded(
                    child: RefreshIndicator(
                      color: EditorialTheme.ink,
                      backgroundColor: EditorialTheme.paper,
                      onRefresh: () async {
                        ref.invalidate(accountsProvider);
                        ref.invalidate(transactionsProvider);
                      },
                      child: ListView(
                        padding: const EdgeInsets.only(
                          left: EditorialTheme.margin,
                          right: EditorialTheme.margin,
                          top: 0,
                          bottom: 160,
                        ),
                        children: [
                          const SizedBox(height: 4),

                          // Tarjeta de saldo total + resumen del mes
                          Container(
                            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                            decoration: BoxDecoration(
                              color: EditorialTheme.paper,
                              borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SALDO TOTAL',
                                  style: EditorialTheme.label(10.5, color: EditorialTheme.grayText),
                                ),
                                const SizedBox(height: 6),
                                AnimatedBalanceText(
                                  balance: totalBalance,
                                  formatter: usdFormat,
                                  style: EditorialTheme.caps(
                                    34,
                                    weight: FontWeight.w700,
                                    color: EditorialTheme.ink,
                                    letterSpacing: -0.7,
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Container(height: 1, color: EditorialTheme.grayStrong),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    _monthStatEditorial(
                                      label: 'Entró este mes',
                                      amount: summary.income,
                                      color: BentoTheme.successGreen,
                                      icon: Icons.arrow_downward_rounded,
                                    ),
                                    _monthStatDivider(),
                                    _monthStatEditorial(
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
                                  return _accountCard(
                                    account,
                                    balance,
                                    isSelected,
                                    isDimmed,
                                  );
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.info_outline_rounded, size: 12, color: EditorialTheme.muted),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Toca para filtrar · Mantén presionado para editar',
                                    style: EditorialTheme.text(
                                      10,
                                      weight: FontWeight.w600,
                                      color: EditorialTheme.muted,
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
                                (_selectedAccountId == null
                                        ? 'Movimientos'
                                        : 'Movimientos (${accounts.firstWhere((a) => a.id == _selectedAccountId, orElse: () => accounts.first).name})')
                                    .toUpperCase(),
                                style: EditorialTheme.label(12, color: EditorialTheme.muted),
                              ),
                              EditorialCircleButton(
                                icon: _isSearching ? Icons.close_rounded : Icons.search_rounded,
                                tooltip: 'Buscar movimientos',
                                size: 34,
                                onTap: () {
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
                            EditorialField(
                              controller: _searchController,
                              hint: 'Buscar por descripción o categoría...',
                              onChanged: (val) => setState(() => _searchQuery = val),
                              suffix: _searchQuery.isNotEmpty
                                  ? EditorialPressable(
                                      onTap: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                      child: const Icon(Icons.clear_rounded, color: EditorialTheme.grayText, size: 18),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Chips de filtro por tipo
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                EditorialChoice(
                                  label: 'Todos',
                                  selected: _selectedType == null,
                                  onTap: () => setState(() => _selectedType = null),
                                ),
                                const SizedBox(width: 8),
                                ...TransactionType.values.map((type) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: EditorialChoice(
                                      label: type.label,
                                      selected: _selectedType == type,
                                      accent: type.color,
                                      onTap: () => setState(() => _selectedType = type),
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
                                child: CircularProgressIndicator(color: EditorialTheme.paper),
                              ),
                            )
                          else if (accounts.isEmpty)
                            _EmptyStateEditorial(
                              icon: Icons.account_balance_wallet_outlined,
                              message: 'Crea tu primera cuenta para empezar\na gestionar tu dinero.',
                              buttonLabel: 'Crear Cuenta',
                              onPressed: () => showAccountFormEditorial(context, ref),
                            )
                          else if (txs.isEmpty)
                            _EmptyStateEditorial(
                              icon: Icons.receipt_long_outlined,
                              message: 'Aún no tienes movimientos.\nRegistra tu primer ingreso o gasto.',
                              buttonLabel: 'Registrar Movimiento',
                              onPressed: () => showTransactionFormEditorial(context, ref),
                            )
                          else if (filteredTxs.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(40),
                              child: Center(
                                child: Text(
                                  'No se encontraron movimientos con los filtros aplicados.',
                                  textAlign: TextAlign.center,
                                  style: EditorialTheme.text(
                                    13,
                                    color: EditorialTheme.muted,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )
                          else
                            ..._buildGroupedTransactions(context, ref, filteredTxs, accounts),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // Botón circular para agregar movimiento al estilo editorial
              Positioned(
                bottom: 100,
                right: EditorialTheme.margin,
                child: EditorialCircleButton(
                  icon: Icons.add,
                  tooltip: 'Registrar movimiento',
                  size: 54,
                  onTap: () => showTransactionFormEditorial(context, ref),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monthStatEditorial({
    required String label,
    required double amount,
    required Color color,
    required IconData icon,
  }) {
    final tone = EditorialTheme.accent(color, onDark: false);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: tone),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: EditorialTheme.label(10, color: EditorialTheme.grayText),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            usdFormat.format(amount),
            style: EditorialTheme.caps(
              18,
              weight: FontWeight.w800,
              color: tone,
              letterSpacing: -0.5,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthStatDivider() => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        color: EditorialTheme.grayStrong,
      );

  Widget _accountCard(
    AccountModel account,
    double balance,
    bool isSelected,
    bool isDimmed,
  ) {
    final accentColor = EditorialTheme.accent(account.type.color, onDark: isSelected);

    return EditorialPressable(
      onTap: () {
        setState(() {
          if (_selectedAccountId == account.id) {
            _selectedAccountId = null;
          } else {
            _selectedAccountId = account.id;
          }
        });
      },
      onLongPress: () => showAccountFormEditorial(context, ref, account: account),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isDimmed ? 0.55 : 1.0,
        child: AnimatedContainer(
          duration: EditorialTheme.motion,
          curve: EditorialTheme.curve,
          width: 160,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? EditorialTheme.paper : EditorialTheme.surface,
            borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    account.type.icon,
                    size: 18,
                    color: isSelected ? EditorialTheme.ink : accentColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      account.name,
                      overflow: TextOverflow.ellipsis,
                      style: EditorialTheme.text(
                        13.5,
                        weight: FontWeight.w700,
                        color: isSelected ? EditorialTheme.ink : EditorialTheme.paper,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: AnimatedBalanceText(
                      balance: balance,
                      formatter: usdFormat,
                      style: EditorialTheme.caps(
                        17,
                        weight: FontWeight.w800,
                        color: balance < 0
                            ? const Color(0xFFD90429)
                            : (isSelected ? EditorialTheme.ink : EditorialTheme.paper),
                      ),
                    ),
                  ),
                  if (isSelected)
                    const Icon(
                      Icons.check_circle,
                      size: 16,
                      color: EditorialTheme.ink,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdown(List<MapEntry<String, double>> sortedCategories, double totalExpenses) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EditorialTheme.paper,
        borderRadius: BorderRadius.circular(EditorialTheme.radiusPanel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart_outline_rounded, size: 16, color: EditorialTheme.ink),
              const SizedBox(width: 6),
              Text(
                'Gastos por Categoría (Este Mes)'.toUpperCase(),
                style: EditorialTheme.label(11, color: EditorialTheme.grayText),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...sortedCategories.take(3).map((entry) {
            final cat = FinanceCategories.byId(entry.key);
            final amount = entry.value;
            final pct = totalExpenses > 0 ? amount / totalExpenses : 0.0;
            final catColor = EditorialTheme.accent(cat.color, onDark: false);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(cat.icon, size: 14, color: catColor),
                          const SizedBox(width: 6),
                          Text(
                            cat.label,
                            style: EditorialTheme.text(
                              12,
                              weight: FontWeight.w700,
                              color: EditorialTheme.ink,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${usdFormat.format(amount)} (${(pct * 100).toStringAsFixed(0)}%)',
                        style: EditorialTheme.text(
                          12,
                          weight: FontWeight.w600,
                          color: EditorialTheme.grayText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 5,
                      backgroundColor: EditorialTheme.gray,
                      valueColor: AlwaysStoppedAnimation<Color>(catColor),
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
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            _friendlyDate(tx.occurredAt).toUpperCase(),
            style: EditorialTheme.label(11, color: EditorialTheme.muted),
          ),
        ));
      }
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _TransactionTileEditorial(tx: tx, accounts: accounts),
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

class _TransactionTileEditorial extends ConsumerWidget {
  final TransactionModel tx;
  final List<AccountModel> accounts;

  const _TransactionTileEditorial({required this.tx, required this.accounts});

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

    final accentColor = EditorialTheme.accent(color, onDark: false);

    return EditorialPressable(
      onTap: () => showTransactionFormEditorial(context, ref, transaction: tx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: EditorialTheme.paper,
          borderRadius: BorderRadius.circular(EditorialTheme.radiusCard),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: EditorialTheme.gray,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: accentColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: EditorialTheme.text(
                      14,
                      weight: FontWeight.w700,
                      color: EditorialTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: EditorialTheme.text(
                      11,
                      weight: FontWeight.w600,
                      color: EditorialTheme.grayText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amountText,
              style: EditorialTheme.caps(
                14,
                weight: FontWeight.w900,
                color: accentColor,
              ),
            ),
            const SizedBox(width: 8),
            EditorialPressable(
              onTap: () async {
                final confirmed = await confirmEditorial(
                  context,
                  title: '¿Eliminar movimiento?',
                  body: 'Esta acción es permanente y no se puede deshacer.',
                );
                if (confirmed == true) {
                  ref.read(transactionsProvider.notifier).deleteTransaction(tx.id);
                }
              },
              child: const Icon(Icons.close_rounded, size: 18, color: EditorialTheme.grayText),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStateEditorial extends StatelessWidget {
  final IconData icon;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  const _EmptyStateEditorial({
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
          Icon(icon, size: 48, color: EditorialTheme.muted),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: EditorialTheme.text(
              13,
              color: EditorialTheme.muted,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          EditorialButton(
            label: buttonLabel,
            ghost: true,
            onTap: onPressed,
          ),
        ],
      ),
    );
  }
}
