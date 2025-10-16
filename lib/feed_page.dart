import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:run_walk_app/create_post_page.dart';
import 'package:run_walk_app/notifications_page.dart';
import 'package:run_walk_app/search_users_page.dart';
import 'package:run_walk_app/comments_page.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:run_walk_app/create_post_page.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  Stream<QuerySnapshot>? _postsStream;
  bool _isLoading = true;
  final _currentUserId = FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
    _setupFeedStream();
  }

  // LÓGICA DO FEED CORRIGIDA
  Future<void> _setupFeedStream() async {
    // 1. Pega a lista de IDs de quem o usuário segue.
    final followingSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .collection('following')
        .get();
    List<String> followingIds =
        followingSnapshot.docs.map((doc) => doc.id).toList();

    // 2. Garante que o usuário sempre veja suas próprias publicações.
    followingIds.add(_currentUserId);

    if (mounted) {
      setState(() {
        // 3. Cria a busca no banco de dados com a lista de IDs correta.
        // A lista nunca estará vazia, pois sempre contém o ID do próprio usuário.
        _postsStream = FirebaseFirestore.instance
            .collection('posts')
            .where('authorId', whereIn: followingIds)
            .orderBy('timestamp', descending: true)
            .snapshots();

  bool get isWearOS {
    final size = MediaQueryData.fromWindow(WidgetsBinding.instance.window).size;
    return size.shortestSide < 300;
  }

        _isLoading = false;
      });
    }
  }

  Future<void> _toggleLike(
      String postId, String authorId, List<dynamic> currentLikes) async {
    final isLiked = currentLikes.contains(_currentUserId);
    final postRef = FirebaseFirestore.instance.collection('posts').doc(postId);

    if (isLiked) {
      await postRef.update({
        'likes': FieldValue.arrayRemove([_currentUserId])
      });
    } else {
      await postRef.update({
        'likes': FieldValue.arrayUnion([_currentUserId])
      });
      if (_currentUserId != authorId) {
        final notificationRef = FirebaseFirestore.instance
            .collection('users')
            .doc(authorId)
            .collection('notifications');
        await notificationRef.add({
          'type': 'like',
          'message':
              '${FirebaseAuth.instance.currentUser?.displayName ?? 'Alguém'} curtiu sua publicação.',
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return isWearOS ? _buildWearView() : _buildMobileView();
  }

  // 📱 -------- VIEW MOBILE --------
  Widget _buildMobileView() {
    const Color primaryGreen = const Color(0xFF00C853);
    const Color accentOrange = const Color(0xFFFF6D00);
    const Color lightGreen = const Color(0xFF00E676);
    const Color softOrange = const Color(0xFFFF9100);
    const Color logoutRed = const Color(0xFFE53935);

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
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [primaryGreen,softOrange],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)),
          child: AppBar(
            title: const Text('FEED',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            actionsIconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const SearchUsersPage()))
                      .then((_) => _setupFeedStream())),
              IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const CreatePostPage()))),
              IconButton(
                  icon: const Icon(Icons.notifications),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const NotificationsPage()))),
            ],
          ),
        ),
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
      body: _buildFeedBody(),
    );
  }

  // background: Stack(
  // fit: StackFit.expand,
  // children: [
  // Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [primaryGreen, accentOrange], begin: Alignment.topLeft, end: Alignment.bottomRight))),
  // Align(alignment: Alignment.bottomLeft, child: Padding(padding: const EdgeInsets.all(16), child: CircleAvatar(radius: 45, backgroundColor: Colors.white.withOpacity(0.25), backgroundImage: (photoURL != null && photoURL!.isNotEmpty) ? NetworkImage(photoURL!) : null, child: (photoURL == null || photoURL!.isEmpty) ? const Icon(Icons.person, color: Colors.white, size: 50) : null))),
  // ],
  // ),

  Widget _buildFeedBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return StreamBuilder<QuerySnapshot>(
      stream: _postsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            _postsStream != null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(
              child: Text('Ocorreu um erro ao carregar o feed.',
                  style: TextStyle(color: Colors.white70)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _emptyFeedMessage();
        }

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final post = snapshot.data!.docs[index];
            final data = post.data() as Map<String, dynamic>;
            final authorId = data['authorId'];
            final likes = data['likes'] as List<dynamic>? ?? [];
            final isLiked = likes.contains(_currentUserId);

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .doc(post.id)
                  .collection('comments')
                  .snapshots(),
              builder: (context, commentSnapshot) {
                final commentCount = commentSnapshot.data?.docs.length ?? 0;
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  color: Colors.grey[900],
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPostHeader(data),
                          const SizedBox(height: 12),
                          if (data['text'] != null && data['text'].isNotEmpty)
                            Text(data['text'],
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 16)),
                          const Divider(color: Colors.white24, height: 24),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _actionButton(
                                    isLiked
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    '${likes.length} Curtidas',
                                    () => _toggleLike(post.id, authorId, likes),
                                    color: isLiked
                                        ? Theme.of(context).primaryColor
                                        : Colors.white70),
                                _actionButton(
                                    Icons.comment_outlined,
                                    '$commentCount Comentários',
                                    () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) => CommentsPage(
                                                postId: post.id,
                                                postAuthorId: authorId)))),
                              ]),
                        ]),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPostHeader(Map<String, dynamic> data) {
    final postTime =
        (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
    return Row(children: [
      CircleAvatar(
          backgroundImage: NetworkImage(
              data['authorPhotoUrl'] ?? 'https://via.placeholder.com/150'),
          radius: 20),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(data['authorName'] ?? 'Usuário Anônimo',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.white)),
        Text(timeago.format(postTime, locale: 'pt_BR'),
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    ]);
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onPressed,
      {Color? color}) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: color ?? Colors.white70),
      label: Text(label, style: TextStyle(color: color ?? Colors.white70)),
    );
  }

  Widget _emptyFeedMessage() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('Feed Silencioso',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text('Faça sua primeira publicação ou siga outros usuários.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const SearchUsersPage()))
              .then((_) => _setupFeedStream()),
          icon: const Icon(Icons.search),
          label: const Text('Encontrar Pessoas'),
        ),
      ]),
    );
  }
}
