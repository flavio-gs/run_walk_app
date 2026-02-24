import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:run_walk_app/theme/season_theme_scope.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  int _rating = 0;
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendFeedback() async {
    final s = SeasonThemeScope.of(context);

    if (_rating == 0 || _controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Por favor, dê uma nota e escreva seu feedback!"),
          backgroundColor: s.destructive,
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
          SnackBar(
            content: const Text("✨ Obrigado pelo seu feedback!"),
            backgroundColor: s.accent,
          ),
        );
      }
    } catch (e) {
      final s2 = SeasonThemeScope.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erro ao enviar: $e"),
          backgroundColor: s2.destructive,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _buildStar(int index) {
    final s = SeasonThemeScope.of(context);

    final isOn = index <= _rating;

    return IconButton(
      icon: Icon(
        isOn ? Icons.star_rounded : Icons.star_border_rounded,
        color: isOn ? s.accent : s.muted,
        size: 40,
      ),
      onPressed: () => setState(() => _rating = index),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = SeasonThemeScope.of(context);

    return Scaffold(
      backgroundColor: s.background,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: s.accent),
        title: Text(
          "Feedback",
          style: GoogleFonts.russoOne(
            textStyle: TextStyle(
              color: s.foreground,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Fundo (gradiente usando tokens do tema)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  s.background,
                  s.card.withOpacity(0.70),
                  s.popover.withOpacity(0.65),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 22),
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: s.card.withOpacity(0.55),
                    border: Border.all(color: s.border.withOpacity(0.9)),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: s.ring.withOpacity(0.15),
                        blurRadius: 26,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 6),
                        Text(
                          "O que achou do Império da Corrida? 👑",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.orbitron(
                            textStyle: TextStyle(
                              color: s.cardForeground,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),

                        // ⭐ Estrelas
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(5, (i) => _buildStar(i + 1)),
                        ),

                        const SizedBox(height: 22),

                        // 📝 Campo de texto
                        TextField(
                          controller: _controller,
                          maxLines: 5,
                          textAlignVertical: TextAlignVertical.top,
                          style: TextStyle(color: s.foreground),
                          cursorColor: s.ring,
                          decoration: InputDecoration(
                            hintText: "Deixe sua opinião, ideia ou bug encontrado!",
                            hintStyle: TextStyle(color: s.mutedForeground),
                            filled: true,
                            fillColor: s.input.withOpacity(0.85),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: s.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: s.ring, width: 1.5),
                            ),
                          ),
                        ),

                        const SizedBox(height: 22),

                        // 🔘 Botão enviar
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _sending ? null : _sendFeedback,
                            icon: _sending
                                ? SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  s.primaryForeground,
                                ),
                              ),
                            )
                                : Icon(Icons.send_rounded, color: s.primaryForeground),
                            label: Text(
                              _sending ? "Enviando..." : "Enviar feedback",
                              style: TextStyle(
                                color: s.primaryForeground,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: s.primary,
                              disabledBackgroundColor: s.muted.withOpacity(0.35),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        Text(
                          "Seu feedback nos ajuda a evoluir mais rápido que um sprint! 🏃‍♂️💨",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: s.mutedForeground,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
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
