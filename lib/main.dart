import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:run_walk_app/feed_page.dart';
import 'package:run_walk_app/historico_page.dart';
import 'package:run_walk_app/login_page.dart';
import 'package:run_walk_app/profile_page.dart';
import 'package:run_walk_app/complete_profile_page.dart';
import 'run_tracker.dart';
import 'widgets//main_scaffold.dart';
import 'auth_gate.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Inicializa o Firebase
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Empire Of The Run',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const AuthGate(),
      routes: {
        '/main': (context) => const MainScaffold(),
        '/complete_profile': (context) => const CompleteProfilePage(),
        '/feed': (context) => const FeedPage(),
        '/tracker': (context) => const RunTrackingPage(),
        '/login': (context) => const LoginPage(),
        '/historico': (context) => const HistoricoPage(),
        '/perfil': (context) => const ProfilePage(),
        '/feed': (context) => const FeedPage(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Corrida & Caminhada'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/tracker');
              },
              child: const Text('Iniciar Rastreamento'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pushNamed(context, '/mapa');
              },
              child: const Text('Ver Mapa com Trajeto'),
            ),
          ],
        ),
      ),
    );
  }
}
