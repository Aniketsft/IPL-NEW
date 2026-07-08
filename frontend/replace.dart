import 'dart:io';

void main() {
  var file = File('lib/features/logistics/data/repositories/delivery_repository.dart');
  var content = file.readAsStringSync();
  content = content.replaceAll(RegExp(r"throw 'Failed to (.*?): \$e';"), r"throw 'Failed to $1: ${ApiErrorHandler.getErrorMessage(e)}';");
  content = content.replaceAll(r"throw 'Sync failed: $e';", r"throw 'Sync failed: ${ApiErrorHandler.getErrorMessage(e)}';");
  
  if (!content.contains('api_error_handler.dart')) {
    content = content.replaceFirst("import 'package:dio/dio.dart';", "import 'package:dio/dio.dart';\nimport '../../../../core/error/api_error_handler.dart';");
  }
  file.writeAsStringSync(content);
  print('Dart replacement complete.');
}
