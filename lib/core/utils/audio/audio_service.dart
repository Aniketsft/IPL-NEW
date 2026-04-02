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
      debugPrint('AudioService: Pre-loading audio assets...');
      await _successPlayer.setSource(AssetSource('audio/Scan Confirm.mp3'));
      await _errorPlayer.setSource(AssetSource('audio/Scan Reject.mp3'));
    } catch (e) {
      debugPrint('AudioService: Initialization error: $e');
    }
  }

  /// Plays the success chime.
  Future<void> playSuccess() async {
    try {
      debugPrint('AudioService: Playing success sound (low latency)');
      if (_successPlayer.state == PlayerState.playing) {
        await _successPlayer.stop();
      }
      await _successPlayer.seek(Duration.zero);
      await _successPlayer.resume();
    } catch (e) {
      debugPrint('AudioService: Error playing success sound: $e');
    }
  }

  /// Plays the error/invalid chime.
  Future<void> playError() async {
    try {
      debugPrint('AudioService: Playing error sound (low latency)');
      if (_errorPlayer.state == PlayerState.playing) {
        await _errorPlayer.stop();
      }
      await _errorPlayer.seek(Duration.zero);
      await _errorPlayer.resume();
    } catch (e) {
      debugPrint('AudioService: Error playing error sound: $e');
    }
  }

  void dispose() {
    _successPlayer.dispose();
    _errorPlayer.dispose();
  }
}
