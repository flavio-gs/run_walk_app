
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  // O Stream vai ouvir a coleção 'posts' no Firestore, ordenando pelo mais recente.
  final Stream<QuerySnapshot> _postsStream = FirebaseFirestore.instance
      .collection('posts')
      .orderBy('timestamp', descending: true)
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
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
            
            // Usando a biblioteca timeago para formatar o tempo relativo
            final postTime = (data['timestamp'] as Timestamp).toDate();
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
                      Text(
                        data['text'],
                        style: const TextStyle(color: Colors.white),
                      ),
                    const SizedBox(height: 10),
                    // Exibindo dados da corrida (exemplo)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMetric('Distância', '${data['distance']?.toStringAsFixed(2) ?? '0'} km'),
                        _buildMetric('Duração', data['duration'] ?? '00:00'),
                        _buildMetric('Ritmo', '${data['pace'] ?? '0'}/km'),
                      ],
                    )
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildMetric(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
              color: Colors.pinkAccent,
              fontSize: 16,
              fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

