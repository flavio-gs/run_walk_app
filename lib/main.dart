import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

// Suas páginas
import 'package:run_walk_app/feed_page.dart';
import 'package:run_walk_app/historico_page.dart';
import 'package:run_walk_app/login_page.dart';
import 'package:run_walk_app/profile_page.dart';
import 'package:run_walk_app/complete_profile_page.dart';
import 'package:run_walk_app/run_tracker.dart';
import 'package:run_walk_app/widgets/main_scaffold.dart';
import 'package:run_walk_app/auth_gate.dart';
import 'package:run_walk_app/splash_page.dart';

// Serviço de gamificação
import 'package:run_walk_app/service/service/gamification_service.dart';
import 'package:run_walk_app/service/achievement_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // 🔹 Marca o usuário online assim que o app abrir (se já estiver logado)
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'isOnline': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Sincroniza pontos assim que o app abre
  await GamificationService().syncNow();

  // Inicia o app
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    // 🛰️ Listener para sincronizar automaticamente quando a internet voltar
    Connectivity().onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        GamificationService().syncNow(context: context);
        AchievementService().syncNow(context: context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Empire Of The Run',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: const SplashPage(), // ⬅️ começa pelo vídeo
      routes: {
        '/main': (context) => const MainScaffold(),
        '/complete_profile': (context) => const CompleteProfilePage(),
        '/feed': (context) => const FeedPage(),
        '/tracker': (context) => const RunTrackingPage(),
        '/login': (context) => const LoginPage(),
        '/historico': (context) => const HistoricoPage(),
        '/perfil': (context) => const ProfilePage(),
      },
    );

  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Corrida & Caminhada')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/tracker'),
              child: const Text('Iniciar Rastreamento'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/historico'),
              child: const Text('Ver Histórico'),
            ),
          ],
        ),
      ),
    );
  }
}
