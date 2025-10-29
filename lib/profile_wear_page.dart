import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileWearPage extends StatelessWidget {
  const ProfileWearPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const _CenteredText("Nenhum usuário logado ⚠️");
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const _CenteredText("Carregando perfil...");
            }

            final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            final xp = (data['xp'] ?? 0).toDouble();
            final level = (data['level'] ?? 1).toInt();
            final name = data['displayName'] ??
                user.displayName ??
                user.email ??
                'Usuário';
            final since = data['createdAt'] ?? data['updatedAt'];

            // 🔹 Prioriza foto do Firestore > Firebase Auth > ícone padrão
            final photoURL = (data['photoURL'] ??
                user.photoURL ??
                '').toString().trim();

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 🔸 Foto de perfil ou ícone
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.orangeAccent.withOpacity(0.3),
                      backgroundImage:
                      photoURL.isNotEmpty ? NetworkImage(photoURL) : null,
                      child: photoURL.isEmpty
                          ? const Icon(Icons.person,
                          color: Colors.white, size: 32)
                          : null,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Nível $level • ${xp.toStringAsFixed(0)} XP",
                      style: const TextStyle(
                          color: Colors.orangeAccent, fontSize: 11),
                    ),
                    const SizedBox(height: 10),
                    if (since != null)
                      const Text(
                        "Membro ativo 🌟",
                        style:
                        TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                  ],
                ),
              ),
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
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
    );
  }
}
