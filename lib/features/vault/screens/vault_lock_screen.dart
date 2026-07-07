import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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

  InputDecoration _darkInputDecoration({required String hint, required IconData icon, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: BentoTheme.creamAlpha(0.3)),
      prefixIcon: Icon(icon, color: BentoTheme.creamAlpha(0.55)),
      suffixIcon: suffixIcon,
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
        borderSide: BorderSide(color: BentoTheme.accentBrain, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(vaultProvider);

    return Scaffold(
      backgroundColor: BentoTheme.darkBg,
      appBar: AppBar(
        backgroundColor: BentoTheme.darkBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: BentoTheme.cream),
          tooltip: 'Volver',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [BentoTheme.darkBgTop, BentoTheme.darkBg],
            stops: [0.0, 0.6],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Logo/Icono
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: BentoTheme.darkCard,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: BentoTheme.accentBrain, width: 2),
                  ),
                  child: Center(
                    child: Icon(
                      vaultState.isSetup ? Icons.lock_outline : Icons.enhanced_encryption_outlined,
                      size: 48,
                      color: BentoTheme.accentBrain,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  vaultState.isSetup ? 'Bóveda Protegida' : 'Configura tu Bóveda',
                  style: GoogleFonts.montserrat(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: BentoTheme.cream,
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  vaultState.isSetup
                      ? 'Autentícate para acceder a tus contraseñas y secretos'
                      : 'Tus datos se cifrarán en el dispositivo de forma segura usando encriptación de conocimiento cero.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.montserrat(
                    fontSize: 14,
                    color: BentoTheme.creamAlpha(0.55),
                  ),
                ),
                const SizedBox(height: 32),

                if (vaultState.error != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: BentoTheme.errorRed.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: BentoTheme.errorRed, width: 1.5),
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
                    GestureDetector(
                      onTap: _attemptBiometricUnlock,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        decoration: BoxDecoration(
                          color: BentoTheme.darkCard,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: BentoTheme.accentBrain, width: 1.5),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.fingerprint_outlined,
                              size: 64,
                              color: BentoTheme.accentBrain,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Tocar para Desbloquear con Huella',
                              style: GoogleFonts.montserrat(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: BentoTheme.cream,
                              ),
                            ),
                          ],
                        ),
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
                      style: TextButton.styleFrom(foregroundColor: BentoTheme.accentBrain),
                      icon: const Icon(Icons.password_outlined),
                      label: const Text(
                        'Usar contraseña de respaldo',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ] else ...[
                    // Formulario de Contraseña de Respaldo
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: BentoTheme.darkCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: BentoTheme.creamAlpha(0.1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Contraseña de Respaldo',
                            style: GoogleFonts.montserrat(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: BentoTheme.cream,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscureText1,
                            style: const TextStyle(color: BentoTheme.cream),
                            decoration: _darkInputDecoration(
                              hint: 'Ingresa tu contraseña maestra',
                              icon: Icons.lock_outline,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureText1 ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: BentoTheme.creamAlpha(0.55),
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
                                ? const Center(child: CircularProgressIndicator(color: BentoTheme.accentBrain))
                                : ElevatedButton(
                                    onPressed: _handlePasswordUnlock,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: BentoTheme.accentBrain,
                                      foregroundColor: const Color(0xFF0C0C0D),
                                      elevation: 0,
                                    ),
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
                      style: TextButton.styleFrom(foregroundColor: BentoTheme.accentBrain),
                      icon: const Icon(Icons.fingerprint_outlined),
                      label: const Text(
                        'Volver a usar biometría',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ] else ...[
                  // Formulario de Configuración Inicial (Setup)
                  Form(
                    key: _formKey,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: BentoTheme.darkCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: BentoTheme.creamAlpha(0.1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Crea una Contraseña Maestra',
                            style: GoogleFonts.montserrat(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: BentoTheme.cream,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Esta contraseña te servirá de respaldo si la biometría no está disponible. No se puede recuperar si la olvidas.',
                            style: TextStyle(fontSize: 12, color: BentoTheme.creamAlpha(0.55)),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscureText1,
                            style: const TextStyle(color: BentoTheme.cream),
                            validator: (val) {
                              if (val == null || val.isEmpty) return 'La contraseña es obligatoria';
                              if (val.length < 6) return 'Debe tener al menos 6 caracteres';
                              return null;
                            },
                            decoration: _darkInputDecoration(
                              hint: 'Contraseña maestra',
                              icon: Icons.lock_outline,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureText1 ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: BentoTheme.creamAlpha(0.55),
                                ),
                                onPressed: () => setState(() => _obscureText1 = !_obscureText1),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmController,
                            obscureText: _obscureText2,
                            style: const TextStyle(color: BentoTheme.cream),
                            validator: (val) {
                              if (val != _passwordController.text) {
                                return 'Las contraseñas no coinciden';
                              }
                              return null;
                            },
                            decoration: _darkInputDecoration(
                              hint: 'Confirmar contraseña maestra',
                              icon: Icons.lock_outline,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureText2 ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: BentoTheme.creamAlpha(0.55),
                                ),
                                onPressed: () => setState(() => _obscureText2 = !_obscureText2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: _isProcessing
                                ? const Center(child: CircularProgressIndicator(color: BentoTheme.accentBrain))
                                : ElevatedButton(
                                    onPressed: _handleSetup,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: BentoTheme.accentBrain,
                                      foregroundColor: const Color(0xFF0C0C0D),
                                      elevation: 0,
                                    ),
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
      ),
    );
  }
}
