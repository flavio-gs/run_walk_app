import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:run_walk_app/create_post_page.dart'; // Importa a tela de criação

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final Stream<QuerySnapshot> _postsStream = FirebaseFirestore.instance
      .collection('posts')
      .orderBy('timestamp', descending: true)
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Feed de Atividades'),
        backgroundColor: Colors.grey[900],
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            tooltip: 'Encontrar pessoas',
            onPressed: () {
              // TODO: Implementar busca de usuários
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.white),
            tooltip: 'Adicionar publicação',
            onPressed: () {
              // Navega para a tela de criação de post
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CreatePostPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.white),
            tooltip: 'Notificações',
            onPressed: () {
              // TODO: Implementar notificações
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _postsStream,
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Algo deu errado.'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'Nenhuma publicação encontrada.\nSiga seus amigos para ver as atividades deles!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: snapshot.data!.docs.map((DocumentSnapshot document) {
              Map<String, dynamic> data =
                  document.data()! as Map<String, dynamic>;
              final postTime = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
              timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
              final formattedTime = timeago.format(postTime, locale: 'pt_BR');
              return Card(
                color: Colors.grey[900],
                margin: const EdgeInsets.symmetric(vertical: 8.0),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundImage: NetworkImage(
                                data['authorPhotoUrl'] ?? 'https://via.placeholder.com/150'),
                            radius: 20,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['authorName'] ?? 'Usuário Anônimo',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                formattedTime,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (data['text'] != null && data['text'].isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            data['text'],
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ),
                      // Adicionar espaço para outras informações como métricas de corrida
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}
