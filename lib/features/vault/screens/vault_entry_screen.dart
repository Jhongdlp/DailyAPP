import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/providers/vault_provider.dart';
import '../models/vault_item.dart';

class VaultEntryScreen extends ConsumerStatefulWidget {
  final VaultItem? item;

  const VaultEntryScreen({super.key, this.item});

  @override
  ConsumerState<VaultEntryScreen> createState() => _VaultEntryScreenState();
}

class _VaultEntryScreenState extends ConsumerState<VaultEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  // Campos específicos
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _urlController = TextEditingController();

  final _cardHolderController = TextEditingController();
  final _cardNumberController = TextEditingController();
  final _cardExpiryController = TextEditingController();
  final _cardCvvController = TextEditingController();

  final _noteTextController = TextEditingController();

  String _category = 'password'; // 'password', 'card', 'note', 'other'
  bool _obscurePassword = true;
  bool _obscureCvv = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.item != null) {
      _loadExistingItem();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _cardHolderController.dispose();
    _cardNumberController.dispose();
    _cardExpiryController.dispose();
    _cardCvvController.dispose();
    _noteTextController.dispose();
    super.dispose();
  }

  void _loadExistingItem() {
    final item = widget.item!;
    final vaultKey = ref.read(vaultProvider).vaultKey!;
    
    _titleController.text = item.getDecryptedTitle(vaultKey);
    _descController.text = item.getDecryptedDescription(vaultKey) ?? '';
    _category = item.category;

    final payload = item.getDecryptedPayload(vaultKey);
    if (_category == 'password') {
      _usernameController.text = payload['username'] ?? '';
      _passwordController.text = payload['password'] ?? '';
      _urlController.text = payload['url'] ?? '';
    } else if (_category == 'card') {
      _cardHolderController.text = payload['cardholder'] ?? '';
      _cardNumberController.text = payload['number'] ?? '';
      _cardExpiryController.text = payload['expiry'] ?? '';
      _cardCvvController.text = payload['cvv'] ?? '';
    } else if (_category == 'note') {
      _noteTextController.text = payload['note_text'] ?? '';
    } else {
      _noteTextController.text = payload['other_text'] ?? '';
    }
  }

  void _generateSecurePassword() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()_-+=<>?';
    final rand = Random.secure();
    final password = List.generate(16, (index) => chars[rand.nextInt(chars.length)]).join();
    
    setState(() {
      _passwordController.text = password;
      _obscurePassword = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Contraseña segura de 16 caracteres generada.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    // Armar el payload dinámico según la categoría
    final Map<String, dynamic> payload = {};
    if (_category == 'password') {
      payload['username'] = _usernameController.text.trim();
      payload['password'] = _passwordController.text.trim();
      payload['url'] = _urlController.text.trim();
    } else if (_category == 'card') {
      payload['cardholder'] = _cardHolderController.text.trim();
      payload['number'] = _cardNumberController.text.trim();
      payload['expiry'] = _cardExpiryController.text.trim();
      payload['cvv'] = _cardCvvController.text.trim();
    } else if (_category == 'note') {
      payload['note_text'] = _noteTextController.text.trim();
    } else {
      payload['other_text'] = _noteTextController.text.trim();
    }

    final notifier = ref.read(vaultProvider.notifier);
    bool success;

    if (widget.item == null) {
      // Agregar nuevo
      success = await notifier.addVaultItem(
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        category: _category,
        payload: payload,
      );
    } else {
      // Editar existente
      success = await notifier.updateVaultItem(
        widget.item!,
        title: _titleController.text.trim(),
        description: _descController.text.trim(),
        category: _category,
        payload: payload,
      );
    }

    setState(() => _isSaving = false);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Guardado correctamente en la bóveda.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.item != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? 'Editar Elemento' : 'Nuevo Elemento',
          style: TextStyle(fontWeight: FontWeight.bold, color: BentoTheme.primaryDark),
        ),
        elevation: 0,
        backgroundColor: BentoTheme.bgLight,
      ),
      backgroundColor: BentoTheme.bgLight,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Categoría Selector (Bento Card)
                BentoCard(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Categoría',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: BentoTheme.primaryDark),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildCategoryButton('password', 'Contraseña', Icons.vpn_key_outlined),
                          _buildCategoryButton('card', 'Tarjeta', Icons.credit_card_outlined),
                          _buildCategoryButton('note', 'Nota Segura', Icons.lock_outline),
                          _buildCategoryButton('other', 'Otro', Icons.more_horiz_outlined),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Datos Generales
                BentoCard(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Información General',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: BentoTheme.primaryDark),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _titleController,
                        validator: (val) => val == null || val.isEmpty ? 'El título es requerido' : null,
                        decoration: InputDecoration(
                          labelText: 'Título',
                          hintText: 'Ej. Mi correo personal',
                          prefixIcon: Icon(Icons.title, color: BentoTheme.textSecondary),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Descripción / Notas rápidas',
                          hintText: 'Ej. Cuenta principal de desarrollo',
                          prefixIcon: Icon(Icons.notes, color: BentoTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Campos Dinámicos según Categoría
                if (_category == 'password') ...[
                  BentoCard(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Detalles de la Cuenta',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: BentoTheme.primaryDark),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: 'Usuario / Correo',
                            hintText: 'ejemplo@correo.com',
                            prefixIcon: Icon(Icons.person_outline, color: BentoTheme.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          validator: (val) => val == null || val.isEmpty ? 'La contraseña es requerida' : null,
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: Icon(Icons.password_outlined, color: BentoTheme.textSecondary),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.casino_outlined),
                                  tooltip: 'Generar Contraseña Segura',
                                  onPressed: _generateSecurePassword,
                                ),
                                IconButton(
                                  icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            labelText: 'Sitio Web / URL',
                            hintText: 'https://ejemplo.com',
                            prefixIcon: Icon(Icons.link, color: BentoTheme.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_category == 'card') ...[
                  BentoCard(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Detalles de la Tarjeta',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: BentoTheme.primaryDark),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _cardHolderController,
                          decoration: InputDecoration(
                            labelText: 'Nombre del Titular',
                            hintText: 'JUAN PEREZ',
                            prefixIcon: Icon(Icons.person_outline, color: BentoTheme.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _cardNumberController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Número de Tarjeta',
                            hintText: '4000 1234 5678 9010',
                            prefixIcon: Icon(Icons.credit_card_outlined, color: BentoTheme.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _cardExpiryController,
                                decoration: InputDecoration(
                                  labelText: 'Vencimiento',
                                  hintText: 'MM/AA',
                                  prefixIcon: Icon(Icons.date_range_outlined, color: BentoTheme.textSecondary),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: _cardCvvController,
                                obscureText: _obscureCvv,
                                decoration: InputDecoration(
                                  labelText: 'CVV',
                                  hintText: '123',
                                  prefixIcon: Icon(Icons.lock_outline, color: BentoTheme.textSecondary),
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscureCvv ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                    onPressed: () => setState(() => _obscureCvv = !_obscureCvv),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  BentoCard(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _category == 'note' ? 'Contenido de la Nota Segura' : 'Texto Confidencial',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: BentoTheme.primaryDark),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _noteTextController,
                          maxLines: 8,
                          validator: (val) => val == null || val.isEmpty ? 'El contenido no puede estar vacío' : null,
                          decoration: const InputDecoration(
                            hintText: 'Escribe tu nota confidencial aquí...',
                            prefixIcon: null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Botón Guardar
                SizedBox(
                  width: double.infinity,
                  child: _isSaving
                      ? Center(child: CircularProgressIndicator(color: BentoTheme.primaryDark))
                      : ElevatedButton(
                          onPressed: _handleSave,
                          child: const Text('Guardar Elemento'),
                        ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryButton(String categoryType, String label, IconData icon) {
    final isSelected = _category == categoryType;
    final buttonColor = isSelected ? BentoTheme.primaryDark : Colors.transparent;
    final textColor = isSelected ? Colors.white : BentoTheme.textPrimary;
    final iconColor = isSelected ? Colors.white : BentoTheme.textSecondary;
    final borderColor = isSelected ? BentoTheme.primaryDark : BentoTheme.borderMuted;

    return GestureDetector(
      onTap: () {
        setState(() {
          _category = categoryType;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        width: 72,
        decoration: BoxDecoration(
          color: buttonColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
