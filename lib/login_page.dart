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

  final AudioPlayer _player = AudioPlayer();

  void navigateToRunTrackingPage() {
    Navigator.pushReplacementNamed(context, '/main');
  }

  Future<void> _reactivateIfNeeded(String uid) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await ref.get();

    if (!snap.exists) {
      // se for 1º login, garante o doc com isActive=true
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

// 🔹 Reativação automática caso esteja inativa
      await _reactivateIfNeeded(user.uid);

      final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      var userDoc = await userDocRef.get();

// 🔹 Cria doc se não existir (já com isActive:true)
      if (!userDoc.exists) {
        await userDocRef.set({
          'uid': user.uid,
          'email': user.email,
          'photoURL': user.photoURL ?? '',
          'username': '',
          'isActive': true, // ✅ garante ativo
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
    setState(() => loading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => loading = false);
        return; // usuário cancelou
      }

      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred =
      await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCred.user;
      if (user == null) {
        setState(() => loading = false);
        return;
      }

      // 🔹 Reativação automática
      await _reactivateIfNeeded(user.uid);

      final userDocRef =
      FirebaseFirestore.instance.collection('users').doc(user.uid);
      var userDoc = await userDocRef.get();

      // 🔹 Se não existir cadastro, cria com dados básicos e força perfil incompleto
      if (!userDoc.exists) {
        await userDocRef.set({
          'uid': user.uid,
          'email': user.email,
          'photoURL': user.photoURL ?? '',
          'username': '', // vazio pra forçar completar
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
              // Logo
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

              // Campos
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

              // Botão principal
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

              // Alternar login/cadastro
              TextButton(
                onPressed: () {
                  setState(() {
                    isRegistering = !isRegistering;
                    mensagemErro = '';
                  });
                },
                child: Text(
                  isRegistering
                      ? "Já tenho uma conta"
                      : "Não tem conta? Cadastre-se",
                  style: const TextStyle(color: Colors.black54),
                ),
              ),

              const SizedBox(height: 10),

              // Divisor
              Row(
                children: const [
                  Expanded(child: Divider(color: Colors.black12)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      "ou",
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.black12)),
                ],
              ),

              const SizedBox(height: 20),

              // Botão Google
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: loading ? null : signInWithGoogle,
                  icon: const Icon(Icons.g_mobiledata, color: Colors.black87),
                  label: const Text(
                    "Entrar com Google",
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Colors.black26),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
