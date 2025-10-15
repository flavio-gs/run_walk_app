import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart'; // Import necessário para Cupertino widgets
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:run_walk_app/run_tracker.dart'; // Assumindo que este é o caminho correto

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Controladores de Texto
  final TextEditingController emailController = TextEditingController();
  final TextEditingController senhaController = TextEditingController();

  bool loading = false;
  String mensagemErro = '';
  bool isRegistering = false; // Alterna entre Login e Cadastro

  // URL da imagem de rede do seu exemplo
  static const String logoUrl =
      "http://ninelabs-wordpress-1aba45-177-136-235-199.traefik.me/wp-content/uploads/2022/05/Group-1.png";

  // Função centralizada para navegação
  void navigateToRunTrackingPage() {
    Navigator.pushReplacementNamed(context, '/main');
  }

  // --- LÓGICA DE AUTENTICAÇÃO PADRÃO (E-MAIL/SENHA) ---

  Future<void> handleAuthAction() async {
    // Validação básica
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
      if (isRegistering) {
        // Ação de CADASTRO
        final userCredential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailController.text.trim(),
          password: senhaController.text.trim(),
        );
        if (userCredential.user != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Conta criada com sucesso! Entrando...')),
          );
          navigateToRunTrackingPage();
        }
      } else {
        // Ação de LOGIN
        final userCredential =
            await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: senhaController.text.trim(),
        );
        if (userCredential.user != null) {
          navigateToRunTrackingPage();
        }
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        setState(() => mensagemErro = 'E-mail ou senha inválidos.');
      } else if (e.code == 'email-already-in-use') {
        setState(() => mensagemErro = 'Este e-mail já está cadastrado.');
      } else {
        setState(() => mensagemErro = 'Erro: ${e.message}');
      }
    } finally {
      setState(() => loading = false);
    }
  }

  // --- LÓGICA DE AUTENTICAÇÃO GOOGLE ---

  Future<void> signInWithGoogle() async {
    setState(() {
      loading = true;
      mensagemErro = '';
    });

    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();

      if (googleUser == null) {
        setState(() => loading = false);
        return; // Usuário cancelou
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      if (userCredential.user != null) {
        navigateToRunTrackingPage();
      }
    } on FirebaseAuthException catch (e) {
      setState(() => mensagemErro = 'Erro Google: ${e.message}');
    } catch (e) {
      setState(() => mensagemErro = 'Erro inesperado: $e');
    } finally {
      setState(() => loading = false);
    }
  }

  // --- WIDGETS AUXILIARES PARA INPUTS ---

  Widget _buildTextField({
    required TextEditingController controller,
    required String placeholder,
    bool obscureText = false,
  }) {
    return CupertinoTextField(
      controller: controller,
      cursorColor: Colors.amber,
      padding: const EdgeInsets.all(15),
      placeholder: placeholder,
      obscureText: obscureText,
      placeholderStyle: const TextStyle(color: Colors.white70, fontSize: 14),
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: const BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.all(
            Radius.circular(7),
          )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Image(
          image: NetworkImage(logoUrl),
          width: 140,
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        width: MediaQuery.of(context).size.width,
        padding: const EdgeInsets.all(27),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.teal,
              Color.fromARGB(255, 250, 110, 2),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 30),
            Text(
              isRegistering
                  ? "Crie sua conta nos campos abaixo."
                  : "Digite os dados de acesso nos campos abaixo.",
              style: const TextStyle(
                color: Colors.white,
              ),
            ),
            if (mensagemErro.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  mensagemErro,
                  style: const TextStyle(
                      color: Colors
                          .yellowAccent), // Mudança de cor para destacar no fundo escuro
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 30),

            // Campos de Texto
            _buildTextField(
              controller: emailController,
              placeholder: "Digite o seu e-mail",
            ),
            const SizedBox(height: 5),
            _buildTextField(
              controller: senhaController,
              placeholder: "Digite sua senha",
              obscureText: true,
            ),
            const SizedBox(height: 30),

            // Botão Principal (Login / Cadastrar)
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                padding: const EdgeInsets.all(17),
                color: Colors.greenAccent,
                onPressed: loading ? null : handleAuthAction,
                child: loading
                    ? const CupertinoActivityIndicator(
                        radius: 10, color: Colors.black45)
                    : Text(
                        isRegistering ? "Cadastrar" : "Acessar",
                        style: const TextStyle(
                            color: Colors.black45,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
              ),
            ),
            const SizedBox(height: 7),

            // Botão de Alternância (Criar Conta / Já tenho conta)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.white70, width: 0.8),
                  borderRadius: BorderRadius.circular(7)),
              child: CupertinoButton(
                child: Text(
                  isRegistering
                      ? "Já tenho uma conta, Acessar"
                      : "Crie sua conta",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                onPressed: () {
                  setState(() {
                    isRegistering = !isRegistering;
                    mensagemErro = '';
                    emailController.clear();
                    senhaController.clear();
                  });
                },
              ),
            ),
            const SizedBox(height: 15),

            // Botão Google Sign-In
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(7)),
              child: CupertinoButton(
                child: const Text(
                  "Entrar com Google",
                  style: TextStyle(
                      color: Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                onPressed: loading ? null : signInWithGoogle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
