import 'package:dio/dio.dart';

class ApiErrorHandler {
  static String getErrorMessage(dynamic error) {
    if (error is DioException) {
      return _handleDioException(error);
    } else {
      // If it's a generic exception, or something thrown via `throw 'string';`
      return error.toString();
    }
  }

  static String _handleDioException(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Please check your internet connection and try again.';
      case DioExceptionType.connectionError:
        return 'Unable to connect to the server. Please check your network connection.';
      case DioExceptionType.badResponse:
        return _handleBadResponse(error.response);
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      case DioExceptionType.badCertificate:
        return 'Connection security error. Invalid certificate.';
      case DioExceptionType.unknown:
      default:
        // Handle SocketExceptions hidden in unknown
        if (error.error != null && error.error.toString().contains('SocketException')) {
          return 'Network error. The server is unreachable. Please check your connection.';
        }
        return 'An unexpected network error occurred.';
    }
  }

  static String _handleBadResponse(Response? response) {
    if (response == null) return 'Invalid response received from the server.';
    
    final statusCode = response.statusCode;
    
    // Try to extract backend error message (ProblemDetails standard in .NET, or generic JSON)
    String? backendMessage;
    try {
      if (response.data is Map<String, dynamic>) {
        backendMessage = response.data['message'] ?? response.data['title'] ?? response.data['error'];
      }
    } catch (_) {}

    if (backendMessage != null && backendMessage.isNotEmpty) {
      return backendMessage; 
    }

    switch (statusCode) {
      case 400:
        return 'Bad request. Please verify the information you entered.';
      case 401:
        return 'Session expired or unauthorized. Please log in again.';
      case 403:
        return 'You do not have permission to access this resource.';
      case 404:
        return 'The requested resource was not found on the server.';
      case 409:
        return 'A conflict occurred with the current state of the resource.';
      case 422:
        return 'Validation error. Please check your input fields.';
      case 500:
        return 'Internal server error (500). Please try again later.';
      case 502:
        return 'Bad gateway (502). The server is currently unavailable.';
      case 503:
        return 'Service unavailable (503). The system is undergoing maintenance.';
      case 504:
        return 'Gateway timeout (504). The server took too long to respond.';
      default:
        return 'An error occurred (Status Code: $statusCode).';
    }
  }
}
