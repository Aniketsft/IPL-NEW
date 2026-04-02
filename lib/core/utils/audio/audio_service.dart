import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// A singleton service to manage audio feedback for scanning and other interactions.
class AudioService {
  static final AudioService _instance = AudioService._internal();
  static AudioService get instance => _instance;

  final AudioPlayer _successPlayer = AudioPlayer();
  final AudioPlayer _errorPlayer = AudioPlayer();

  AudioService._internal() {
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Pre-warm the players
      debugPrint('AudioService: Initializing audio engine...');
      // No longer mandatory to set source here, as we play directly from assets
    } catch (e) {
      debugPrint('AudioService: Initialization error: $e');
    }
  }

  /// Plays the success chime.
  Future<void> playSuccess() async {
    try {
      debugPrint('AudioService: Playing success sound (audio/Scan Confirm.mp3)');
      if (_successPlayer.state == PlayerState.playing) {
        await _successPlayer.stop();
      }
      await _successPlayer.play(AssetSource('audio/Scan Confirm.mp3'), volume: 1.0);
    } catch (e) {
      debugPrint('AudioService: Error playing success sound: $e');
    }
  }

  /// Plays the error/invalid chime.
  Future<void> playError() async {
    try {
      debugPrint('AudioService: Playing error sound (audio/Scan Reject.mp3)');
      if (_errorPlayer.state == PlayerState.playing) {
        await _errorPlayer.stop();
      }
      await _errorPlayer.play(AssetSource('audio/Scan Reject.mp3'), volume: 1.0);
    } catch (e) {
      debugPrint('AudioService: Error playing error sound: $e');
    }
  }

  void dispose() {
    _successPlayer.dispose();
    _errorPlayer.dispose();
  }
}
