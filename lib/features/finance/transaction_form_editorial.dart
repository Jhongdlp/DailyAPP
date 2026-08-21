import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/models/account_model.dart';
import '../../core/models/transaction_model.dart';
import '../../core/providers/finance_provider.dart';
import '../../core/providers/rpg_provider.dart';
import '../../core/models/achievement_catalog.dart';
import '../../core/widgets/rpg_celebration.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/widgets/editorial_kit.dart';
import '../../core/utils/error_snackbar.dart';
import '../../core/services/quick_capture_parser.dart';

/// Bottom sheet para registrar o editar una transacción en el sistema editorial.
Future<void> showTransactionFormEditorial(BuildContext context, WidgetRef ref, {TransactionModel? transaction}) {
  return showEditorialSheet<void>(
    context: context,
    title: transaction == null ? 'Nuevo Movimiento' : 'Editar Movimiento',
    maxHeightFactor: 0.92,
    builder: (sheetContext, _) => TransactionFormEditorial(ref: ref, transaction: transaction),
  );
}

class TransactionFormEditorial extends StatefulWidget {
  final WidgetRef ref;
  final TransactionModel? transaction;

  const TransactionFormEditorial({super.key, required this.ref, this.transaction});

  @override
  State<TransactionFormEditorial> createState() => _TransactionFormEditorialState();
}

class _TransactionFormEditorialState extends State<TransactionFormEditorial> {
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _aiInputController;
  late TransactionType _type;
  late String _category;
  String? _accountId;
  String? _transferAccountId;
  late DateTime _date;
  bool _saving = false;

  bool get _isEditing => widget.transaction != null;

  @override
  void initState() {
    super.initState();
    final tx = widget.transaction;
    _amountController = TextEditingController(
      text: tx != null ? tx.amount.toStringAsFixed(2) : '',
    );
    _descriptionController = TextEditingController(text: tx?.description ?? '');
    _aiInputController = TextEditingController();
    _type = tx?.type ?? TransactionType.expense;
    _category = tx?.category ?? 'other';
    _accountId = tx?.accountId;
    _transferAccountId = tx?.transferAccountId;
    _date = tx?.occurredAt ?? DateTime.now();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _aiInputController.dispose();
    super.dispose();
  }

  void _parseAIInput() {
    final text = _aiInputController.text.trim();
    if (text.isEmpty) return;

    final draft = QuickCaptureParser.parse(text);
    setState(() {
      if (draft.amount != null) {
        _amountController.text = draft.amount!.toStringAsFixed(2);
      }
      if (draft.title.isNotEmpty && draft.title != 'Sin descripción') {
        _descriptionController.text = draft.title;
      }
      if (draft.kind == CaptureKind.expense) {
        _type = TransactionType.expense;
      } else if (draft.kind == CaptureKind.income) {
        _type = TransactionType.income;
      }
      if (draft.categoryId != null) {
        _category = draft.categoryId!;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: EditorialTheme.ink,
            onPrimary: EditorialTheme.paper,
            surface: EditorialTheme.paper,
            onSurface: EditorialTheme.ink,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _selectAccount(BuildContext context, {required bool isSource}) async {
    final accounts = widget.ref.read(accountsProvider).value ?? [];
    if (accounts.isEmpty) return;

    await showEditorialSheet<void>(
      context: context,
      title: isSource ? 'Seleccionar cuenta' : 'Seleccionar cuenta destino',
      builder: (sheetContext, setSheetState) {
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          children: accounts
              .where((a) => isSource ? true : a.id != _accountId)
              .map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: EditorialRow(
                      icon: a.type.icon,
                      label: a.name,
                      active: isSource ? _accountId == a.id : _transferAccountId == a.id,
                      accent: a.type.color,
                      onTap: () {
                        setState(() {
                          if (isSource) {
                            _accountId = a.id;
                            if (_transferAccountId == _accountId) {
                              _transferAccountId = null;
                            }
                          } else {
                            _transferAccountId = a.id;
                          }
                        });
                        Navigator.pop(sheetContext);
                      },
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    if (amount == null || amount <= 0 || _accountId == null) return;
    if (_type == TransactionType.transfer &&
        (_transferAccountId == null || _transferAccountId == _accountId)) {
      return;
    }

    setState(() => _saving = true);
    try {
      final tx = TransactionModel(
        id: widget.transaction?.id ?? '',
        userId: '',
        accountId: _accountId!,
        transferAccountId: _type == TransactionType.transfer ? _transferAccountId : null,
        type: _type,
        amount: amount,
        category: _type == TransactionType.transfer ? 'other' : _category,
        description: _descriptionController.text.trim(),
        occurredAt: _date,
        createdAt: widget.transaction?.createdAt ?? DateTime.now(),
      );

      final notifier = widget.ref.read(transactionsProvider.notifier);
      if (_isEditing) {
        await notifier.updateTransaction(tx);
      } else {
        await notifier.addTransaction(tx);
        final result = widget.ref.read(rpgProvider.notifier).gainXpAndGold(
          5,
          2,
          counterKeys: const [RpgCounters.transactions],
        );
        if (mounted) {
          RpgCelebration.show(
            context,
            xp: result['xpGained'] as int,
            gold: result['goldGained'] as int,
            levelUp: result['levelUp'] as bool,
            newLevel: result['newLevel'] as int?,
          );
          AchievementToast.show(context, result['unlocked']);
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showErrorSnackBar(context, message: 'Error al guardar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = widget.ref.watch(accountsProvider).value ?? [];

    if (_accountId == null && accounts.isNotEmpty) {
      _accountId = accounts.first.id;
    }

    final categories = FinanceCategories.forType(_type);
    if (!categories.any((c) => c.id == _category)) {
      _category = 'other';
    }

    final selectedAccountName = accounts.firstWhere((a) => a.id == _accountId, orElse: () => accounts.first).name;
    final selectedAccountIcon = accounts.firstWhere((a) => a.id == _accountId, orElse: () => accounts.first).type.icon;

    final selectedDestAccountName = _transferAccountId != null
        ? accounts.firstWhere((a) => a.id == _transferAccountId, orElse: () => accounts.first).name
        : 'Seleccionar cuenta destino';
    final selectedDestAccountIcon = _transferAccountId != null
        ? accounts.firstWhere((a) => a.id == _transferAccountId, orElse: () => accounts.first).type.icon
        : Icons.account_balance_wallet_outlined;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              // Selector de tipo
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TransactionType.values.map((type) {
                  return EditorialChoice(
                    label: type.label,
                    selected: _type == type,
                    accent: type.color,
                    onTap: () => setState(() {
                      _type = type;
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Entrada Rápida IA
              if (!_isEditing) ...[
                const EditorialSectionLabel('Entrada Asistida (Escribe con tus palabras)'),
                const SizedBox(height: 12),
                EditorialField(
                  controller: _aiInputController,
                  hint: 'Ej: 15 almuerzo, recibi 300 freelance...',
                  suffix: EditorialPressable(
                    onTap: _parseAIInput,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: EditorialTheme.ink,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Aplicar',
                        style: EditorialTheme.text(12, color: EditorialTheme.paper, weight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Monto
              const EditorialSectionLabel('Monto (USD)'),
              const SizedBox(height: 12),
              EditorialField(
                controller: _amountController,
                hint: '0.00',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                prefix: Text(
                  '\$ ',
                  style: EditorialTheme.text(15, color: EditorialTheme.ink),
                ),
              ),
              const SizedBox(height: 24),

              // Cuentas
              EditorialSectionLabel(_type == TransactionType.transfer ? 'Desde la cuenta' : 'Cuenta'),
              const SizedBox(height: 12),
              EditorialRow(
                icon: selectedAccountIcon,
                label: selectedAccountName,
                onTap: () => _selectAccount(context, isSource: true),
              ),
              if (_type == TransactionType.transfer) ...[
                const SizedBox(height: 24),
                const EditorialSectionLabel('Hacia la cuenta'),
                const SizedBox(height: 12),
                EditorialRow(
                  icon: selectedDestAccountIcon,
                  label: selectedDestAccountName,
                  active: _transferAccountId != null,
                  onTap: () => _selectAccount(context, isSource: false),
                ),
              ],
              const SizedBox(height: 24),

              // Categorías
              if (_type != TransactionType.transfer) ...[
                const EditorialSectionLabel('Categoría'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: categories.map((cat) {
                    return EditorialChoice(
                      label: cat.label,
                      icon: cat.icon,
                      selected: _category == cat.id,
                      accent: cat.color,
                      onTap: () => setState(() => _category = cat.id),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ],

              // Descripción
              const EditorialSectionLabel('Descripción (opcional)'),
              const SizedBox(height: 12),
              EditorialField(
                controller: _descriptionController,
                hint: 'Ej: Almuerzo con el equipo',
              ),
              const SizedBox(height: 24),

              // Fecha
              const EditorialSectionLabel('Fecha del movimiento'),
              const SizedBox(height: 12),
              EditorialRow(
                icon: Icons.calendar_today_outlined,
                label: DateFormat('EEEE d MMMM, yyyy', 'es').format(_date),
                onTap: _pickDate,
              ),
            ],
          ),
        ),
        const EditorialRule(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: EditorialButton(
            label: _isEditing ? 'Guardar Cambios' : 'Registrar',
            onTap: _saving || accounts.isEmpty ? null : _save,
          ),
        ),
        if (accounts.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              'Primero crea una cuenta para registrar movimientos.',
              textAlign: TextAlign.center,
              style: EditorialTheme.text(12, color: EditorialTheme.muted, weight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}
