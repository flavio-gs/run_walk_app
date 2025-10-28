import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class LoginWearPage extends StatefulWidget {
  const LoginWearPage({super.key});

  @override
  State<LoginWearPage> createState() => _LoginWearPageState();
}

class _LoginWearPageState extends State<LoginWearPage> {
  bool loading = false;
  String mensagem = '';

  Future<void> _signInWithGoogle() async {
    if (Firebase.apps.isEmpty) {
      setState(() => mensagem = "📴 Modo offline — conecte-se via app principal.");
      return;
    }

    setState(() {
      loading = true;
      mensagem = '';
    });

    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCred.user;
      if (user == null) return;

      // 🔹 Cria documento se necessário
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await ref.get();
      if (!snap.exists) {
        await ref.set({
          'uid': user.uid,
          'email': user.email,
          'photoURL': user.photoURL ?? '',
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/main_wear');
      }
    } catch (e) {
      setState(() => mensagem = "Erro: $e");
    } finally {
      setState(() => loading = false);
    }
  }

  void _continueOffline() {
    // 🔹 Apenas navega direto para o app sem login
    Navigator.pushReplacementNamed(context, '/main_wear');
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 10),
                // 🔹 Logo pequena
                Image.asset(
                  'assets/icon/logo_principal.png',
                  height: 60,
                ),
                const SizedBox(height: 14),
                const Text(
                  "Empire of The Run",
                  style: TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                // 🔹 Botão Google
                SizedBox(
                  width: 120,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: _signInWithGoogle,
                    child: const Text(
                      "Entrar com Google",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _continueOffline,
                  child: const Text(
                    "Entrar offline",
                    style: TextStyle(color: Colors.white70, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

  }
}
