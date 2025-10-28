import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:run_walk_app/run_tracker_wear.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:run_walk_app/widgets/main_scaffold_wear.dart';
import 'package:run_walk_app/login_wear_page.dart';
import 'package:run_walk_app/service/wear_offline_sync_service.dart';



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
import 'package:run_walk_app/profile_page.dart';
import 'package:run_walk_app/complete_profile_page.dart';
import 'package:run_walk_app/run_tracker.dart';

// 🔹 Página leve do Wear OS (só texto)
import 'package:run_walk_app/wear_tutorial_page.dart'; // você vai criar logo abaixo 👇


// ------------------------------------------------------------
// 🔹 DETECÇÃO DE WEAR OS
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
// 🔹 MAIN
// ------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final bool isWear = await isWearOS();

  if (!isWear) {


    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    await initializeBackgroundTracking();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'isOnline': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await GamificationService().syncNow();
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
  @override
  void initState() {
    super.initState();

    Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        try {
          GamificationService().syncNow();
          AchievementService().syncNow();
        } catch (e) {
          debugPrint("Erro ao sincronizar automaticamente: $e");
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Empire Of The Run',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.orange,
        scaffoldBackgroundColor: Colors.black,
      ),
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
        '/perfil': (context) => const ProfilePage(),
        '/tracker_wear': (context) => const RunTrackerWearPage(),
        '/login_wear': (context) => const LoginWearPage(),

      },
    );
  }
}
