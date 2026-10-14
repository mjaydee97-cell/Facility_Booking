import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../models/models.dart';
import '../services/push_service.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState extends ChangeNotifier {
  AuthState(this._backend, this._push) {
    _backend.client.onUnauthorized = () => logout();
  }

  static const _tokenKey = 'auth_token';

  final Backend _backend;
  final PushService _push;
  final _storage = const FlutterSecureStorage();

  AuthStatus status = AuthStatus.unknown;
  User? user;

  /// Restores a saved session on app start.
  Future<void> restore() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null) {
      _set(AuthStatus.signedOut, null);
      return;
    }
    _backend.client.token = token;
    try {
      _set(AuthStatus.signedIn, await _backend.me());
      _push.registerWithBackend(_backend);
    } on ApiException catch (e) {
      // Expired token: forget it. Otherwise (e.g. offline) keep it for next launch.
      if (e.statusCode == 401) await _clear();
      _set(AuthStatus.signedOut, null);
    }
  }

  Future<void> login(String email, String password) =>
      _signIn(_backend.login(email.trim(), password));

  Future<void> register(String name, String email, String password) =>
      _signIn(_backend.register(name.trim(), email.trim(), password));

  Future<void> _signIn(Future<({String token, User user})> request) async {
    final result = await request;
    _backend.client.token = result.token;
    await _storage.write(key: _tokenKey, value: result.token);
    _set(AuthStatus.signedIn, result.user);
    _push.registerWithBackend(_backend);
  }

  Future<void> logout() async {
    if (status != AuthStatus.signedIn) return;
    await _push.unregisterFromBackend(_backend);
    await _clear();
    _set(AuthStatus.signedOut, null);
  }

  Future<void> _clear() async {
    _backend.client.token = null;
    await _storage.delete(key: _tokenKey);
  }

  void _set(AuthStatus s, User? u) {
    status = s;
    user = u;
    notifyListeners();
  }
}
