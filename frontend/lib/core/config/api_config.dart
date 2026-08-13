import 'dart:io';
import 'package:flutter/foundation.dart';

class ApiConfig {
  /// Base IP Address for the backend server.
  /// Update this value to change the IP globally across the app.
  static const String serverIp = '192.168.120.7';

  /// Centralized configuration for user inactivity timeout.
  /// The app will automatically log out the user after this duration of inactivity.
  static const Duration inactivityTimeout = Duration(minutes: 30);

  //'192.168.100.13';
  // 192.168.1.78 sft
  //'192.168.100.156'; Home
  // 10.131.28.227
  // 192.168.100.10 innodis winter
  // 192.168.120.2 innodis server
  // 172.26.106.82 innodis wifi pokemon
  // http://192.168.120.7/ server x3
  // 10.131.28.227 IPLL pokemon

  /// Port number for the backend server. (Default is 5004)
  static const String serverPort = '5004';

  /// Port for local development (standard .NET HTTPS port)
  static const String localPort = '7176';

  /// Generates the base URL for API calls based on the platform.
  static String get baseUrl {
    if (!kIsWeb) {
      if (Platform.isAndroid || Platform.isIOS) {
        return 'http://$serverIp:$serverPort/api/';
      }
    }
    return 'https://localhost:$localPort/api/';
  }
}
