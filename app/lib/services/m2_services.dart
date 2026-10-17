import 'speech_input.dart';
import 'translation_service.dart';
import 'voice_service.dart';

/// Bundle of the M2 services, created ONCE in main and passed down —
/// one speech-input instance (initialize-once rule), one voice
/// controller (single-speech-controller rule), one translation service.
class M2Services {
  final SpeechInputService speechInput;
  final VoiceService voice;
  final TranslationService translation;

  M2Services({
    SpeechInputService? speechInput,
    VoiceService? voice,
    TranslationService? translation,
  })  : speechInput = speechInput ?? SpeechInputService(),
        voice = voice ?? VoiceService(),
        translation = translation ?? TranslationService();

  /// Non-owning view used by unit tests / previews.
  factory M2Services.withFakes({
    required SpeechInputService speechInput,
    required VoiceService voice,
    required TranslationService translation,
  }) =>
      M2Services(
        speechInput: speechInput,
        voice: voice,
        translation: translation,
      );
}
