import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:run_walk_app/run_tracker_wear.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:run_walk_app/widgets/main_scaffold_wear.dart';
import 'package:run_walk_app/login_wear_page.dart';
import 'package:run_walk_app/service/wear_offline_sync_service.dart';

// 🚨 NOVOS IMPORTS PARA FCM
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';


// 🔹 Serviços
import 'package:run_walk_app/service/background_tracking.dart';
import 'package:run_walk_app/service/service/gamification_service.dart';
import 'package:run_walk_app/service/achievement_service.dart';

// 🔹 Páginas
import 'package:run_walk_app/auth_gate.dart';
import 'package:run_walk_app/widgets/main_scaffold.dart';
import 'package:run_walk_app/tutorial_page.dart';
import 'package:run_walk_app/feed_page.dart';
import 'package:run_walk_app/historico_page.dart';
import 'package:run_walk_app/login_page.dart';
import 'package:run_walk_app/profile_page.dart'; // NECESSÁRIO para navegação
import 'package:run_walk_app/complete_profile_page.dart';
import 'package:run_walk_app/run_tracker.dart';

// 🔹 Página leve do Wear OS (só texto)
import 'package:run_walk_app/wear_tutorial_page.dart';


// ------------------------------------------------------------
// 🔹 CHAVE GLOBAL (Permite Navegar de handlers de FCM)
// ------------------------------------------------------------
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Plugin para Notificações Locais (necessário para Foreground)
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();


// ------------------------------------------------------------
// 🔹 FCM BACKGROUND HANDLER (Top-level)
// ------------------------------------------------------------
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("📳 [FCM BG] Mensagem recebida em segundo plano.");
  // A navegação real acontece via onMessageOpenedApp/getInitialMessage
}

// ------------------------------------------------------------
// 🔹 LÓGICA DE CLIQUE E NAVEGAÇÃO
// ------------------------------------------------------------
void handlePushNotificationClick(RemoteMessage message) {
  final data = message.data;
  final senderId = data['senderId'] as String?;

  if (senderId != null) {
    debugPrint("📳 [FCM Click] Navegando para ProfilePage de ID: $senderId");
    // Navega usando a GlobalKey para ProfilePage
    // Usamos pushNamedAndRemoveUntil para limpar a pilha e garantir que a ProfilePage seja a nova rota principal
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/perfil', // Usa a rota definida no MaterialApp
          (route) => route.settings.name == '/main', // Mantém a main scaffold se necessário, ou remove tudo (false)
      arguments: senderId, // Passa o senderId como argumento
    );
  }
}

// ------------------------------------------------------------
// 🔹 FUNÇÕES AUXILIARES DE NOTIFICAÇÃO
// ------------------------------------------------------------

Future<void> initializeLocalNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

void showLocalNotification(RemoteMessage message) {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'high_importance_channel', // Deve coincidir com o AndroidManifest
    'Notificações Importantes',
    channelDescription: 'Canal para notificações de atividade do app.',
    importance: Importance.max,
    priority: Priority.high,
  );

  const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

  flutterLocalNotificationsPlugin.show(
    0,
    message.notification!.title,
    message.notification!.body,
    platformDetails,
    payload: message.data.toString(),
  );
}


Future<void> setupFCM() async {
  if (await isWearOS()) return; // Não faz o setup do FCM no Wear OS

  final fcm = FirebaseMessaging.instance;

  // 1. Requisitar Permissão e Setup de Notificações Locais
  await fcm.requestPermission(alert: true, badge: true, sound: true);
  await initializeLocalNotifications();

  // 2. Salvar o Token FCM
  final user = FirebaseAuth.instance.currentUser;
  String? token = await fcm.getToken();

  if (user != null && token != null) {
    await FirebaseFirestore.instance.collection('users').doc(user.uid)
        .set({'fcmToken': token}, SetOptions(merge: true));
  }

  // 3. HANDLER PARA APP FECHADO
  RemoteMessage? initialMessage = await fcm.getInitialMessage();
  if (initialMessage != null) {
    handlePushNotificationClick(initialMessage);
  }

  // 4. HANDLER PARA APP EM SEGUNDO PLANO (Clique na notificação)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    handlePushNotificationClick(message);
  });

  // 5. HANDLER PARA APP EM FOREGROUND (App Aberto)
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    debugPrint("📳 [FCM FG] Mensagem em foreground. Exibindo notificação local.");
    if (message.notification != null) {
      showLocalNotification(message);
    }
  });
}


// ------------------------------------------------------------
// 🔹 DETECÇÃO DE WEAR OS (Mantido)
// ------------------------------------------------------------
Future<bool> isWearOS() async {
  try {
    if (!Platform.isAndroid) return false;
    final info = await DeviceInfoPlugin().androidInfo;
    return info.systemFeatures.contains('android.hardware.type.watch');
  } catch (_) {
    return false;
  }
}

// ------------------------------------------------------------
// 🔹 MAIN (Chamada do setupFCM)
// ------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final bool isWear = await isWearOS();

  if (!isWear) {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    Future<void> ensureServiceStoppedIfNotTracking() async {
      final prefs = await SharedPreferences.getInstance();
      final isTracking = prefs.getBool('isTracking') ?? false;

      final service = FlutterBackgroundService();
      final running = await service.isRunning();

      if (!isTracking && running) {
        debugPrint("🛑 [Main] Serviço estava rodando sem corrida ativa. Parando...");
        service.invoke('stopService');
      }
    }
    await ensureServiceStoppedIfNotTracking();
    await initializeBackgroundTracking();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'isOnline': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await GamificationService().syncNow();

    // 🚨 CHAMADA PRINCIPAL DO SETUP FCM AQUI
    await setupFCM();

  } else {
    debugPrint("⌚ [Main] Wear OS detectado — inicialização leve.");
  }

  final prefs = await SharedPreferences.getInstance();
  final hasSeenTutorial = prefs.getBool('hasSeenTutorial') ?? false;

  final Widget initialPage;
  if (isWear) {
    Connectivity().onConnectivityChanged.listen((result) async {
      if (result != ConnectivityResult.none) {
        debugPrint("⌚ [Sync] Wear OS online — sincronizando dados pendentes...");
        await WearOfflineSyncService.syncPendingData();
      }
    });
    initialPage = hasSeenTutorial
        ? const LoginWearPage()
        : const WearTextTutorialPage();
  } else {
    initialPage = hasSeenTutorial ? const AuthGate() : const MapTutorialPage();
  }

  runApp(MyApp(initialPage: initialPage));
}

// ------------------------------------------------------------
// 🔹 MyApp
// ------------------------------------------------------------
class MyApp extends StatefulWidget {
  final Widget initialPage;
  const MyApp({super.key, required this.initialPage});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // ... (initState e Connectivity listen mantidos) ...

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Empire Of The Run',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.orange,
        scaffoldBackgroundColor: Colors.black,
      ),
      // 🚨 ATRIBUIÇÃO DA CHAVE GLOBAL AO NAVIGATOR
      navigatorKey: navigatorKey,
      // ---------------------------------------------
      home: widget.initialPage,
      routes: {
        '/tutorial': (context) => const MapTutorialPage(),
        '/main': (context) => const MainScaffold(),
        '/main_wear': (context) => const MainScaffoldWear(),
        '/complete_profile': (context) => const CompleteProfilePage(),
        '/feed': (context) => const FeedPage(),
        '/tracker': (context) => const RunTrackingPage(),
        '/login': (context) => const LoginPage(),
        '/historico': (context) => const HistoricoPage(),
        // 🚨 PROFILE PAGE (ATUALIZADA PARA LIDAR COM ARGUMENTOS DE ROTA)
        '/perfil': (context) {
          // Extrai o userId dos argumentos da rota, que é passado pelo Push Notification handler
          final userId = ModalRoute.of(context)?.settings.arguments as String?;
          // Se o argumento for nulo, usa o ID do usuário logado (default)
          return ProfilePage(userId: userId ?? FirebaseAuth.instance.currentUser!.uid);
        },
        // -------------------------------------------------------------------
        '/tracker_wear': (context) => const RunTrackerWearPage(),
        '/login_wear': (context) => const LoginWearPage(),
      },
    );
  }
}