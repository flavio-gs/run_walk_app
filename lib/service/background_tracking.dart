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
  double pace = 0.0;
  List<Map<String, double>> path = [];
  DateTime? startTime;
  bool isPaused = false;

  StreamSubscription<Position>? positionStream;

  void startTracking() {
    startTime ??= DateTime.now();
    positionStream?.cancel();
    positionStream = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "Rastreando sua corrida em segundo plano...",
          notificationTitle: "🏃 Runner Ativo",
          enableWakeLock: true,
        ),
      ),
    ).listen((position) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final currentPoint = {"lat": position.latitude, "lng": position.longitude};
      if (path.isEmpty || 
          path.last['lat'] != position.latitude || 
          path.last['lng'] != position.longitude) {
        path.add(currentPoint);
      }

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
          
          if (totalDistance > 0 && totalSeconds > 0) {
            final minutes = totalSeconds / 60;
            final km = totalDistance / 1000;
            pace = minutes / km;
          }
        }
      }
      lastPosition = position;

      // Envia atualização para a UI
      service.invoke('update', {
        "distance": totalDistance,
        "seconds": totalSeconds,
        "calories": totalCalories,
        "pace": pace,
        "latitude": position.latitude,
        "longitude": position.longitude,
        "path": path,
        "startTime": startTime?.toIso8601String(),
        "isPaused": isPaused,
      });

      // Atualiza a notificação (Android)
      if (service is AndroidServiceInstance) {
        final kmStr = (totalDistance / 1000).toStringAsFixed(2);
        final paceMin = pace.floor();
        final paceSec = ((pace - paceMin) * 60).round().toString().padLeft(2, '0');

        service.setForegroundNotificationInfo(
          title: '🏃 Corrida em andamento',
          content: 'Distância: ${kmStr} km • Pace: ${paceMin}\'${paceSec}\"/km',
        );
      }
    });
  }

  service.on('stopService').listen((_) {
    debugPrint("🛑 [Service] Parando serviço.");
    positionStream?.cancel();
    service.stopSelf();
  });

  service.on('pauseService').listen((_) {
    isPaused = true;
    positionStream?.pause();
    debugPrint("⏸ [Service] Tracking pausado.");
  });

  service.on('resumeService').listen((_) {
    isPaused = false;
    positionStream?.resume();
    debugPrint("▶️ [Service] Tracking retomado.");
  });

  service.on('request_state').listen((_) {
    service.invoke('update', {
      "distance": totalDistance,
      "seconds": totalSeconds,
      "calories": totalCalories,
      "pace": pace,
      "latitude": lastPosition?.latitude,
      "longitude": lastPosition?.longitude,
      "path": path,
      "startTime": startTime?.toIso8601String(),
      "isPaused": isPaused,
    });
  });

  startTracking();

  // Timer apenas para o cronômetro (segundos)
  Timer.periodic(const Duration(seconds: 1), (timer) {
    if (!isPaused) {
      totalSeconds++;
      
      // Opcional: a cada 10s atualiza o firestore se necessário
      if (totalSeconds % 10 == 0 && lastPosition != null) {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
               FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                  'lat': lastPosition!.latitude,
                  'lng': lastPosition!.longitude,
                  'updatedAt': FieldValue.serverTimestamp(),
                  'distance_m': totalDistance,
                  'kcal': totalCalories,
                  'pace_min_km': pace,
                }).catchError((e) => debugPrint("Erro firestore bg: $e"));
          }
      }
    }
  });
}
