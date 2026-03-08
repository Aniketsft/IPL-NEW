import 'dart:io';
import 'package:flutter/foundation.dart';

class ApiConfig {
  /// Base IP Address for the backend server.
  /// Update this value to change the IP globally across the app.
  static const String serverIp = '192.168.100.156';

  ///'192.168.1.107'

  /// Port number for the backend server. (Default is 5004)
  static const String serverPort = '5004';

  /// Port for local development (standard .NET HTTPS port)
  static const String localPort = '7176';

  /// Generates the base URL for API calls based on the platform.
  static String get baseUrl {
    if (!kIsWeb && Platform.isAndroid) {
      // Use the configured server IP for Android
      return 'http://$serverIp:$serverPort/api/';
    }
    // Use localhost for iOS simulator or other platforms
    return 'https://localhost:$localPort/api/';
  }
}
