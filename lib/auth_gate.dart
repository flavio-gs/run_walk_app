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

class ProfileCompletionChecker extends StatelessWidget {
  final User user;
  const ProfileCompletionChecker({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      // Verifica se o documento do usuário existe na coleção 'users'
      future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
      builder: (context, snapshot) {
        // Enquanto está verificando, mostra um loader
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Se deu erro na verificação
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Algo deu errado!')),
          );
        }

        // Se o documento NÃO EXISTE, o perfil está incompleto.
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const CompleteProfilePage();
        }

        // Se o documento existe, o perfil está completo. Vá para a Tela de atividades.
        return const MainScaffold();
      },
    );
  }
}
