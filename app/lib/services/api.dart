import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Thin client for the Node/SQLite backend in /backend.
class ApiClient {
  String baseUrl = kDefaultServer;
  String? token;
  String? username;

  bool get isLoggedIn => token != null;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    baseUrl = p.getString('baseUrl') ?? kDefaultServer;
    token = p.getString('token');
    username = p.getString('username');
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('baseUrl', baseUrl);
    if (token == null) {
      await p.remove('token');
      await p.remove('username');
    } else {
      await p.setString('token', token!);
      await p.setString('username', username ?? '');
    }
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    await _persist();
  }

  Future<void> logout() async {
    token = null;
    username = null;
    await _persist();
  }

  Future<dynamic> _request(String method, String path, {Map<String, dynamic>? body, bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (auth && token != null) 'Authorization': 'Bearer $token',
    };
    try {
      final http.Response res;
      if (method == 'GET') {
        res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
      } else {
        res = await http.post(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 8));
      }
      final decoded = res.body.isEmpty ? null : jsonDecode(res.body);
      if (res.statusCode >= 400) {
        final msg = (decoded is Map && decoded['error'] is String) ? decoded['error'] as String : 'Server error (${res.statusCode})';
        throw ApiException(msg, status: res.statusCode);
      }
      return decoded;
    } on TimeoutException {
      throw ApiException('Server not reachable (timeout). Check the URL and that both devices are on the same Wi-Fi.');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Cannot reach the server: $e');
    }
  }

  Future<bool> health() async {
    final r = await _request('GET', '/api/health', auth: false);
    return r is Map && r['ok'] == true;
  }

  Future<void> _authenticate(String path, String user, String pass) async {
    final r = await _request('POST', path, body: {'username': user, 'password': pass}, auth: false);
    token = r['token'] as String;
    username = (r['user'] as Map)['username'] as String;
    await _persist();
  }

  Future<void> register(String user, String pass) => _authenticate('/api/auth/register', user, pass);
  Future<void> login(String user, String pass) => _authenticate('/api/auth/login', user, pass);

  Future<Map<String, dynamic>> summary() async => Map<String, dynamic>.from(await _request('GET', '/api/me/summary') as Map);

  Future<void> saveStage(int stage) => _request('POST', '/api/tutorial/stage', body: {'stage': stage});

  Future<void> saveAttempt({
    required String mode,
    required int score,
    required double durationSec,
    required int collisions,
    required double stability,
    required bool success,
  }) =>
      _request('POST', '/api/attempts', body: {
        'mode': mode,
        'score': score,
        'durationSec': durationSec,
        'collisions': collisions,
        'stability': stability,
        'success': success,
      });

  Future<List<Map<String, dynamic>>> attempts() async {
    final r = await _request('GET', '/api/attempts?limit=50') as List;
    return r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> leaderboard(String mode) async {
    final r = await _request('GET', '/api/leaderboard?mode=$mode') as List;
    return r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}

final ApiClient api = ApiClient();
