import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  static const String logoUrl =
      "http://ninelabs-wordpress-1aba45-177-136-235-199.traefik.me/wp-content/uploads/2022/05/Group-1.png";

  final AudioPlayer _player = AudioPlayer();

  void navigateToRunTrackingPage() {
    Navigator.pushReplacementNamed(context, '/main');
  }

  // ------------------ 🔐 LOGIN / CADASTRO -------------------
  Future<void> handleAuthAction() async {
    if (emailController.text.trim().isEmpty ||
        senhaController.text.trim().isEmpty) {
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

      final userDocRef =
      FirebaseFirestore.instance.collection('users').doc(user.uid);
      final userDoc = await userDocRef.get();

      if (!userDoc.exists) {
        await userDocRef.set({
          'email': user.email,
          'photoURL': user.photoURL ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/complete_profile');
          return;
        }
      }

      final data = userDoc.data() ?? {};
      final camposObrigatorios = [
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
    // ✅ Simulação automática no Wear OS (para testes em emulador)
    if (isWearOS) {
      await _playFeedback();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Simulando login no Wear OS...",
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.black87,
          duration: Duration(seconds: 2),
        ),
      );
      await Future.delayed(const Duration(seconds: 1));
      navigateToRunTrackingPage();
      return;
    }

    // 🔐 Login real no mobile
    setState(() => loading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred =
      await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCred.user;
      if (user == null) return;

      final userDocRef =
      FirebaseFirestore.instance.collection('users').doc(user.uid);
      final userDoc = await userDocRef.get();

      if (!userDoc.exists) {
        await userDocRef.set({
          'email': user.email,
          'photoURL': user.photoURL ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/complete_profile');
          return;
        }
      }

      final data = userDoc.data() ?? {};
      final camposObrigatorios = [
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
        Navigator.pushReplacementNamed(context, '/complete_profile');
      } else {
        navigateToRunTrackingPage();
      }
    } catch (e) {
      setState(() => mensagemErro = 'Erro ao autenticar: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  // ------------------ 🧭 DETECTOR WEAR OS -------------------
  bool get isWearOS {
    final size = MediaQueryData.fromWindow(WidgetsBinding.instance.window).size;
    return size.shortestSide < 300;
  }

  // ------------------ 🧱 CAMPOS DE TEXTO -------------------
  Widget _buildTextField({
    required TextEditingController controller,
    required String placeholder,
    required IconData icon,
    bool obscureText = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: CupertinoTextField(
        controller: controller,
        placeholder: placeholder,
        obscureText: obscureText,
        prefix: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Icon(icon, color: Colors.white70, size: 20),
        ),
        padding: const EdgeInsets.all(15),
        cursorColor: Colors.orangeAccent,
        placeholderStyle: const TextStyle(color: Colors.black),
        style: const TextStyle(color: Colors.black, fontSize: 15),
      ),
    );
  }

  // ------------------ 🎵 FEEDBACK HÁPTICO + SOM -------------------
  Future<void> _playFeedback() async {
    if (!isWearOS) return;
    try {
      await HapticFeedback.lightImpact();
      await _player.play(AssetSource('click.mp3'));
    } catch (e) {
      debugPrint("Erro ao reproduzir som: $e");
    }
  }

  // ------------------ 💻 MOBILE LOGIN -------------------
  Widget _buildDefaultLogin() {
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(seconds: 4),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00C853), Color(0xFFFF6D00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.white30, width: 1.2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.network(logoUrl, width: 120),
                    const SizedBox(height: 20),
                    Text(
                      isRegistering
                          ? "Crie sua conta para começar"
                          : "Bem-vindo de volta!",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      controller: emailController,
                      placeholder: "Digite seu e-mail",
                      icon: CupertinoIcons.mail,
                    ),
                    _buildTextField(
                      controller: senhaController,
                      placeholder: "Digite sua senha",
                      obscureText: true,
                      icon: CupertinoIcons.lock_fill,
                    ),
                    const SizedBox(height: 10),
                    if (mensagemErro.isNotEmpty)
                      Text(
                        mensagemErro,
                        style: const TextStyle(
                            color: Colors.amberAccent, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    const SizedBox(height: 25),
                    GestureDetector(
                      onTap: loading
                          ? null
                          : () {
                        _playFeedback();
                        handleAuthAction();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF00E676),
                              Color(0xFFFF9100),
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              offset: const Offset(0, 4),
                              blurRadius: 10,
                            )
                          ],
                        ),
                        child: Center(
                          child: loading
                              ? const CupertinoActivityIndicator(
                              color: Colors.black)
                              : Text(
                            isRegistering ? "Cadastrar" : "Entrar",
                            style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        _playFeedback();
                        setState(() {
                          isRegistering = !isRegistering;
                          mensagemErro = '';
                        });
                      },
                      child: Text(
                        isRegistering
                            ? "Já tenho conta, entrar"
                            : "Não tem conta? Cadastrar",
                        style: const TextStyle(
                          color: Colors.white70,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: const [
                        Expanded(child: Divider(color: Colors.white38)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text("ou",
                              style: TextStyle(color: Colors.white70)),
                        ),
                        Expanded(child: Divider(color: Colors.white38)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: loading
                          ? null
                          : () {
                        _playFeedback();
                        signInWithGoogle();
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.g_mobiledata,
                                color: Colors.black87, size: 28),
                            SizedBox(width: 10),
                            Text(
                              "Entrar com Google",
                              style: TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------ ⌚ WEAR OS LOGIN -------------------
  Widget _buildWearOSLogin() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00C853), Color(0xFFFF6D00)],
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipOval(
                  child: Image.network(
                    logoUrl,
                    width: 70,
                    height: 70,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Império da Corrida",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  "Toque para entrar",
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: loading
                      ? null
                      : () async {
                    await _playFeedback();
                    await signInWithGoogle();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    height: 60,
                    width: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00C853), Color(0xFFFF6D00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orangeAccent.withOpacity(0.7),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: loading
                        ? const CupertinoActivityIndicator(color: Colors.black)
                        : const Icon(Icons.play_arrow_rounded,
                        color: Colors.black, size: 32),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Google Login",
                  style: TextStyle(color: Colors.white, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------ 🧩 BUILD FINAL -------------------
  @override
  Widget build(BuildContext context) {
    return isWearOS ? _buildWearOSLogin() : _buildDefaultLogin();
  }
}
