/// HTTP API Client
/// ================
/// Thin wrapper around [http] that handles connection to the Hive backend.
/// All API calls go through this client.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class ApiClient {
  ApiClient._();

  static final http.Client _client = http.Client();

  /// Generic GET request that returns decoded JSON.
  static Future<Map<String, dynamic>> get(String endpoint) async {
    final uri = Uri.parse('${AppConfig.baseUrl}$endpoint');
    try {
      final response = await _client.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw ApiException(
          'API returned status ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Connection failed: $e');
    }
  }
}

/// Custom exception for API errors.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException: $message';
}
