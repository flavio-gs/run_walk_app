import 'dart:math' as math;
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

class _LoginWearPageState extends State<LoginWearPage> with SingleTickerProviderStateMixin {
  bool loading = false;
  String mensagem = '';

  // 🔸 Progresso determinístico (0.0 → 1.0)
  double _progress = 0.0;
  String _status = '';

  late final AnimationController _progressCtrl;
  Animation<double>? _progressAnim;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))
      ..addListener(() {
        setState(() {
          _progress = _progressAnim?.value ?? _progress;
        });
      });
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  // 🔸 Anima suavemente até o alvo informado
  Future<void> _animateTo(double target, {Curve curve = Curves.easeInOut}) async {
    _progressAnim = Tween<double>(begin: _progress, end: target).animate(CurvedAnimation(
      parent: _progressCtrl,
      curve: curve,
    ));
    await _progressCtrl.forward(from: 0);
  }

  Future<void> _step(double target, String status) async {
    setState(() => _status = status);
    await _animateTo(target);
  }

  Future<void> _signInWithGoogle() async {
    if (Firebase.apps.isEmpty) {
      setState(() => mensagem = "📴 Modo offline — conecte-se via app principal.");
      return;
    }

    setState(() {
      loading = true;
      mensagem = '';
      _progress = 0.0;
      _status = 'Iniciando...';
    });

    try {
      await _step(0.10, 'Conectando ao Google...');

      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        // Usuário cancelou
        await _step(0.0, 'Cancelado');
        setState(() => loading = false);
        return;
      }

      await _step(0.30, 'Autorizando...');
      final googleAuth = await googleUser.authentication;

      await _step(0.50, 'Obtendo credenciais...');
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCred.user;
      if (user == null) {
        setState(() {
          mensagem = "Erro: usuário não retornado.";
          loading = false;
        });
        return;
      }

      await _step(0.75, 'Sincronizando perfil...');
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

      await _step(0.95, 'Finalizando...');
      await Future.delayed(const Duration(milliseconds: 200));

      if (mounted) {
        await _step(1.0, 'Pronto!');
        Navigator.pushReplacementNamed(context, '/main_wear');
      }
    } catch (e) {
      setState(() => mensagem = "Erro: $e");
    } finally {
      setState(() => loading = false);
    }
  }

  void _continueOffline() {
    Navigator.pushReplacementNamed(context, '/main_wear');
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
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
                    Image.asset('assets/icon/logo_transp.png', height: 60),
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
                    SizedBox(
                      width: 120,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orangeAccent,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        onPressed: _signInWithGoogle,
                        child: const Text(
                          "Entrar com Google",
                          style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _continueOffline,
                      child: const Text("Entrar offline", style: TextStyle(color: Colors.white70, fontSize: 10)),
                    ),
                    if (mensagem.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(mensagem, style: const TextStyle(color: Colors.redAccent, fontSize: 10), textAlign: TextAlign.center),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),

        // 🔶 Overlay determinístico com % e status
        if (loading)
          _DeterminateLoadingOverlay(progress: _progress, status: _status),
      ],
    );
  }
}

class _DeterminateLoadingOverlay extends StatelessWidget {
  final double progress; // 0.0 → 1.0
  final String status;

  const _DeterminateLoadingOverlay({required this.progress, required this.status});

  @override
  Widget build(BuildContext context) {
    final pct = (progress.clamp(0.0, 1.0) * 100).round();
    return Container(
      color: Colors.black.withOpacity(0.60),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 78,
            width: 78,
            child: CustomPaint(
              painter: _DeterminateRingPainter(progress: progress),
              child: Center(
                child: Text(
                  '$pct%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            status,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DeterminateRingPainter extends CustomPainter {
  final double progress; // 0.0 → 1.0

  _DeterminateRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide / 2) - 4;

    // trilho
    final track = Paint()
      ..color = const Color(0xFF2B2B2B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    // arco de progresso
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    final start = -math.pi / 2; // começa no topo
    final rect = Rect.fromCircle(center: center, radius: radius);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: const [Color(0xFFFFA726), Color(0xFFFFCC80), Color(0xFFFFA726)],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);

    canvas.drawArc(rect, start, sweep, false, arc);
  }

  @override
  bool shouldRepaint(_DeterminateRingPainter old) => old.progress != progress;
}
