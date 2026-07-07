import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Backend e IA fijos del proyecto: no son configurables desde la app
/// (multi-tenant, cada usuario se aísla por RLS con su propia cuenta, no por
/// servidor; y el servidor de IA es un único servidor propio, no por-usuario).
const String kSupabaseUrl = 'https://vhtorhsyqszoaeshlnjs.supabase.co';
const String kSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZodG9yaHN5cXN6b2Flc2hsbmpzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE3MjkwOTYsImV4cCI6MjA5NzMwNTA5Nn0.y1FMqvVlchoFLr06NWvA9sCUZsFsaQ9GPB59BrH8Q9k';
const String kLocalAiUrl = 'http://63.141.255.7:11434';
const String kTextModel = 'qwen2.5-coder:14b';
const String kVisionModel = 'qwen3-vl:8b';

class AppSettings {
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String localAiUrl;
  final String textModel;
  final String visionModel;
  final bool isSupabaseConfigured;

  const AppSettings({
    this.supabaseUrl = kSupabaseUrl,
    this.supabaseAnonKey = kSupabaseAnonKey,
    this.localAiUrl = kLocalAiUrl,
    this.textModel = kTextModel,
    this.visionModel = kVisionModel,
    this.isSupabaseConfigured = true,
  });
}

final settingsProvider = Provider<AppSettings>((ref) => const AppSettings());
