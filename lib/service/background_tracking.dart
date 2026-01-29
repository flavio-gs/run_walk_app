import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel runnerChannel = AndroidNotificationChannel(
  'runner_tracking',
  'Rastreamento em segundo plano',
  description: 'Notificações do serviço de corrida em segundo plano',
  importance: Importance.low,
);

/// 🔹 Detecta Wear OS de forma segura
Future<bool> _isWearOS() async {
  try {
    if (!Platform.isAndroid) return false;
    final info = await DeviceInfoPlugin().androidInfo;
    return info.systemFeatures.contains('android.hardware.type.watch');
  } catch (_) {
    return false;
  }
}

/// 🔹 Inicializa o serviço (ignorado no Wear OS)
Future<void> initializeBackgroundTracking() async {
  // ⚠️ Não use plugins de notificação no Wear OS
  final isWear = await _isWearOS();
  if (isWear) {
    debugPrint("⌚ [Init] Wear OS detectado — rastreamento desativado.");
    return;
  }

  final service = FlutterBackgroundService();

  debugPrint("🟢 [Init] Configurando serviço de rastreamento...");

  try {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await flutterLocalNotificationsPlugin.initialize(initSettings);

    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(runnerChannel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStartBackgroundTracking,
        autoStart: false,
        isForegroundMode: true,
        foregroundServiceNotificationId: 777,
        notificationChannelId: 'runner_tracking',
        initialNotificationTitle: '🏃 Corrida em andamento',
        initialNotificationContent: 'Rastreamento ativo...',
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStartBackgroundTracking,
      ),
    );

    debugPrint("✅ [Init] Serviço configurado com sucesso!");
  } catch (e) {
    debugPrint("⚠️ [Init] Erro ao iniciar serviço: $e");
  }
}

@pragma('vm:entry-point')
Future<void> onStartBackgroundTracking(ServiceInstance service) async {
  // 🚫 Ignora completamente no Wear OS
  final isWear = await _isWearOS();
  if (isWear) {
    debugPrint("⌚ [Service] Wear OS detectado — serviço não iniciado.");
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (_) {
    debugPrint("⚠️ [Service] Firebase já estava inicializado.");
  }

  debugPrint("🚀 [Service] Serviço iniciado com sucesso!");

  try {
    await Geolocator.requestPermission();
  } catch (e) {
    debugPrint("⚠️ [Permissão] Erro ao pedir permissão: $e");
  }

  Position? lastPosition;
  double totalDistance = 0.0;
  int totalSeconds = 0;
  double totalCalories = 0.0;

  service.on('stopService').listen((_) {
    debugPrint("🛑 [Service] Parando serviço.");
    service.stopSelf();
  });

  Timer.periodic(const Duration(seconds: 5), (timer) async {
    totalSeconds += 5;
    debugPrint("⏱ [Timer] Tick — verificando posição...");

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (lastPosition != null) {
        final distance = Geolocator.distanceBetween(
          lastPosition!.latitude,
          lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );

        if (distance >= 3) {
          totalDistance += distance;
          totalCalories = totalDistance / 15;
        }
      }
      lastPosition = position;

      double pace = 0;
      if (totalDistance > 0) {
        final minutes = totalSeconds / 60;
        final km = totalDistance / 1000;
        pace = minutes / km;
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'lat': position.latitude,
        'lng': position.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
        'distance_m': totalDistance,
        'kcal': totalCalories,
        'pace_min_km': pace,
      });

      if (service is AndroidServiceInstance) {
        final kmStr = (totalDistance / 1000).toStringAsFixed(2);
        final kcalStr = totalCalories.toStringAsFixed(0);
        final paceMin = pace.floor();
        final paceSec = ((pace - paceMin) * 60).round().toString().padLeft(2, '0');

        await service.setForegroundNotificationInfo(
          title: '🏃 Corrida ativa',
          content:
          'Distância: ${kmStr} km • ${kcalStr} kcal • Pace: ${paceMin}\'${paceSec}\"/km',
        );
      }

      debugPrint("🧭 [Firestore] Localização e métricas atualizadas!");
    } catch (e) {
      debugPrint("❌ [Erro] Falha no tracking: $e");
    }
  });
}
