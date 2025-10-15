import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  void navigateToRunTrackingPage() {
    Navigator.pushReplacementNamed(context, '/main');
  }

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

      if (userCredential.user != null) {
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

  Future<void> signInWithGoogle() async {
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

      if (userCred.user != null) navigateToRunTrackingPage();
    } catch (e) {
      setState(() => mensagemErro = 'Erro ao autenticar: $e');
    } finally {
      setState(() => loading = false);
    }
  }

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
        placeholderStyle: const TextStyle(color: Colors.white54),
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(seconds: 4),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF00C853), // Verde vibrante
              Color(0xFFFF6D00), // Laranja energético
            ],
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

                    // Botão principal com gradiente verde-laranja
                    GestureDetector(
                      onTap: loading ? null : handleAuthAction,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF00E676), // verde claro
                              Color(0xFFFF9100), // laranja suave
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

                    // Alternar Login / Cadastro
                    TextButton(
                      onPressed: () => setState(() {
                        isRegistering = !isRegistering;
                        mensagemErro = '';
                      }),
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

                    // Botão Google
                    GestureDetector(
                      onTap: loading ? null : signInWithGoogle,
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
                            const Icon(Icons.g_mobiledata, color: Colors.black87, size: 28),
                            const SizedBox(width: 10),
                            const Text(
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
}
