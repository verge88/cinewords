import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final FlutterTts _tts = FlutterTts();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    _initialized = true;
  }

  static Future<void> speak(String text) async {
    await init();
    await _tts.speak(text);
  }

  static Future<void> stop() async {
    await _tts.stop();
  }

  static Future<void> setSpeechRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }
}
