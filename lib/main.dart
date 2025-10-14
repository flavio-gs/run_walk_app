import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:run_walk_app/login_page.dart';
import 'run_tracker.dart';

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
      home: const LoginPage(),
      routes: {
        '/tracker': (context) => const RunTrackingPage(),
        '/login': (context) => const LoginPage()
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
