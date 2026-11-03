import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/config/env.dart';
import '../../data/datasources/firebase/functions_api.dart';

/// Registers this phone for push notifications and shows foreground messages.
class PushService {
  PushService(this._api, this._messengerKey);

  final FunctionsApi _api;
  final GlobalKey<ScaffoldMessengerState> _messengerKey;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _messageSub;
  String? _token;

  Future<void> start() async {
    // FCM isn't available in the emulator suite, and web push needs extra setup.
    if (Env.useEmulator || kIsWeb) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      _token = await messaging.getToken();
      if (_token != null) await _api.call('registerFcmToken', {'token': _token});
      _tokenSub ??= messaging.onTokenRefresh.listen((t) {
        _token = t;
        _api.call('registerFcmToken', {'token': t}).ignore();
      });
      _messageSub ??= FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n == null) return;
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text([n.title, n.body].whereType<String>().join(': '))),
        );
      });
    } catch (e) {
      debugPrint('Push setup failed: $e');
    }
  }

  /// Call before signing out so the next user of this phone doesn't get these notifications.
  Future<void> stop() async {
    await _tokenSub?.cancel();
    await _messageSub?.cancel();
    _tokenSub = null;
    _messageSub = null;
    final token = _token;
    _token = null;
    if (token != null) {
      try {
        await _api.call('unregisterFcmToken', {'token': token});
      } catch (_) {}
    }
  }
}
