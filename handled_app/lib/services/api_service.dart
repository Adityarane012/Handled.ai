import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000'; // FastAPI default

  // Helper to get headers with JWT if available
  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();

    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      // In a production app, we'd have a robust error handler here.
      throw Exception('API Error ${response.statusCode}: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> get(String endpoint) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();

    final response = await http.get(uri, headers: headers);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      throw Exception('API Error ${response.statusCode}: ${response.body}');
    }
  }

  /// For endpoints that return a JSON array (e.g. GET /ops/approvals).
  static Future<List<dynamic>> getList(String endpoint) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = await _getHeaders();

    final response = await http.get(uri, headers: headers);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body) as List<dynamic>;
    } else {
      throw Exception('API Error ${response.statusCode}: ${response.body}');
    }
  }

  /// Turns a thrown error into something safe to show a user directly —
  /// pulls FastAPI's {"detail": "..."} out of the "API Error N: `body`"
  /// wrapper, or flags an unreachable backend, instead of a raw stack trace.
  static String friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('ClientException') || msg.contains('SocketException') || msg.contains('Failed to fetch')) {
      return "Can't reach the server. Is the backend running?";
    }
    final match = RegExp(r'API Error \d+: (.*)', dotAll: true).firstMatch(msg);
    if (match != null) {
      try {
        final body = jsonDecode(match.group(1)!);
        final detail = body is Map ? body['detail'] : null;
        if (detail is String) return detail;
      } catch (_) {
        // response body wasn't JSON — fall through to the raw message
      }
    }
    return msg.replaceFirst('Exception: ', '');
  }
}
