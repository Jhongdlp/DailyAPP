import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/bento_theme.dart';
import '../../../core/providers/vault_provider.dart';
import 'vault_home_screen.dart';

class VaultLockScreen extends ConsumerStatefulWidget {
  const VaultLockScreen({super.key});

  @override
  ConsumerState<VaultLockScreen> createState() => _VaultLockScreenState();
}

class _VaultLockScreenState extends ConsumerState<VaultLockScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _usePasswordBackup = false;
  bool _obscureText1 = true;
  bool _obscureText2 = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // Intentar desbloquear biométricamente de forma automática si la bóveda ya está configurada
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptBiometricUnlock();
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _attemptBiometricUnlock() async {
    final stateVal = ref.read(vaultProvider);
    if (stateVal.isSetup && !stateVal.isUnlocked) {
      final success = await ref.read(vaultProvider.notifier).unlockWithBiometrics();
      if (success && mounted) {
        _navigateToVaultHome();
      }
    }
  }

  void _navigateToVaultHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const VaultHomeScreen()),
    );
  }

  Future<void> _handleSetup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isProcessing = true);
    final success = await ref
        .read(vaultProvider.notifier)
        .setupVault(_passwordController.text.trim());
    setState(() => _isProcessing = false);

    if (success && mounted) {
      _navigateToVaultHome();
    }
  }

  Future<void> _handlePasswordUnlock() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) return;

    setState(() => _isProcessing = true);
    final success = await ref
        .read(vaultProvider.notifier)
        .unlockWithPassword(password);
    setState(() => _isProcessing = false);

    if (success && mounted) {
      _navigateToVaultHome();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(vaultProvider);

    return BentoBackground(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo/Icono Bento
              BentoCard(
                width: 100,
                height: 100,
                backgroundColor: BentoTheme.primaryDark,
                borderColor: BentoTheme.primaryDark,
                borderRadius: 24,
                child: Center(
                  child: Icon(
                    vaultState.isSetup ? Icons.lock_outline : Icons.enhanced_encryption_outlined,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                vaultState.isSetup ? 'Bóveda Protegida' : 'Configura tu Bóveda',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: BentoTheme.primaryDark,
                ),
              ),
              const SizedBox(height: 8),

              Text(
                vaultState.isSetup
                    ? 'Autentícate para acceder a tus contraseñas y secretos'
                    : 'Tus datos se cifrarán en el dispositivo de forma segura usando encriptación de conocimiento cero.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: BentoTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 32),

              if (vaultState.error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: BentoTheme.errorRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: BentoTheme.errorRed, width: 2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: BentoTheme.errorRed),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          vaultState.error!,
                          style: const TextStyle(
                            color: BentoTheme.errorRed,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Si la bóveda ya está configurada
              if (vaultState.isSetup) ...[
                if (!_usePasswordBackup) ...[
                  // Botón Biometría Principal
                  BentoCard(
                    width: double.infinity,
                    onTap: _attemptBiometricUnlock,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    borderColor: BentoTheme.primaryDark,
                    child: const Column(
                      children: [
                        Icon(
                          Icons.fingerprint_outlined,
                          size: 64,
                          color: BentoTheme.primaryDark,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Tocar para Desbloquear con Huella',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: BentoTheme.primaryDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _usePasswordBackup = true;
                        _passwordController.clear();
                      });
                    },
                    icon: const Icon(Icons.password_outlined, color: BentoTheme.primaryDark),
                    label: const Text(
                      'Usar contraseña de respaldo',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: BentoTheme.primaryDark,
                      ),
                    ),
                  ),
                ] else ...[
                  // Formulario de Contraseña de Respaldo
                  BentoCard(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Contraseña de Respaldo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: BentoTheme.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscureText1,
                          decoration: InputDecoration(
                            hintText: 'Ingresa tu contraseña maestra',
                            prefixIcon: const Icon(Icons.lock_outline, color: BentoTheme.textSecondary),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureText1 ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: BentoTheme.textSecondary,
                              ),
                              onPressed: () => setState(() => _obscureText1 = !_obscureText1),
                            ),
                          ),
                          onSubmitted: (_) => _handlePasswordUnlock(),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: _isProcessing
                              ? const Center(child: CircularProgressIndicator(color: BentoTheme.primaryDark))
                              : ElevatedButton(
                                  onPressed: _handlePasswordUnlock,
                                  child: const Text('Desbloquear'),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _usePasswordBackup = false;
                      });
                      _attemptBiometricUnlock();
                    },
                    icon: const Icon(Icons.fingerprint_outlined, color: BentoTheme.primaryDark),
                    label: const Text(
                      'Volver a usar biometría',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: BentoTheme.primaryDark,
                      ),
                    ),
                  ),
                ],
              ] else ...[
                // Formulario de Configuración Inicial (Setup)
                Form(
                  key: _formKey,
                  child: BentoCard(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Crea una Contraseña Maestra',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: BentoTheme.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Esta contraseña te servirá de respaldo si la biometría no está disponible. No se puede recuperar si la olvidas.',
                          style: TextStyle(fontSize: 12, color: BentoTheme.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscureText1,
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'La contraseña es obligatoria';
                            if (val.length < 6) return 'Debe tener al menos 6 caracteres';
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'Contraseña maestra',
                            prefixIcon: const Icon(Icons.lock_outline, color: BentoTheme.textSecondary),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureText1 ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: BentoTheme.textSecondary,
                              ),
                              onPressed: () => setState(() => _obscureText1 = !_obscureText1),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmController,
                          obscureText: _obscureText2,
                          validator: (val) {
                            if (val != _passwordController.text) {
                              return 'Las contraseñas no coinciden';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'Confirmar contraseña maestra',
                            prefixIcon: const Icon(Icons.lock_outline, color: BentoTheme.textSecondary),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureText2 ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: BentoTheme.textSecondary,
                              ),
                              onPressed: () => setState(() => _obscureText2 = !_obscureText2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: _isProcessing
                              ? const Center(child: CircularProgressIndicator(color: BentoTheme.primaryDark))
                              : ElevatedButton(
                                  onPressed: _handleSetup,
                                  child: const Text('Configurar Bóveda'),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
