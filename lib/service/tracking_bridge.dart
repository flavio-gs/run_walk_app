import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

class TrackingBridge {
  static const _channel = MethodChannel('run_tracker/methods');
  static const _eventChannel = EventChannel('run_tracker/events');

  static Stream<Map<String, dynamic>> get trackingStream {
    return _eventChannel.receiveBroadcastStream().map((event) => Map<String, dynamic>.from(event));
  }

  static Future<void> startService() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _channel.invokeMethod('startTracking', {
        'userId': user.uid,
      });
    } on PlatformException catch (e) {
      print("Erro ao iniciar nativo: ${e.message}");
    }
  }

  static Future<void> stopService() async {
    try {
      await _channel.invokeMethod('stopTracking');
    } on PlatformException catch (e) {
      print("Erro ao parar nativo: ${e.message}");
    }
  }
}
