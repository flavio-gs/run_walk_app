import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:audioplayers/audioplayers.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController senhaController = TextEditingController();

  bool loading = false;
  String mensagemErro = '';
  bool isRegistering = false;

  final AudioPlayer _player = AudioPlayer();

  void navigateToRunTrackingPage() {
    Navigator.pushReplacementNamed(context, '/main');
  }

  Future<void> _reactivateIfNeeded(String uid) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final data = snap.data() ?? {};
    final isActive = (data['isActive'] ?? true) as bool;

    if (!isActive) {
      await ref.update({
        'isActive': true,
        'reactivatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conta reativada. Bem-vindo(a) de volta!')),
        );
      }
    }
  }

  // ------------------ 🔐 LOGIN / CADASTRO -------------------
  Future<void> handleAuthAction() async {
    if (emailController.text.trim().isEmpty || senhaController.text.trim().isEmpty) {
      setState(() => mensagemErro = 'Preencha todos os campos.');
      return;
    }

    setState(() {
      loading = true;
      mensagemErro = '';
    });

    try {
      final FirebaseAuth auth = FirebaseAuth.instance;
      final userCredential = isRegistering
          ? await auth.createUserWithEmailAndPassword(
              email: emailController.text.trim(),
              password: senhaController.text.trim(),
            )
          : await auth.signInWithEmailAndPassword(
              email: emailController.text.trim(),
              password: senhaController.text.trim(),
            );

      final user = userCredential.user;
      if (user == null) return;

      await _reactivateIfNeeded(user.uid);

      final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      var userDoc = await userDocRef.get();

      if (!userDoc.exists) {
        await userDocRef.set({
          'uid': user.uid,
          'email': user.email,
          'photoURL': user.photoURL ?? '',
          'username': '',
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        userDoc = await userDocRef.get();
      }

      final data = userDoc.data() ?? {};
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
        (valor) => valor == null || (valor is String && valor.trim().isEmpty) || (valor is num && valor == 0),
      );

      if (perfilIncompleto) {
        Navigator.pushReplacementNamed(context, '/complete_profile');
      } else {
        navigateToRunTrackingPage();
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = switch (e.code) {
        'user-not-found' || 'wrong-password' => 'E-mail ou senha inválidos.',
        'email-already-in-use' => 'Este e-mail já está cadastrado.',
        _ => 'Erro: ${e.message}',
      };
      setState(() => mensagemErro = errorMessage);
    } finally {
      setState(() => loading = false);
    }
  }

  // ------------------ 🔑 LOGIN COM GOOGLE -------------------
  Future<void> signInWithGoogle() async {
    setState(() {
      loading = true;
      mensagemErro = '';
    });
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => loading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCred.user;
      if (user == null) {
        setState(() => loading = false);
        return;
      }

      await _reactivateIfNeeded(user.uid);

      final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      var userDoc = await userDocRef.get();

      if (!userDoc.exists) {
        await userDocRef.set({
          'uid': user.uid,
          'email': user.email,
          'photoURL': user.photoURL ?? '',
          'username': '',
          'displayName': user.displayName ?? '',
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        userDoc = await userDocRef.get();
      }

      final data = userDoc.data() ?? {};
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
        (valor) => valor == null || (valor is String && valor.trim().isEmpty) || (valor is num && valor == 0),
      );

      if (perfilIncompleto) {
        Navigator.pushReplacementNamed(context, '/complete_profile');
      } else {
        navigateToRunTrackingPage();
      }
    } catch (e) {
      setState(() => mensagemErro = 'Erro ao autenticar com Google: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  // ------------------ 🍎 LOGIN COM APPLE -------------------
  Future<void> signInWithApple() async {
    setState(() {
      loading = true;
      mensagemErro = '';
    });
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final OAuthProvider oAuthProvider = OAuthProvider('apple.com');
      final AuthCredential credential = oAuthProvider.credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCred.user;
      if (user == null) {
        setState(() => loading = false);
        return;
      }

      await _reactivateIfNeeded(user.uid);

      final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      var userDoc = await userDocRef.get();

      if (!userDoc.exists) {
        // Apple só envia nome e email no PRIMEIRO login
        String? displayName = user.displayName;
        if (displayName == null || displayName.isEmpty) {
          if (appleCredential.givenName != null || appleCredential.familyName != null) {
            displayName = '${appleCredential.givenName ?? ''} ${appleCredential.familyName ?? ''}'.trim();
          }
        }

        await userDocRef.set({
          'uid': user.uid,
          'email': user.email ?? appleCredential.email ?? '',
          'photoURL': user.photoURL ?? '',
          'username': '',
          'displayName': displayName ?? 'Runner',
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        userDoc = await userDocRef.get();
      }

      final data = userDoc.data() ?? {};
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
        (valor) => valor == null || (valor is String && valor.trim().isEmpty) || (valor is num && valor == 0),
      );

      if (perfilIncompleto) {
        Navigator.pushReplacementNamed(context, '/complete_profile');
      } else {
        navigateToRunTrackingPage();
      }
    } catch (e) {
      setState(() => mensagemErro = 'Erro ao autenticar com Apple: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  // ------------------ 🧱 CAMPOS -------------------
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      cursorColor: Colors.orange,
      style: const TextStyle(color: Colors.black87, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.black54),
        prefixIcon: Icon(icon, color: Colors.black87, size: 20),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.orange, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.black12, width: 1.2),
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  // ------------------ 🧩 BUILD -------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset(
                'assets/icon/logo_transp.png',
                height: 100,
              ),
              const SizedBox(height: 40),
              Text(
                isRegistering ? "Crie sua conta" : "Bem-vindo de volta!",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 30),
              _buildTextField(
                controller: emailController,
                label: "E-mail",
                icon: Icons.email_outlined,
              ),
              const SizedBox(height: 15),
              _buildTextField(
                controller: senhaController,
                label: "Senha",
                icon: Icons.lock_outline,
                obscureText: true,
              ),
              const SizedBox(height: 10),
              if (mensagemErro.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    mensagemErro,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loading ? null : handleAuthAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: loading
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : Text(
                          isRegistering ? "Cadastrar" : "Entrar",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  setState(() => isRegistering = !isRegistering);
                },
                child: Text(
                  isRegistering ? "Já tem conta? Entre" : "Não tem conta? Cadastre-se",
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
              const SizedBox(height: 25),
              const Row(
                children: [
                  Expanded(child: Divider(color: Colors.black12)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text("OU", style: TextStyle(color: Colors.black26, fontSize: 12)),
                  ),
                  Expanded(child: Divider(color: Colors.black12)),
                ],
              ),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: loading ? null : signInWithGoogle,
                  icon: const Icon(Icons.g_mobiledata, color: Colors.black87, size: 30),
                  label: const Text(
                    "Entrar com Google",
                    style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: const BorderSide(color: Colors.black12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (Platform.isIOS)
                SignInWithAppleButton(
                  text: "Continuar com Apple",
                  height: 45,
                  borderRadius: BorderRadius.circular(8),
                  onPressed: () {
                    if (!loading) signInWithApple();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
