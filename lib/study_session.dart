import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

String? roomCodeFrom(String input) {
  final raw = input.trim();
  final code = (Uri.tryParse(raw)?.queryParameters['code'] ?? raw)
      .toUpperCase();
  return RegExp(r'^[A-HJ-NP-Z2-9]{6}$').hasMatch(code) ? code : null;
}

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

class StudyApi {
  final http.Client client;
  String baseUrl;
  String? token;
  StudyApi({http.Client? client, String? baseUrl})
    : client = client ?? http.Client(),
      baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_URL',
            defaultValue: kIsWeb
                ? 'http://127.0.0.1:8080'
                : 'http://10.0.2.2:8080',
          );

  Future<Map<String, dynamic>> request(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      final response =
          await (body == null
                  ? client.get(uri, headers: headers)
                  : client.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(const Duration(seconds: 12));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        throw ApiException(
          data['error'] as String? ?? 'Something went wrong.',
          response.statusCode,
        );
      }
      return data;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(
        'Cannot reach the study server. Check your connection and server address.',
      );
    }
  }
}

class StudySession extends ChangeNotifier {
  final StudyApi api;
  StudySession({StudyApi? api}) : api = api ?? StudyApi();
  Map<String, dynamic>? user;
  Map<String, dynamic>? room;
  String? error;
  String? connectionError;
  bool busy = false;
  bool _polling = false;
  bool _disposed = false;
  int _generation = 0;
  Timer? _timer;
  List<Map<String, dynamic>> get members =>
      (room?['members'] as List? ?? []).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get messages =>
      (room?['messages'] as List? ?? []).cast<Map<String, dynamic>>();
  Map<String, dynamic>? get me {
    for (final member in members) {
      if (member['id'] == user?['id']) return member;
    }
    return null;
  }

  Future<bool> perform(Future<void> Function() action) async {
    if (busy) return false;
    busy = true;
    error = null;
    _generation++;
    notifyListeners();
    try {
      await action();
      return true;
    } on ApiException catch (e) {
      error = e.message;
      if (e.status == 401 && user != null) _clear();
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> authenticate(String email, String password, String? name) =>
      perform(() async {
        final result = await api.request(
          name == null ? '/login' : '/register',
          {'email': email, 'password': password, 'name': name},
        );
        api.token = result['token'] as String;
        user = result['user'] as Map<String, dynamic>;
      });

  Future<bool> join(String mode, {String? code}) => perform(() async {
    final path = mode == 'join'
        ? '/join'
        : mode == 'random'
        ? '/random'
        : '/rooms';
    room = await api.request(path, {'kind': mode, 'code': code});
    connectionError = null;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  });

  Future<void> refresh() async {
    if (room == null || busy || _polling || _disposed) return;
    _polling = true;
    final generation = _generation;
    try {
      final updated = await api.request('/room');
      if (!_disposed && generation == _generation) {
        room = updated;
        connectionError = null;
      }
    } on ApiException catch (e) {
      if (!_disposed && generation == _generation) {
        connectionError = e.message;
        if (e.status == 401) _clear();
        if (e.status == 404) {
          room = null;
          _timer?.cancel();
          error = e.message;
        }
      }
    } finally {
      _polling = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> send(String body) => perform(() async {
    room = await api.request('/messages', {'body': body});
    connectionError = null;
  });
  Future<bool> setBreak({
    required bool active,
    int seconds = 300,
    bool share = true,
  }) => perform(() async {
    room = await api.request('/break', {
      'active': active,
      'seconds': seconds,
      'share': share,
    });
    connectionError = null;
  });
  Future<bool> leave() => perform(() async {
    await api.request('/leave', {});
    room = null;
    connectionError = null;
    _timer?.cancel();
  });
  Future<bool> logout() => perform(() async {
    await api.request('/logout', {});
    _clear();
  });
  void _clear() {
    _timer?.cancel();
    room = null;
    user = null;
    api.token = null;
    connectionError = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    api.client.close();
    super.dispose();
  }
}
