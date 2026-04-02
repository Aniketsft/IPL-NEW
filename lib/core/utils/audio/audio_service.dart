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
      // Pre-set the source for faster playback
      // Note: These files must exist in assets/audio/ for this to work in a real build.
      // We are setting them up as placeholders as requested.
      await _successPlayer.setSource(
        AssetSource(
          'C:/Users/Aniket/.gemini/antigravity/scratch/enterprise_auth_system/assets/audio/Scan Confirm.mp3',
        ),
      );
      await _errorPlayer.setSource(
        AssetSource(
          'C:/Users/Aniket/.gemini/antigravity/scratch/enterprise_auth_system/assets/audio/Scan Reject.mp3',
        ),
      );
    } catch (e) {
      debugPrint('AudioService initialization error: $e');
    }
  }

  /// Plays the success chime.
  Future<void> playSuccess() async {
    try {
      if (_successPlayer.state == PlayerState.playing) {
        await _successPlayer.stop();
      }
      await _successPlayer.resume();
    } catch (e) {
      debugPrint('Error playing success sound: $e');
      // Fallback to system sound if assets are missing
    }
  }

  /// Plays the error/invalid chime.
  Future<void> playError() async {
    try {
      if (_errorPlayer.state == PlayerState.playing) {
        await _errorPlayer.stop();
      }
      await _errorPlayer.resume();
    } catch (e) {
      debugPrint('Error playing error sound: $e');
    }
  }

  void dispose() {
    _successPlayer.dispose();
    _errorPlayer.dispose();
  }
}
