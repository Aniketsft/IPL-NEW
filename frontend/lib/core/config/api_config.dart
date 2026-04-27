import 'dart:io';
import 'package:flutter/foundation.dart';

class ApiConfig {
  /// Base IP Address for the backend server.
  /// Update this value to change the IP globally across the app.
  static const String serverIp = '172.26.106.82';
  //'172.26.106.42'; POKEMON

  //'192.168.100.13';
  // 192.168.1.97 sft
  //'192.168.100.156'; Home
  // 192.168.100.10 innodis winter
  // 172.26.106.82 innodis wifi pokemon
  
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
