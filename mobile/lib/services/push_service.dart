import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/backend.dart';

/// Receives Firebase Cloud Messaging pushes and keeps the server informed of
/// this device's FCM token.
///
/// Firebase is optional: if the app was built without Firebase config files
/// (google-services.json / GoogleService-Info.plist), initialization fails
/// quietly and the app relies on the in-app notification inbox instead.
class PushService {
  bool _available = false;
  Future<void>? _ready;
  String? _token;
  StreamSubscription<String>? _refreshSub;

  /// Foreground messages, so the UI can show a snackbar.
  final foregroundMessages = StreamController<RemoteMessage>.broadcast();

  /// Starts Firebase in the background; never blocks or fails app startup.
  Future<void> init() => _ready ??= _init();

  Future<void> _init() async {
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 10));
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      FirebaseMessaging.onMessage.listen(foregroundMessages.add);
      _available = true;
    } catch (e) {
      debugPrint('Push notifications disabled: $e');
    }
  }

  String get _platform => kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'unknown'));

  Future<void> registerWithBackend(Backend backend) async {
    await init();
    if (!_available) return;
    try {
      _token = await FirebaseMessaging.instance.getToken();
      if (_token != null) await backend.registerDeviceToken(_token!, _platform);
      await _refreshSub?.cancel();
      _refreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        _token = t;
        backend.registerDeviceToken(t, _platform).ignore();
      });
    } catch (e) {
      debugPrint('Could not register FCM token: $e');
    }
  }

  Future<void> unregisterFromBackend(Backend backend) async {
    await _refreshSub?.cancel();
    _refreshSub = null;
    if (_token == null) return;
    try {
      await backend.removeDeviceToken(_token!);
    } catch (_) {
      // Best effort; the server also prunes dead tokens when FCM rejects them.
    }
  }
}
