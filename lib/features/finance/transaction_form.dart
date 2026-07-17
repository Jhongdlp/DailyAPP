import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/models/account_model.dart';
import '../../core/models/transaction_model.dart';
import '../../core/providers/finance_provider.dart';
import '../../core/providers/rpg_provider.dart';
import '../../core/models/achievement_catalog.dart';
import '../../core/widgets/rpg_celebration.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/utils/error_snackbar.dart';

/// Bottom sheet para registrar o editar una transacción.
Future<void> showTransactionForm(BuildContext context, {TransactionModel? transaction}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => TransactionForm(transaction: transaction),
  );
}

class TransactionForm extends ConsumerStatefulWidget {
  final TransactionModel? transaction;

  const TransactionForm({super.key, this.transaction});

  @override
  ConsumerState<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends ConsumerState<TransactionForm> {
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
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
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
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

      final notifier = ref.read(transactionsProvider.notifier);
      if (_isEditing) {
        await notifier.updateTransaction(tx);
      } else {
        await notifier.addTransaction(tx);
        // Recompensa por constancia financiera
        final result = ref.read(rpgProvider.notifier).gainXpAndGold(
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

  InputDecoration _darkInputDecoration({required String label, String? hint, String? prefixText}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
      labelStyle: TextStyle(color: BentoTheme.creamAlpha(0.55)),
      hintStyle: TextStyle(color: BentoTheme.creamAlpha(0.3)),
      prefixStyle: TextStyle(color: BentoTheme.cream),
      filled: true,
      fillColor: BentoTheme.darkCardAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: BentoTheme.creamAlpha(0.14)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: BentoTheme.creamAlpha(0.14)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: BentoTheme.accentFinance, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).value ?? [];

    // Selección por defecto de cuenta al abrir
    if (_accountId == null && accounts.isNotEmpty) {
      _accountId = accounts.first.id;
    }

    final categories = FinanceCategories.forType(_type);
    if (!categories.any((c) => c.id == _category)) {
      _category = 'other';
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: BentoTheme.darkCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing ? 'Editar Movimiento' : 'Nuevo Movimiento',
                style: GoogleFonts.montserrat(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: BentoTheme.cream,
                ),
              ),
              const SizedBox(height: 20),

              // Selector de tipo
              Row(
                children: TransactionType.values.map((type) {
                  final selected = _type == type;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _type = type),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: selected ? type.color.withValues(alpha: 0.16) : BentoTheme.darkCardAlt,
                          border: Border.all(
                            color: selected ? type.color : BentoTheme.creamAlpha(0.14),
                            width: 2,
                          ),
                        ),
                        child: Text(
                          type.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: selected ? type.color : BentoTheme.creamAlpha(0.55),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Monto
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: !_isEditing,
                style: TextStyle(
                  color: BentoTheme.cream,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                ),
                decoration: _darkInputDecoration(label: 'Monto (USD)', hint: '0.00', prefixText: '\$ '),
              ),
              const SizedBox(height: 16),

              // Cuenta (origen)
              DropdownButtonFormField<String>(
                initialValue: _accountId,
                dropdownColor: BentoTheme.darkCardAlt,
                style: TextStyle(color: BentoTheme.cream),
                iconEnabledColor: BentoTheme.creamAlpha(0.55),
                decoration: _darkInputDecoration(
                  label: _type == TransactionType.transfer ? 'Desde la cuenta' : 'Cuenta',
                ),
                items: accounts
                    .map((a) => DropdownMenuItem(
                          value: a.id,
                          child: Row(
                            children: [
                              Icon(a.type.icon, size: 18, color: a.type.color),
                              const SizedBox(width: 8),
                              Text(a.name, style: TextStyle(fontWeight: FontWeight.w600, color: BentoTheme.cream)),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _accountId = v),
              ),

              // Cuenta destino (solo transferencias)
              if (_type == TransactionType.transfer) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _transferAccountId,
                  dropdownColor: BentoTheme.darkCardAlt,
                  style: TextStyle(color: BentoTheme.cream),
                  iconEnabledColor: BentoTheme.creamAlpha(0.55),
                  decoration: _darkInputDecoration(label: 'Hacia la cuenta'),
                  items: accounts
                      .where((a) => a.id != _accountId)
                      .map((a) => DropdownMenuItem(
                            value: a.id,
                            child: Row(
                              children: [
                                Icon(a.type.icon, size: 18, color: a.type.color),
                                const SizedBox(width: 8),
                                Text(a.name, style: TextStyle(fontWeight: FontWeight.w600, color: BentoTheme.cream)),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _transferAccountId = v),
                ),
              ],

              // Categorías (no aplica a transferencias)
              if (_type != TransactionType.transfer) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: categories.map((cat) {
                    final selected = _category == cat.id;
                    return GestureDetector(
                      onTap: () => setState(() => _category = cat.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: selected ? cat.color.withValues(alpha: 0.16) : BentoTheme.darkCardAlt,
                          border: Border.all(
                            color: selected ? cat.color : BentoTheme.creamAlpha(0.14),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(cat.icon, size: 16, color: selected ? cat.color : BentoTheme.creamAlpha(0.55)),
                            const SizedBox(width: 4),
                            Text(
                              cat.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: selected ? cat.color : BentoTheme.creamAlpha(0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 16),

              // Descripción
              TextField(
                controller: _descriptionController,
                style: TextStyle(color: BentoTheme.cream, fontWeight: FontWeight.w500),
                decoration: _darkInputDecoration(label: 'Descripción (opcional)', hint: 'Ej: Almuerzo con el equipo'),
              ),
              const SizedBox(height: 16),

              // Fecha
              OutlinedButton.icon(
                onPressed: _pickDate,
                style: OutlinedButton.styleFrom(
                  foregroundColor: BentoTheme.cream,
                  side: BorderSide(color: BentoTheme.creamAlpha(0.2), width: 2),
                ),
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(DateFormat('EEE d MMM, yyyy', 'es').format(_date)),
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _saving || accounts.isEmpty ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: BentoTheme.accentFinance,
                  foregroundColor: const Color(0xFF0C0C0D),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0C0C0D)),
                      )
                    : Text(_isEditing ? 'Guardar Cambios' : 'Registrar'),
              ),
              if (accounts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Primero crea una cuenta para registrar movimientos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: BentoTheme.creamAlpha(0.55), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
