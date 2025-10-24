import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';


/// Instâncias globais
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel runnerChannel = AndroidNotificationChannel(
  'runner_tracking',
  'Rastreamento em segundo plano',
  description: 'Notificações do serviço de corrida em segundo plano',
  importance: Importance.low,
);

/// Inicializa canal + serviço de rastreamento
Future<void> initializeBackgroundTracking() async {
  final service = FlutterBackgroundService();

  debugPrint("🟢 [Init] Configurando serviço de rastreamento...");

  // ✅ Permissão de notificação (Android 13+)
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }

  // ✅ Criação manual do canal de notificação
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: android);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(runnerChannel);

  debugPrint("📣 [Init] Canal runner_tracking criado com sucesso!");

  // ✅ Configuração do serviço
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStartBackgroundTracking,
      autoStart: false,
      isForegroundMode: true,
      foregroundServiceNotificationId: 777,
      notificationChannelId: 'runner_tracking',
      initialNotificationTitle: '🏃 Corrida em andamento',
      initialNotificationContent: 'Rastreamento ativo...',
      // ⚠️ Não tem mais parâmetro de ícone na v5.x
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStartBackgroundTracking,
    ),
  );

  debugPrint("✅ [Init] Serviço configurado com sucesso!");
}

@pragma('vm:entry-point')
Future<void> onStartBackgroundTracking(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // ✅ ESSA LINHA É OBRIGATÓRIO NO ISOLATE
  debugPrint("🚀 [Service] Serviço iniciado com sucesso!");

  try {
    await Geolocator.requestPermission();
    debugPrint("📡 [Permissão] Permissão de localização verificada.");
  } catch (e) {
    debugPrint("⚠️ [Permissão] Erro ao pedir permissão: $e");
  }

  // 🔸 Atualiza uma notificação padrão segura assim que o serviço inicia
  final android = AndroidNotificationDetails(
    runnerChannel.id,
    runnerChannel.name,
    channelDescription: runnerChannel.description,
    importance: Importance.low,
    priority: Priority.low,
    icon: '@mipmap/ic_launcher', // ícone válido pro Android 14
  );

  final notificationDetails = NotificationDetails(android: android);

  await flutterLocalNotificationsPlugin.show(
    777,
    '🏃 Corrida iniciada',
    'Serviço de rastreamento ativo',
    notificationDetails,
  );


  Position? lastPosition;

  double totalDistance = 0.0; // em metros
  int totalSeconds = 0;
  double totalCalories = 0.0;
  DateTime startTime = DateTime.now();

  // Permite parar o serviço externamente
  service.on('stopService').listen((_) {
    debugPrint("🛑 [Service] Parando serviço.");
    service.stopSelf();
  });

  // Executa a cada 5 segundos
  Timer.periodic(const Duration(seconds: 5), (timer) async {
    totalSeconds += 5; // cada tick = 5 segundos
    debugPrint("⏱ [Timer] Tick — verificando posição...");

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Distância desde a última posição
      if (lastPosition != null) {
        final distance = Geolocator.distanceBetween(
          lastPosition!.latitude,
          lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );

        // Ignora pequenas variações
        if (distance >= 3) {
          totalDistance += distance;
          // Estimativa básica de calorias (~1 kcal por 15 metros p/ pessoa média)
          totalCalories = totalDistance / 15;
        }
      }

      lastPosition = position;

      // Calcula pace (min/km)
      double pace = 0;
      if (totalDistance > 0) {
        final minutes = totalSeconds / 60;
        final km = totalDistance / 1000;
        pace = minutes / km;
      }

      // Atualiza no Firestore (opcional)
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'lat': position.latitude,
        'lng': position.longitude,
        'updatedAt': FieldValue.serverTimestamp(),
        'distance_m': totalDistance,
        'kcal': totalCalories,
        'pace_min_km': pace,
      });

      // Atualiza notificação
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
