import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:run_walk_app/create_post_page.dart';

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

  bool get isWearOS {
    final size = MediaQueryData.fromWindow(WidgetsBinding.instance.window).size;
    return size.shortestSide < 300;
  }

  @override
  Widget build(BuildContext context) {
    return isWearOS ? _buildWearView() : _buildMobileView();
  }

  // 📱 -------- VIEW MOBILE --------
  Widget _buildMobileView() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Feed de Atividades'),
        backgroundColor: Colors.grey[900],
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            tooltip: 'Encontrar pessoas',
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.white),
            tooltip: 'Adicionar publicação',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CreatePostPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.white),
            tooltip: 'Notificações',
            onPressed: () {},
          ),
        ],
      ),
      body: _buildFeedStream(
        itemBuilder: (data, formattedTime) => Card(
          color: Colors.grey[900],
          margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 10),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundImage: NetworkImage(
                        data['authorPhotoUrl'] ??
                            'https://via.placeholder.com/150',
                      ),
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
                      style:
                      const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ⌚ -------- VIEW WEAR OS (carrossel de posts) --------
  Widget _buildWearView() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.fromARGB(90, 0, 200, 83),
                Color.fromARGB(40, 255, 109, 0),
                Colors.transparent,
              ],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
          ),
          child: StreamBuilder<QuerySnapshot>(
            stream: _postsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Erro ao carregar posts.',
                      style: TextStyle(color: Colors.redAccent)),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF6D00)),
                );
              }

              if (snapshot.data!.docs.isEmpty) {
                return const Center(
                  child: Text(
                    'Sem publicações ainda!',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                );
              }

              final docs = snapshot.data!.docs;

              return Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, bottom: 4),
                    child: Text(
                      '🌍 Atividades',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),

                  // 🔹 Carrossel de posts
                  Expanded(
                    child: PageView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        Map<String, dynamic> data =
                        docs[index].data()! as Map<String, dynamic>;
                        final postTime =
                            (data['timestamp'] as Timestamp?)?.toDate() ??
                                DateTime.now();
                        timeago.setLocaleMessages(
                            'pt_BR', timeago.PtBrMessages());
                        final formattedTime =
                        timeago.format(postTime, locale: 'pt_BR');

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF00C853),
                                  Color(0xFFFF6D00)
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundImage: NetworkImage(
                                          data['authorPhotoUrl'] ??
                                              'https://via.placeholder.com/100',
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              data['authorName'] ?? 'Anônimo',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              formattedTime,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 9,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  if (data['text'] != null &&
                                      data['text'].isNotEmpty)
                                    Text(
                                      data['text'],
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // 🔹 Indicador de posição do carrossel
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        docs.length,
                            (i) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }


  // 🔁 -------- STREAM REUTILIZADA --------
  Widget _buildFeedStream({
    required Widget Function(Map<String, dynamic> data, String formattedTime)
    itemBuilder,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: _postsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
              child: Text('Erro ao carregar posts.',
                  style: TextStyle(color: Colors.redAccent)));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child:
              CircularProgressIndicator(color: Color(0xFFFF6D00)));
        }

        if (snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              'Sem publicações ainda!',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        final docs = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          physics: const ClampingScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            Map<String, dynamic> data =
            docs[index].data()! as Map<String, dynamic>;
            final postTime =
                (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
            timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
            final formattedTime =
            timeago.format(postTime, locale: 'pt_BR');

            return itemBuilder(data, formattedTime);
          },
        );
      },
    );
  }
}
