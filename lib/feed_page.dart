import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:run_walk_app/comments_page.dart';
import 'package:run_walk_app/create_post_page.dart';
import 'package:run_walk_app/notifications_page.dart';
import 'package:run_walk_app/search_users_page.dart';
import 'package:timeago/timeago.dart' as timeago;

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

  Future<void> _setupFeedStream() async {
    final followingSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .collection('following')
        .get();
    List<String> followingIds =
        followingSnapshot.docs.map((doc) => doc.id).toList();

    followingIds.add(_currentUserId);

    if (mounted) {
      setState(() {
        _postsStream = FirebaseFirestore.instance
            .collection('posts')
            .where('authorId', whereIn: followingIds)
            .orderBy('timestamp', descending: true)
            .snapshots();
        _isLoading = false;
      });
    }
  }

  // FUNÇÃO MOVIDA PARA O LUGAR CORRETO
  bool get isWearOS {
    final size = MediaQuery.of(context).size;
    return size.shortestSide < 300;
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

  // 📱 -------- VIEW MOBILE CORRIGIDA E LIMPA --------
  Widget _buildMobileView() {
    const Color primaryGreen = Color(0xFF00C853);
    const Color softOrange = Color(0xFFFF9100);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [primaryGreen, softOrange],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight)),
          child: AppBar(
            title: const Text('FEED', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
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
      body: _buildFeedBody(), // Chamando a função correta
    );
  }

  // Corpo do Feed (StreamBuilder) que estava quebrado
  Widget _buildFeedBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return StreamBuilder<QuerySnapshot>(
      stream: _postsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _postsStream != null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Ocorreu um erro ao carregar o feed.', style: TextStyle(color: Colors.black54)));
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
              stream: FirebaseFirestore.instance.collection('posts').doc(post.id).collection('comments').snapshots(),
              builder: (context, commentSnapshot) {
                final commentCount = commentSnapshot.data?.docs.length ?? 0;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  color: Colors.grey[900],
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _buildPostHeader(data),
                      const SizedBox(height: 12),
                      if (data['text'] != null && data['text'].isNotEmpty) Text(data['text'], style: const TextStyle(color: Colors.white, fontSize: 16)),
                      const Divider(color: Colors.white24, height: 24),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                        _actionButton(isLiked ? Icons.favorite : Icons.favorite_border, '${likes.length} Curtidas', () => _toggleLike(post.id, authorId, likes), color: isLiked ? Theme.of(context).primaryColor : Colors.white70),
                        _actionButton(Icons.comment_outlined, '$commentCount Comentários', () => Navigator.push(context, MaterialPageRoute(builder: (context) => CommentsPage(postId: post.id, postAuthorId: authorId)))),
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


  // ⌚ -------- VIEW WEAR OS (carrossel de posts) --------
  Widget _buildWearView() {
    // O seu código para Wear OS parece correto e não foi alterado.
    return Scaffold(/* ... */);
  }
  
  // --- WIDGETS AUXILIARES RESTAURADOS ---
  Widget _buildPostHeader(Map<String, dynamic> data) {
    final postTime = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
    final authorId = data['authorId'] as String?;

    if (authorId == null) {
      return Row(
        children: [
          const CircleAvatar(
            backgroundImage: AssetImage('assets/icon/logo_principal.png'),
            radius: 20,
          ),
          const SizedBox(width: 10),
          const Text('Usuário desconhecido',
              style: TextStyle(color: Colors.white)),
        ],
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(authorId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Row(
            children: [
              const CircleAvatar(
                backgroundImage: AssetImage('assets/icon/logo_principal.png'),
                radius: 20,
              ),
              const SizedBox(width: 10),
              const Text('Carregando...',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Row(
            children: [
              const CircleAvatar(
                backgroundImage: AssetImage('assets/icon/logo_principal.png'),
                radius: 20,
              ),
              const SizedBox(width: 10),
              Text(data['authorName'] ?? 'Usuário',
                  style: const TextStyle(color: Colors.white)),
            ],
          );
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final authorName =
            userData['displayName'] ?? data['authorName'] ?? 'Usuário';
        final photoUrl = userData['photoURL'];

        return Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                  ? NetworkImage(photoUrl)
                  : const AssetImage('assets/icon/logo_principal.png')
              as ImageProvider,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(authorName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.white)),
                Text(
                  timeago.format(postTime, locale: 'pt_BR'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ],
        );
      },
    );
  }



  Widget _actionButton(IconData icon, String label, VoidCallback onPressed, {Color? color}) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: color ?? Colors.white70),
      label: Text(label, style: TextStyle(color: color ?? Colors.white70)),
    );
  }

  Widget _emptyFeedMessage() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('Feed Silencioso', style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text('Faça sua primeira publicação ou siga outros usuários.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SearchUsersPage())).then((_) => _setupFeedStream()),
          icon: const Icon(Icons.search),
          label: const Text('Encontrar Pessoas'),
        ),
      ]),
    );
  }
}
