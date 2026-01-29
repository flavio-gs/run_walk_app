import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:run_walk_app/run_tracker_wear.dart';
import 'package:run_walk_app/theme/season_theme_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:run_walk_app/widgets/main_scaffold_wear.dart';
import 'package:run_walk_app/login_wear_page.dart';
import 'package:run_walk_app/service/wear_offline_sync_service.dart';

import 'package:run_walk_app/service/season_service.dart';
import 'dart:math';
import 'package:flutter/material.dart';

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

// ✅ SPLASH (vídeo)
import 'package:run_walk_app/splash_page.dart';


// ------------------------------------------------------------
// 🔹 CHAVE GLOBAL (Permite Navegar de handlers de FCM)
// ------------------------------------------------------------
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Plugin para Notificações Locais (necessário para Foreground)
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();


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
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/perfil',
          (route) => route.settings.name == '/main',
      arguments: senderId,
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

  const NotificationDetails platformDetails =
  NotificationDetails(android: androidDetails);

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
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
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
    // ✅ Continua igual: se não viu tutorial -> tutorial (e ao finalizar, ele vai pro splash)
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

  final _seasonService = SeasonService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SeasonConfig?>(
      stream: _seasonService.activeSeasonStream(),
      builder: (context, snapshot) {
        final season = snapshot.data;
        final t = season?.theme ?? {};

        // Fallbacks (teu tema atual)
        final primary = parseHslToColor(t['primary']) ?? const Color(0xFFFF7A00);
        final bg = parseHslToColor(t['background']) ?? Colors.black;
        final card = parseHslToColor(t['card']) ?? const Color(0xFF12121A);
        final fg = parseHslToColor(t['foreground']) ?? Colors.white;

        final themeData = ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: primary).copyWith(
            surface: bg,
            onSurface: fg,
          ),
          scaffoldBackgroundColor: bg,
          cardColor: card,
          appBarTheme: AppBarTheme(
            backgroundColor: bg,
            foregroundColor: fg,
          ),
        );

        final seasonTheme = buildSeasonTheme(t);

        return SeasonThemeScope(
          theme: seasonTheme,
          child: MaterialApp(
            title: 'Empire Of The Run',
            debugShowCheckedModeBanner: false,
            theme: themeData,
            navigatorKey: navigatorKey,
            home: widget.initialPage,
            routes: {
              '/tutorial': (context) => const MapTutorialPage(),
              '/splash': (context) => const SplashPage(),
              '/main': (context) => const MainScaffold(),
              '/main_wear': (context) => const MainScaffoldWear(),
              '/complete_profile': (context) => const CompleteProfilePage(),
              '/feed': (context) => const FeedPage(),
              '/tracker': (context) => const RunTrackingPage(),
              '/login': (context) => const LoginPage(),
              '/historico': (context) => const HistoricoPage(),
              '/perfil': (context) {
                final userId =
                ModalRoute.of(context)?.settings.arguments as String?;
                return ProfilePage(
                  userId: userId ?? FirebaseAuth.instance.currentUser!.uid,
                );
              },
              '/tracker_wear': (context) => const RunTrackerWearPage(),
              '/login_wear': (context) => const LoginWearPage(),
            },
          ),
        );

      },
    );
  }

  SeasonTheme buildSeasonTheme(Map<String, dynamic> t) {
    Color c(String key, Color fallback) =>
        parseHslToColor(t[key]) ?? fallback;

    return SeasonTheme(
      accent: c('accent', const Color(0xFFFF7A00)),
      accentForeground: c('accentForeground', Colors.black),
      background: c('background', Colors.black),
      border: c('border', Colors.white12),
      card: c('card', const Color(0xFF12121A)),
      cardForeground: c('cardForeground', Colors.white),
      destructive: c('destructive', Colors.redAccent),
      destructiveForeground: c('destructiveForeground', Colors.white),
      foreground: c('foreground', Colors.white),
      input: c('input', const Color(0xFF12121A)),
      muted: c('muted', Colors.white24),
      mutedForeground: c('mutedForeground', Colors.white60),
      popover: c('popover', const Color(0xFF12121A)),
      popoverForeground: c('popoverForeground', Colors.white),
      primary: c('primary', const Color(0xFFFF7A00)),
      primaryForeground: c('primaryForeground', Colors.black),
      ring: c('ring', const Color(0xFFFF7A00)),
      secondary: c('secondary', Colors.blueGrey),
      secondaryForeground: c('secondaryForeground', Colors.black),
    );
  }



  Color? parseHslToColor(dynamic value) {
    if (value == null || value is! String) return null;

    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.length < 3) return null;

    final h = double.tryParse(parts[0]);
    final s = double.tryParse(parts[1].replaceAll('%', ''));
    final l = double.tryParse(parts[2].replaceAll('%', ''));

    if (h == null || s == null || l == null) return null;

    final hh = h % 360;
    final ss = (s / 100).clamp(0.0, 1.0);
    final ll = (l / 100).clamp(0.0, 1.0);

    return _hslToColor(hh, ss, ll);
  }

  Color _hslToColor(double h, double s, double l) {
    final c = (1 - (2 * l - 1).abs()) * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = l - c / 2;

    double r = 0, g = 0, b = 0;
    if (h < 60) { r = c; g = x; }
    else if (h < 120) { r = x; g = c; }
    else if (h < 180) { g = c; b = x; }
    else if (h < 240) { g = x; b = c; }
    else if (h < 300) { r = x; b = c; }
    else { r = c; b = x; }

    int to255(double v) => ((v + m) * 255).round().clamp(0, 255);
    return Color.fromARGB(255, to255(r), to255(g), to255(b));
  }
}
