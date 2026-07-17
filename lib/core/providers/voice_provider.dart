import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/voice_service.dart';
import '../network/local_ai_client.dart';
import 'settings_provider.dart';

final voiceServiceProvider = Provider<VoiceService>((ref) {
  final settings = ref.watch(settingsProvider);
  final client = LocalAIClient(
    baseUrl: settings.localAiUrl,
    textModelName: settings.textModel,
    visionModelName: settings.visionModel,
    embeddingModelName: settings.embeddingModel,
  );
  return VoiceService(client);
});
