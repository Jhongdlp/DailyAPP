import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/bento_theme.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/network/local_ai_client.dart';
import '../../core/utils/error_snackbar.dart';
import '../dashboard/dashboard_screen.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supabaseUrlController = TextEditingController();
  final _supabaseKeyController = TextEditingController();
  final _localAiUrlController = TextEditingController();
  final _textModelController = TextEditingController();
  final _visionModelController = TextEditingController();

  bool _testingAI = false;
  bool? _aiConnectionOk;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Pre-cargar valores actuales
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = ref.read(settingsProvider);
      _supabaseUrlController.text = settings.supabaseUrl;
      _supabaseKeyController.text = settings.supabaseAnonKey;
      _localAiUrlController.text = settings.localAiUrl;
      _textModelController.text = settings.textModel;
      _visionModelController.text = settings.visionModel;
    });
  }

  @override
  void dispose() {
    _supabaseUrlController.dispose();
    _supabaseKeyController.dispose();
    _localAiUrlController.dispose();
    _textModelController.dispose();
    _visionModelController.dispose();
    super.dispose();
  }

  Future<void> _testLocalAI() async {
    setState(() {
      _testingAI = true;
      _aiConnectionOk = null;
    });

    final testClient = LocalAIClient(
      baseUrl: _localAiUrlController.text.trim(),
    );

    final ok = await testClient.checkHealth();

    if (mounted) {
      setState(() {
        _testingAI = false;
        _aiConnectionOk = ok;
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok 
              ? '¡Conexión con Servidor IA Local establecida con éxito!' 
              : 'No se pudo conectar al Servidor IA. Verifica la URL e IP.',
          ),
          backgroundColor: ok ? BentoTheme.successGreen : BentoTheme.errorRed,
        ),
      );
    }
  }

  Future<void> _saveAndProceed() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final url = _supabaseUrlController.text.trim();
    final key = _supabaseKeyController.text.trim();
    final aiUrl = _localAiUrlController.text.trim();
    final tModel = _textModelController.text.trim();
    final vModel = _visionModelController.text.trim();

    try {
      // 1. Guardar configuraciones en shared_preferences
      await ref.read(settingsProvider.notifier).updateSupabase(url: url, anonKey: key);
      await ref.read(settingsProvider.notifier).updateLocalAI(
        url: aiUrl,
        textModel: tModel,
        visionModel: vModel,
      );

      // 2. Inicializar Supabase dinámicamente
      try {
        await Supabase.initialize(
          url: url,
          anonKey: key,
          debug: false,
        );
      } catch (e) {
        // Si ya está inicializado, ignoramos el error
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, message: 'Error al inicializar servicios: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BentoBackground(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Título y Logo
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: BentoTheme.cardBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: BentoTheme.primaryDark, width: 2),
                      ),
                      child: const Icon(
                        Icons.tune_outlined,
                        size: 48,
                        color: BentoTheme.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'SistemDaily',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                            color: BentoTheme.primaryDark,
                          ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Configura tu Segundo Cerebro & IA Local',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: BentoTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Formulario Bento
              BentoCard(
                borderWidth: 2.0,
                borderColor: BentoTheme.primaryDark,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '🔌 Servidor de Datos (Supabase)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: BentoTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _supabaseUrlController,
                        style: const TextStyle(color: BentoTheme.textPrimary, fontWeight: FontWeight.w500),
                        decoration: const InputDecoration(
                          labelText: 'Supabase URL',
                          hintText: 'https://xxxxxx.supabase.co',
                        ),
                        validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _supabaseKeyController,
                        obscureText: true,
                        style: const TextStyle(color: BentoTheme.textPrimary, fontWeight: FontWeight.w500),
                        decoration: const InputDecoration(
                          labelText: 'Supabase Anon Key',
                          hintText: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
                        ),
                        validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 24),
                      
                      const Text(
                        '🤖 Servidor de IA Local (Qwen)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: BentoTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _localAiUrlController,
                              style: const TextStyle(color: BentoTheme.textPrimary, fontWeight: FontWeight.w500),
                              decoration: const InputDecoration(
                                labelText: 'URL de API Local',
                                hintText: 'http://192.168.x.x:11434',
                              ),
                              validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Botón para probar conexión
                          IconButton.filled(
                            onPressed: _testingAI ? null : _testLocalAI,
                            style: IconButton.styleFrom(
                              backgroundColor: _aiConnectionOk == true
                                  ? BentoTheme.successGreen
                                  : _aiConnectionOk == false
                                      ? BentoTheme.errorRed
                                      : BentoTheme.primaryDark,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: _testingAI
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Icon(_aiConnectionOk == true ? Icons.check : _aiConnectionOk == false ? Icons.close : Icons.bolt),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _textModelController,
                              style: const TextStyle(color: BentoTheme.textPrimary, fontWeight: FontWeight.w500),
                              decoration: const InputDecoration(
                                labelText: 'Modelo Texto (Qwen)',
                              ),
                              validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _visionModelController,
                              style: const TextStyle(color: BentoTheme.textPrimary, fontWeight: FontWeight.w500),
                              decoration: const InputDecoration(
                                labelText: 'Modelo Visión (Qwen-VL)',
                              ),
                              validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Botón para Guardar
                      ElevatedButton(
                        onPressed: _saving ? null : _saveAndProceed,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: BentoTheme.primaryDark,
                        ),
                        child: _saving
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text('Guardar y Conectar'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
