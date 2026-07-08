import re

def update_file(filepath, num_parent_dirs):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Replace "throw 'Failed to ...: $e';"
    content = re.sub(r"throw 'Failed to (.*?): \$e';", r"throw 'Failed to \1: ${ApiErrorHandler.getErrorMessage(e)}';", content)
    
    # Replace "throw 'Sync failed: $e';"
    content = content.replace("throw 'Sync failed: $e';", "throw 'Sync failed: ${ApiErrorHandler.getErrorMessage(e)}';")
    
    # Replace "throw 'Unexpected error: $e';"
    content = content.replace("throw 'Unexpected error: $e';", "throw 'Unexpected error: ${ApiErrorHandler.getErrorMessage(e)}';")

    if 'api_error_handler.dart' not in content:
        import_path = '../' * num_parent_dirs + 'core/error/api_error_handler.dart'
        content = content.replace("import 'package:dio/dio.dart';", f"import 'package:dio/dio.dart';\nimport '{import_path}';")

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

update_file('lib/features/logistics/data/repositories/delivery_repository.dart', 4)
update_file('lib/features/logistics/data/sync/sync_manager.dart', 4)
print('Updated files successfully')
