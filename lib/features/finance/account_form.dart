import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
        backgroundColor: BentoTheme.darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: BentoTheme.creamAlpha(0.14), width: 1.5),
        ),
        title: Text('¿Eliminar cuenta?',
            style: GoogleFonts.montserrat(color: BentoTheme.cream, fontWeight: FontWeight.w700)),
        content: Text(
          'Esta acción es permanente y eliminará todas las transacciones asociadas a esta cuenta.',
          style: TextStyle(color: BentoTheme.creamAlpha(0.6)),
        ),
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

  InputDecoration _darkInputDecoration({required String label, required String hint, String? prefixText}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
      labelStyle: TextStyle(color: BentoTheme.creamAlpha(0.55)),
      hintStyle: TextStyle(color: BentoTheme.creamAlpha(0.3)),
      prefixStyle: const TextStyle(color: BentoTheme.cream),
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
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: BentoTheme.accentLime, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: BentoTheme.darkCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                  style: GoogleFonts.montserrat(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: BentoTheme.cream,
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
              style: const TextStyle(color: BentoTheme.cream, fontWeight: FontWeight.w500),
              decoration: _darkInputDecoration(label: 'Nombre', hint: 'Ej: Banco Principal'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _balanceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: BentoTheme.cream, fontWeight: FontWeight.w500),
              decoration: _darkInputDecoration(
                label: 'Saldo inicial (USD)',
                hint: '0.00',
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
                      color: selected ? type.color.withValues(alpha: 0.16) : BentoTheme.darkCardAlt,
                      border: Border.all(
                        color: selected ? type.color : BentoTheme.creamAlpha(0.14),
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(type.icon, size: 18, color: selected ? type.color : BentoTheme.creamAlpha(0.55)),
                        const SizedBox(width: 6),
                        Text(
                          type.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: selected ? type.color : BentoTheme.creamAlpha(0.55),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: BentoTheme.accentLime,
                foregroundColor: const Color(0xFF0C0C0D),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0C0C0D)),
                    )
                  : Text(_isEditing ? 'Guardar Cambios' : 'Crear Cuenta'),
            ),
          ],
        ),
      ),
    );
  }
}
