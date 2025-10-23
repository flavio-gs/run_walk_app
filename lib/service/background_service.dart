import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Inicializa o serviço que rodará em segundo plano
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      foregroundServiceNotificationId: 123,
      notificationChannelId: 'run_tracking_channel',
      initialNotificationTitle: 'Run Walk App',
      initialNotificationContent: 'Rastreamento ativo...',
    ),
    iosConfiguration: IosConfiguration(), // requerido, mas não usado aqui
  );
}

/// Função executada em segundo plano
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;

  if (service is AndroidServiceInstance) {
    service.on('stopService').listen((event) {
      service.stopSelf();
    });
  }

  // Atualiza localização a cada 10 segundos
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    // Verifica se o serviço ainda está rodando
    if (service is AndroidServiceInstance && !await service.isForegroundService()) {
      timer.cancel();
      return;
    }

    // Pega a posição atual (API Geolocator 10.x)
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    final user = auth.currentUser;
    if (user != null) {
      await firestore.collection('corridas_ativas').doc(user.uid).set({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  });
}
