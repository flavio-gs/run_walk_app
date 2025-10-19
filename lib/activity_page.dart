import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  final user = FirebaseAuth.instance.currentUser!;
  late Stream<QuerySnapshot> _challengeStream;

  @override
  void initState() {
    super.initState();
    _challengeStream = FirebaseFirestore.instance
        .collection('posts')
        .where('type', isEqualTo: 'challenge')
        .where('participants', arrayContains: user.uid)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<QuerySnapshot>(
        stream: _challengeStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final challenges = snapshot.data!.docs;
          if (challenges.isEmpty) {
            return _buildEmptyMessage();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: challenges.length,
            itemBuilder: (context, index) {
              final data = challenges[index].data() as Map<String, dynamic>;
              return _buildChallengeCard(challenges[index].id, data);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.flag_outlined, color: Colors.white38, size: 64),
          const SizedBox(height: 12),
          Text(
            "Nenhum desafio ativo no momento",
            style: GoogleFonts.orbitron(color: Colors.white54, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildChallengeCard(String id, Map<String, dynamic> data) {
    final title = data['title'] ?? 'Desafio sem título';
    final distance = (data['distance'] ?? 0).toDouble();
    final deadline = DateTime.tryParse(data['deadline'].toString());
    final createdBy = data['authorName'] ?? 'Desconhecido';
    final authorId = data['authorId'];
    final quitters = (data['quitters'] ?? []).cast<String>();
    final isCreator = authorId == user.uid;
    final isCreatorQuitter = quitters.contains(authorId);
    final isQuitter = quitters.contains(user.uid);

    final userProgressData =
        (data['progress'] ?? {})[user.uid] ?? {'distance': 0, 'status': 'active'};
    final userDistance = (userProgressData['distance'] ?? 0).toDouble();
    final status = userProgressData['status'] ?? 'active';

    final percent =
    distance > 0 ? (userDistance / distance).clamp(0.0, 1.0) : 0.0;

    final isCancelled = status == 'cancelled';
    final isCompleted = percent >= 1.0;

    final now = DateTime.now();
    final remainingTime =
    (deadline != null && deadline.isAfter(now)) ? deadline.difference(now) : Duration.zero;
    final remainingDays = remainingTime.inDays;

    // 🔹 Cores e estilos
    Color progressColor = isCancelled
        ? Colors.grey
        : isCompleted
        ? Colors.greenAccent
        : const Color(0xFF4A90E2);
    Color remainingColor =
    isCancelled ? Colors.grey[700]! : const Color(0xFFFF4C4C);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 22, top: 12),
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🏁 Título + selo de criador
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.russoOne(
                          color: Colors.white,
                          fontSize: 18,
                          letterSpacing: 1.1,
                        ),
                      ),
                      if (isCreator)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ShaderMask(
                            shaderCallback: (Rect bounds) {
                              return const LinearGradient(
                                colors: [Colors.amber, Colors.orangeAccent],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(bounds);
                            },
                            blendMode: BlendMode.srcIn,
                            child: const Icon(
                              Icons.star_rounded,
                              color: Colors.amber,
                              size: 22,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Icon(
                    isCancelled
                        ? Icons.cancel_outlined
                        : isCompleted
                        ? Icons.emoji_events
                        : Icons.flag,
                    color: isCancelled
                        ? Colors.grey
                        : isCompleted
                        ? Colors.amber
                        : Colors.white70,
                    size: 26,
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Text(
                "Criado por: $createdBy",
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),

              if (isCreatorQuitter)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    "⚠️ O criador deste desafio desistiu 😅, mas ele continua valendo!",
                    style: const TextStyle(
                        color: Colors.amberAccent, fontSize: 13, height: 1.3),
                  ),
                ),

              const SizedBox(height: 18),

              // Barra de progresso
              Stack(
                children: [
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: remainingColor.withOpacity(0.3),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: percent,
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: progressColor,
                        boxShadow: [
                          BoxShadow(
                            color: progressColor.withOpacity(0.4),
                            blurRadius: 8,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${userDistance.toStringAsFixed(2)} km percorridos",
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Text(
                    "Meta: ${distance.toStringAsFixed(1)} km",
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              if (remainingDays > 0 && !isCancelled && !isCompleted)
                Text(
                  "⏳ ${remainingDays} dias restantes",
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                )
              else if (isCompleted)
                const Text("🏁 Desafio concluído!",
                    style: TextStyle(color: Colors.greenAccent, fontSize: 13))
              else if (isCancelled)
                  const Text("❌ Você cancelou sua participação",
                      style: TextStyle(color: Colors.grey, fontSize: 13)),

              const SizedBox(height: 18),

              // Botões com contraste mais forte
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton.icon(
                    onPressed: isCancelled
                        ? null
                        : () => _showRanking(context, id, data),
                    icon: const Icon(Icons.leaderboard_rounded,
                        color: Colors.white70, size: 20),
                    label: const Text(
                      "Ver Ranking",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent.withOpacity(0.9),
                      padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: isCancelled || isQuitter
                        ? null
                        : () => _confirmCancel(id, title),
                    icon: const Icon(Icons.exit_to_app_rounded,
                        color: Colors.white70, size: 20),
                    label: const Text(
                      "Cancelar inscrição",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withOpacity(0.9),
                      padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }




  // Mostra ranking e progresso
  void _showRanking(BuildContext context, String challengeId, Map data) {
    final participants = (data['participants'] ?? []).cast<String>();
    final progress = (data['progress'] ?? {}) as Map<String, dynamic>;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withOpacity(0.8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        final sorted = participants.map((uid) {
          final info = progress[uid] ?? {'distance': 0};
          return {
            'uid': uid,
            'distance': (info['distance'] ?? 0).toDouble(),
          };
        }).toList()
          ..sort((a, b) => (b['distance'] as double).compareTo(a['distance'] as double));

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 36),
              const SizedBox(height: 10),
              Text(
                "Ranking do Desafio",
                style: GoogleFonts.russoOne(color: Colors.white, fontSize: 20),
              ),
              const SizedBox(height: 20),
              ...sorted.map((p) {
                final isMe = p['uid'] == user.uid;
                return ListTile(
                  leading: Icon(
                    isMe ? Icons.person_pin_circle : Icons.person_outline,
                    color: isMe ? Colors.greenAccent : Colors.white70,
                  ),
                  title: Text(
                    isMe ? "Você" : p['uid'],
                    style: TextStyle(
                        color: isMe ? Colors.greenAccent : Colors.white70),
                  ),
                  trailing: Text(
                    "${(p['distance'] as double).toStringAsFixed(2)} km",
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                );
              }),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // Confirmação engraçada para desistir
  void _confirmCancel(String challengeId, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("⚠️ Tem certeza?", style: TextStyle(color: Colors.white)),
        content: const Text(
          "Se você desistir, seu nome vai direto pro mural dos desistentes 😬\n\nDeseja continuar?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar", style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance
                  .collection('posts')
                  .doc(challengeId)
                  .update({
                'quitters': FieldValue.arrayUnion([user.uid]),
                'progress.${user.uid}.status': 'cancelled',
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
            child: const Text("Desistir"),
          ),
        ],
      ),
    );
  }
}
