$path = "d:\enterprise_auth_system\frontend\lib\features\logistics\data\repositories\delivery_repository.dart"
$content = Get-Content $path -Raw
$content = [System.Text.RegularExpressions.Regex]::Replace($content, "throw 'Failed to (.*?): `$e';", "throw 'Failed to `$1: `${ApiErrorHandler.getErrorMessage(e)}';")
$content = $content.Replace("throw 'Sync failed: `$e';", "throw 'Sync failed: `${ApiErrorHandler.getErrorMessage(e)}';")
if (-not $content.Contains("api_error_handler.dart")) {
    $content = $content.Replace("import 'package:dio/dio.dart';", "import 'package:dio/dio.dart';`nimport '../../../../core/error/api_error_handler.dart';")
}
[IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)
Write-Host "Success"
