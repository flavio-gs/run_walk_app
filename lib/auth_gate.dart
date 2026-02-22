import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:run_walk_app/service/version_service.dart';
import 'package:run_walk_app/login_page.dart';
import 'package:run_walk_app/widgets/main_scaffold.dart';
import 'package:run_walk_app/complete_profile_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: VersionService.versionStream(),
      builder: (context, versionSnapshot) {

        if (!versionSnapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final mustUpdate = versionSnapshot.data!;

        if (mustUpdate) {
          return const ForceUpdateScreen();
        }

        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return LoginPage();
            }

            return ProfileCompletionChecker(user: snapshot.data!);
          },
        );
      },
    );
  }
}

class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.system_update, size: 80, color: Colors.orange),
              SizedBox(height: 20),
              Text(
                "Atualização obrigatória 🚀",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              Text(
                "Para continuar usando o Império da Corrida, atualize o app na Play Store.",
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProfileCompletionChecker extends StatefulWidget {
  final User user;
  const ProfileCompletionChecker({super.key, required this.user});

  @override
  State<ProfileCompletionChecker> createState() =>
      _ProfileCompletionCheckerState();
}

class _ProfileCompletionCheckerState
    extends State<ProfileCompletionChecker> {
  late Future<DocumentSnapshot<Map<String, dynamic>>> _future;

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadAndEnsureActive() async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid);

    var snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        'uid': widget.user.uid,
        'email': widget.user.email,
        'photoURL': widget.user.photoURL ?? '',
        'username': '',
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      snap = await ref.get();
    }

    final data = snap.data() ?? {};

    if ((data['isActive'] ?? true) == false) {
      await ref.update({
        'isActive': true,
        'reactivatedAt': FieldValue.serverTimestamp(),
      });

      snap = await ref.get();
    }

    return snap;
  }

  @override
  void initState() {
    super.initState();
    _future = _loadAndEnsureActive();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError) {
          return const Scaffold(
              body: Center(child: Text('Algo deu errado!')));
        }

        final doc = snapshot.data!;
        if (!doc.exists) {
          return const CompleteProfilePage();
        }

        final data = doc.data() ?? {};

        final camposObrigatorios = [
          data['username'],
          data['displayName'],
          data['birthDate'],
          data['gender'],
          data['weight'],
          data['height'],
          data['cep'],
        ];

        final perfilIncompleto = camposObrigatorios.any(
              (valor) =>
          valor == null ||
              (valor is String && valor.trim().isEmpty) ||
              (valor is num && valor == 0),
        );

        if (perfilIncompleto) {
          return const CompleteProfilePage();
        }

        return const MainScaffold();
      },
    );
  }
}