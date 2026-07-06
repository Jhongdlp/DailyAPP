import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/account_model.dart';
import '../../core/providers/finance_provider.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/utils/error_snackbar.dart';

/// Bottom sheet para crear o editar una cuenta.
Future<void> showAccountForm(BuildContext context, {AccountModel? account}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AccountForm(account: account),
  );
}

class AccountForm extends ConsumerStatefulWidget {
  final AccountModel? account;

  const AccountForm({super.key, this.account});

  @override
  ConsumerState<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<AccountForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _balanceController;
  late AccountType _type;
  bool _saving = false;

  bool get _isEditing => widget.account != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.account?.name ?? '');
    _balanceController = TextEditingController(
      text: widget.account != null
          ? widget.account!.initialBalance.toStringAsFixed(2)
          : '',
    );
    _type = widget.account?.type ?? AccountType.cash;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final balance =
        double.tryParse(_balanceController.text.replaceAll(',', '.')) ?? 0;

    setState(() => _saving = true);
    try {
      final notifier = ref.read(accountsProvider.notifier);
      if (_isEditing) {
        await notifier.updateAccount(widget.account!.copyWith(
          name: name,
          type: _type,
          initialBalance: balance,
        ));
      } else {
        await notifier.addAccount(AccountModel(
          id: '',
          userId: '',
          name: name,
          type: _type,
          initialBalance: balance,
          currency: 'USD',
          createdAt: DateTime.now(),
        ));
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showErrorSnackBar(context, message: 'Error al guardar la cuenta: $e');
      }
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BentoTheme.cardBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: BentoTheme.primaryDark, width: 2),
        ),
        title: const Text('¿Eliminar cuenta?',
            style: TextStyle(color: BentoTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: const Text(
          'Esta acción es permanente y eliminará todas las transacciones asociadas a esta cuenta.',
          style: TextStyle(color: BentoTheme.textSecondary),
        ),
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
      setState(() => _saving = true);
      try {
        await ref.read(accountsProvider.notifier).deleteAccount(widget.account!.id);
        if (mounted) {
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _saving = false);
          showErrorSnackBar(context, message: 'Error al eliminar la cuenta: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: BentoTheme.cardBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: BentoTheme.primaryDark, width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isEditing ? 'Editar Cuenta' : 'Nueva Cuenta',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: BentoTheme.textPrimary,
                  ),
                ),
                if (_isEditing)
                  IconButton(
                    onPressed: () => _deleteAccount(context),
                    icon: const Icon(Icons.delete_outline_rounded, color: BentoTheme.errorRed),
                    tooltip: 'Eliminar cuenta',
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: BentoTheme.textPrimary, fontWeight: FontWeight.w500),
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Ej: Banco Principal',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _balanceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: BentoTheme.textPrimary, fontWeight: FontWeight.w500),
              decoration: const InputDecoration(
                labelText: 'Saldo inicial (USD)',
                hintText: '0.00',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AccountType.values.map((type) {
                final selected = _type == type;
                return GestureDetector(
                  onTap: () => setState(() => _type = type),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: selected ? type.color.withOpacity(0.12) : Colors.transparent,
                      border: Border.all(
                        color: selected ? type.color : BentoTheme.borderMuted,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(type.icon, size: 18, color: selected ? type.color : BentoTheme.textSecondary),
                        const SizedBox(width: 6),
                        Text(
                          type.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: selected ? type.color : BentoTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_isEditing ? 'Guardar Cambios' : 'Crear Cuenta'),
            ),
          ],
        ),
      ),
    );
  }
}
