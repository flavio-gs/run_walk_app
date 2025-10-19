import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  int _rating = 0;
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  Future<void> _sendFeedback() async {
    if (_rating == 0 || _controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Por favor, dê uma nota e escreva seu feedback!"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _sending = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('feedbacks').add({
        'userId': user?.uid ?? 'anônimo',
        'userName': user?.displayName ?? 'Jogador misterioso',
        'rating': _rating,
        'message': _controller.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
      });

      setState(() {
        _rating = 0;
        _controller.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✨ Obrigado pelo seu feedback!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erro ao enviar: $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      setState(() => _sending = false);
    }
  }

  Widget _buildStar(int index) {
    return IconButton(
      icon: Icon(
        index <= _rating ? Icons.star_rounded : Icons.star_border_rounded,
        color: index <= _rating ? Colors.amber : Colors.white24,
        size: 40,
      ),
      onPressed: () {
        setState(() => _rating = index);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF4A90E2), Color(0xFF007AFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
          child: Text(
            "Feedback",
            style: GoogleFonts.russoOne(
              textStyle: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Fundo com gradiente e blur
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0A0A0A),
                  Color(0xFF0F2027),
                  Color(0xFF203A43),
                  Color(0xFF2C5364),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(25),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 25),
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueAccent.withOpacity(0.2),
                        blurRadius: 25,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 10),
                        Text(
                          "O que achou do Império da Corrida? 👑",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.orbitron(
                            textStyle: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 25),

                        // ⭐ Estrelas
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(5, (i) => _buildStar(i + 1)),
                        ),

                        const SizedBox(height: 25),

                        // 📝 Campo de texto
                        TextField(
                          controller: _controller,
                          maxLines: 5,
                          textAlignVertical: TextAlignVertical.top,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: "Deixe sua opinião, ideia ou bug encontrado!",
                            hintStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.1),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                  color: Colors.white.withOpacity(0.2)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                  color: Color(0xFF4A90E2), width: 1.5),
                            ),
                          ),
                        ),

                        const SizedBox(height: 25),

                        // 🔘 Botão enviar
                        ElevatedButton.icon(
                          onPressed: _sending ? null : _sendFeedback,
                          icon: _sending
                              ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                              AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                              : const Icon(Icons.send_rounded,
                              color: Colors.white),
                          label: Text(
                            _sending ? "Enviando..." : "Enviar feedback",
                            style: const TextStyle(color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                            const Color(0xFF007AFF).withOpacity(0.9),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        Text(
                          "Seu feedback nos ajuda a evoluir mais rápido que um sprint! 🏃‍♂️💨",
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
