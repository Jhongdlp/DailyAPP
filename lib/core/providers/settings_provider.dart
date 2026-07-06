import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String localAiUrl;
  final String textModel;
  final String visionModel;
  final bool isSupabaseConfigured;

  AppSettings({
    this.supabaseUrl = 'https://vhtorhsyqszoaeshlnjs.supabase.co',
    this.supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZodG9yaHN5cXN6b2Flc2hsbmpzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE3MjkwOTYsImV4cCI6MjA5NzMwNTA5Nn0.y1FMqvVlchoFLr06NWvA9sCUZsFsaQ9GPB59BrH8Q9k',
    this.localAiUrl = 'http://63.141.255.7:11434',
    this.textModel = 'qwen2.5-coder:14b',
    this.visionModel = 'qwen3-vl:8b',
    this.isSupabaseConfigured = true,
  });

  AppSettings copyWith({
    String? supabaseUrl,
    String? supabaseAnonKey,
    String? localAiUrl,
    String? textModel,
    String? visionModel,
    bool? isSupabaseConfigured,
  }) {
    return AppSettings(
      supabaseUrl: supabaseUrl ?? this.supabaseUrl,
      supabaseAnonKey: supabaseAnonKey ?? this.supabaseAnonKey,
      localAiUrl: localAiUrl ?? this.localAiUrl,
      textModel: textModel ?? this.textModel,
      visionModel: visionModel ?? this.visionModel,
      isSupabaseConfigured: isSupabaseConfigured ?? this.isSupabaseConfigured,
    );
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    _loadSettings();
    return AppSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    final savedUrl = prefs.getString('supabase_url') ?? '';
    final savedKey = prefs.getString('supabase_anon_key') ?? '';
    final savedAiUrl = prefs.getString('local_ai_url') ?? '';
    final savedTextModel = prefs.getString('text_model') ?? '';
    final savedVisionModel = prefs.getString('vision_model') ?? '';

    final url = savedUrl.isNotEmpty ? savedUrl : 'https://vhtorhsyqszoaeshlnjs.supabase.co';
    final key = savedKey.isNotEmpty ? savedKey : 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZodG9yaHN5cXN6b2Flc2hsbmpzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE3MjkwOTYsImV4cCI6MjA5NzMwNTA5Nn0.y1FMqvVlchoFLr06NWvA9sCUZsFsaQ9GPB59BrH8Q9k';
    final aiUrl = savedAiUrl.isNotEmpty ? savedAiUrl : 'http://63.141.255.7:11434';
    final tModel = savedTextModel.isNotEmpty ? savedTextModel : 'qwen2.5-coder:14b';
    final vModel = savedVisionModel.isNotEmpty ? savedVisionModel : 'qwen3-vl:8b';

    state = AppSettings(
      supabaseUrl: url,
      supabaseAnonKey: key,
      localAiUrl: aiUrl,
      textModel: tModel,
      visionModel: vModel,
      isSupabaseConfigured: url.isNotEmpty && key.isNotEmpty,
    );
  }

  Future<void> updateSupabase({required String url, required String anonKey}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('supabase_url', url);
    await prefs.setString('supabase_anon_key', anonKey);
    state = state.copyWith(
      supabaseUrl: url,
      supabaseAnonKey: anonKey,
      isSupabaseConfigured: url.isNotEmpty && anonKey.isNotEmpty,
    );
  }

  Future<void> updateLocalAI({
    required String url,
    required String textModel,
    required String visionModel,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('local_ai_url', url);
    await prefs.setString('text_model', textModel);
    await prefs.setString('vision_model', visionModel);
    state = state.copyWith(
      localAiUrl: url,
      textModel: textModel,
      visionModel: visionModel,
    );
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    state = AppSettings();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(() {
  return SettingsNotifier();
});
