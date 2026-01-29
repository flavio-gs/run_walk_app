import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:run_walk_app/complete_profile_page.dart';
import 'package:run_walk_app/feed_page.dart'; // Sua tela de Feed
import 'package:run_walk_app/login_page.dart';
import 'package:run_walk_app/run_tracker.dart';
import 'package:run_walk_app/widgets/main_scaffold.dart'; // Sua tela de Login

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Se o usuário não está logado, mostra a tela de login.
        if (!snapshot.hasData) {
          return LoginPage(); // Substitua pelo nome correto da sua página de login
        }

        // Se o usuário está logado, verifica se o perfil está completo.
        return ProfileCompletionChecker(user: snapshot.data!);
      },
    );
  }
}

class ProfileCompletionChecker extends StatefulWidget {
  final User user;
  const ProfileCompletionChecker({super.key, required this.user});

  @override
  State<ProfileCompletionChecker> createState() => _ProfileCompletionCheckerState();
}

class _ProfileCompletionCheckerState extends State<ProfileCompletionChecker> {
  late Future<DocumentSnapshot<Map<String, dynamic>>> _future;

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadAndEnsureActive() async {
    final ref = FirebaseFirestore.instance.collection('users').doc(widget.user.uid);
    var snap = await ref.get();

    // cria doc se não existir
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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return const Scaffold(body: Center(child: Text('Algo deu errado!')));
        }
        final doc = snapshot.data!;
        if (!doc.exists) {
          return const CompleteProfilePage();
        }

        // Checagem de perfil completo (mesma lógica que você já usa)
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

