import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/account_model.dart';
import '../../core/providers/finance_provider.dart';
import '../../core/theme/editorial_theme.dart';
import '../../core/widgets/editorial_kit.dart';
import '../../core/utils/error_snackbar.dart';

/// Bottom sheet para crear o editar una cuenta en el sistema editorial.
Future<void> showAccountFormEditorial(BuildContext context, WidgetRef ref, {AccountModel? account}) {
  return showEditorialSheet<void>(
    context: context,
    title: account == null ? 'Nueva Cuenta' : 'Editar Cuenta',
    maxHeightFactor: 0.86,
    builder: (sheetContext, _) => AccountFormEditorial(ref: ref, account: account),
  );
}

class AccountFormEditorial extends StatefulWidget {
  final WidgetRef ref;
  final AccountModel? account;

  const AccountFormEditorial({super.key, required this.ref, this.account});

  @override
  State<AccountFormEditorial> createState() => _AccountFormEditorialState();
}

class _AccountFormEditorialState extends State<AccountFormEditorial> {
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
      final notifier = widget.ref.read(accountsProvider.notifier);
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
    final confirmed = await confirmEditorial(
      context,
      title: '¿Eliminar cuenta?',
      body: 'Esta acción es permanente y eliminará todas las transacciones asociadas a esta cuenta.',
      confirmLabel: 'Eliminar',
    );

    if (confirmed == true && mounted) {
      setState(() => _saving = true);
      try {
        await widget.ref.read(accountsProvider.notifier).deleteAccount(widget.account!.id);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              _portada(),
              const SizedBox(height: 24),
              const EditorialSectionLabel('Saldo inicial (USD)'),
              const SizedBox(height: 12),
              EditorialField(
                controller: _balanceController,
                hint: '0.00',
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                prefix: Text(
                  '\$ ',
                  style: EditorialTheme.text(15, color: EditorialTheme.ink),
                ),
              ),
              const SizedBox(height: 24),
              const EditorialSectionLabel('Tipo de cuenta'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AccountType.values.map((type) {
                  return EditorialChoice(
                    label: type.label,
                    icon: type.icon,
                    selected: _type == type,
                    accent: type.color,
                    onTap: () => setState(() => _type = type),
                  );
                }).toList(),
              ),
              if (_isEditing) ...[
                const SizedBox(height: 32),
                EditorialButton(
                  label: 'Eliminar cuenta',
                  tone: const Color(0xFFB3261E),
                  ghost: true,
                  onTap: () => _deleteAccount(context),
                ),
              ],
            ],
          ),
        ),
        const EditorialRule(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: EditorialButton(
            label: _isEditing ? 'Guardar Cambios' : 'Crear Cuenta',
            onTap: _saving ? null : _save,
          ),
        ),
      ],
    );
  }

  Widget _portada() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: EditorialTheme.gray,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            _type.icon,
            size: 28,
            color: EditorialTheme.accent(_type.color, onDark: false),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: EditorialField(
            controller: _nameController,
            hint: 'Nombre de la cuenta',
            autofocus: !_isEditing,
            textInputAction: TextInputAction.next,
          ),
        ),
      ],
    );
  }
}
