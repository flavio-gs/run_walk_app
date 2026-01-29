import 'dart:async';
import 'package:flutter/services.dart';

class HealthWearService {
  static const _m = MethodChannel('wear_health');
  static const _e = EventChannel('wear_health/metrics');

  static Future<bool> isAvailable() async {
    try {
      final ok = await _m.invokeMethod<bool>('isAvailable');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> start() async {
    try {
      final ok = await _m.invokeMethod<bool>('startExercise');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await _m.invokeMethod('stopExercise');
    } catch (_) {}
  }

  static Stream<Map<String, dynamic>> metricsStream() {
    return _e.receiveBroadcastStream().map((event) {
      return Map<String, dynamic>.from(event as Map);
    });
  }
}
