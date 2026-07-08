using System;
using System.IO;
using System.Text.RegularExpressions;

namespace ReplaceErrors
{
    class Program
    {
        static void Main(string[] args)
        {
            string path = @"..\..\..\lib\features\logistics\data\repositories\delivery_repository.dart";
            if (!File.Exists(path)) {
                path = @"d:\enterprise_auth_system\frontend\lib\features\logistics\data\repositories\delivery_repository.dart";
            }
            string content = File.ReadAllText(path);
            
            content = Regex.Replace(content, @"throw 'Failed to (.*?): \$e';", "throw 'Failed to $1: ${ApiErrorHandler.getErrorMessage(e)}';");
            content = content.Replace("throw 'Sync failed: $e';", "throw 'Sync failed: ${ApiErrorHandler.getErrorMessage(e)}';");
            content = content.Replace("throw 'Unexpected error: $e';", "throw 'Unexpected error: ${ApiErrorHandler.getErrorMessage(e)}';");
            
            if (!content.Contains("api_error_handler.dart")) {
                content = content.Replace("import 'package:dio/dio.dart';", "import 'package:dio/dio.dart';\nimport '../../../../core/error/api_error_handler.dart';");
            }
            
            File.WriteAllText(path, content);
            Console.WriteLine("Replaced errors successfully!");
        }
    }
}
