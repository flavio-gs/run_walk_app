import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class HistoricoWearPage extends StatelessWidget {
  const HistoricoWearPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const _CenteredText("Faça login no app principal para ver seu histórico 🕓");
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('corridas')
              .where('userId', isEqualTo: user.uid)
              .orderBy('createdAt', descending: true)
              .limit(10)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const _CenteredText("Carregando...");
            }
            if (snapshot.data!.docs.isEmpty) {
              return const _CenteredText("Nenhuma corrida registrada ainda 🏃‍♂️");
            }

            return ListView.builder(
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                final run = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                final date = (run['data'] as Timestamp?)?.toDate();
                final dist = ((run['distancia_m'] ?? 0) / 1000).toStringAsFixed(2);
                final kcal = (run['kcal'] ?? 0).toStringAsFixed(0);
                final tempo = Duration(seconds: run['tempo_s'] ?? 0);
                final min = tempo.inMinutes.remainder(60).toString().padLeft(2, '0');
                final sec = tempo.inSeconds.remainder(60).toString().padLeft(2, '0');

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          date != null
                              ? DateFormat('dd/MM • HH:mm').format(date)
                              : 'Sem data',
                          style: const TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "$dist km • $kcal kcal",
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "⏱ $min:$sec",
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _CenteredText extends StatelessWidget {
  final String text;
  const _CenteredText(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
      ),
    );
  }
}
