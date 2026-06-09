import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class TcpPrintService {
  static Future<bool> sendRawData(String ip, int port, String data) async {
    Socket? socket;
    try {
      debugPrint('Connecting to printer at $ip:$port...');
      socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      
      debugPrint('Sending data to printer...');
      socket.add(utf8.encode(data));
      await socket.flush();
      
      debugPrint('Print job sent successfully.');
      return true;
    } catch (e) {
      debugPrint('TCP Print Error: $e');
      rethrow;
    } finally {
      await socket?.close();
    }
  }
}
