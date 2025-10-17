import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart'; // para HapticFeedback
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

class _FeedPageState extends State<FeedPage> with TickerProviderStateMixin {
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

  Future<void> _toggleLike(
      String postId, String authorId, List<dynamic> currentLikes) async {
    final isLiked = currentLikes.contains(_currentUserId);
    final postRef = FirebaseFirestore.instance.collection('posts').doc(postId);

    if (isLiked) {
      await postRef.update({
        'likes': FieldValue.arrayRemove([_currentUserId])
      });
    } else {
      HapticFeedback.mediumImpact(); // feedback físico no toque
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
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'RunFeed',
          style: TextStyle(
              color: Colors.black, fontWeight: FontWeight.bold, fontSize: 22),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const SearchUsersPage()))
                  .then((_) => _setupFeedStream())),
          IconButton(
              icon: const Icon(Icons.add_box_outlined),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const CreatePostPage()))),
          IconButton(
              icon: const Icon(Icons.favorite_border),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const NotificationsPage()))),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildFeedBody(),
    );
  }

  Widget _buildFeedBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: _postsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _emptyFeedMessage();
        }

        final posts = snapshot.data!.docs;

        return ListView(
          children: [
            _buildStoriesSection(),
            const Divider(height: 1, color: Colors.black26),
            ...posts.map((post) => _buildPostItem(post)).toList(),
          ],
        );
      },
    );
  }

  // 🔹 STORIES NO TOPO 🔹
  Widget _buildStoriesSection() {
    return SizedBox(
      height: 110,
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final users = snapshot.data!.docs;
          final currentUser = FirebaseAuth.instance.currentUser;

          // Adiciona o seu story como o primeiro
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: users.length + 1, // +1 para o story do próprio usuário
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            itemBuilder: (context, index) {
              // 👉 Primeiro círculo: “Seu story”
              if (index == 0) {
                final photoUrl = currentUser?.photoURL;
                final name = currentUser?.displayName ?? "Você";

                return GestureDetector(
                  onTap: () {
                    _showAddStoryOptions(context);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            // Gradiente de borda igual aos outros
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Color(0xFF00C853), Color(0xFFFF9100)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(3),
                              child: CircleAvatar(
                                radius: 30,
                                backgroundImage:
                                (photoUrl != null && photoUrl.isNotEmpty)
                                    ? NetworkImage(photoUrl)
                                    : const AssetImage(
                                    'assets/icon/logo_principal.png')
                                as ImageProvider,
                              ),
                            ),
                            // Ícone de +
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent,
                                  border: Border.all(
                                      color: Colors.white, width: 2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.add,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        const Text('Seu story',
                            style: TextStyle(
                                fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                );
              }

              // 👉 Stories dos outros usuários
              final userData = users[index - 1].data() as Map<String, dynamic>;
              final photoUrl = userData['photoURL'];
              final name = userData['displayName'] ?? 'Usuário';

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Color(0xFFFF9100), Color(0xFF00C853)]),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(3),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundImage:
                        (photoUrl != null && photoUrl.isNotEmpty)
                            ? NetworkImage(photoUrl)
                            : const AssetImage(
                            'assets/icon/logo_principal.png')
                        as ImageProvider,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(name.split(' ').first,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // 🔹 MODAL PARA ADICIONAR STORY 🔹
  void _showAddStoryOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 15),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const Text(
                'Criar novo story',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded,
                    color: Colors.deepOrange),
                title: const Text('Tirar foto'),
                subtitle: const Text('Abra a câmera para tirar uma foto'),
                onTap: () {
                  Navigator.pop(context);
                  // 🔸 Aqui você pode chamar o método para abrir a câmera
                  debugPrint('Abrir câmera');
                },
              ),
              ListTile(
                leading:
                const Icon(Icons.photo_library_rounded, color: Colors.green),
                title: const Text('Escolher da galeria'),
                subtitle: const Text('Selecione uma imagem existente'),
                onTap: () {
                  Navigator.pop(context);
                  // 🔸 Aqui você pode chamar o método para abrir a galeria
                  debugPrint('Abrir galeria');
                },
              ),
              ListTile(
                leading: const Icon(Icons.text_fields_rounded,
                    color: Colors.indigoAccent),
                title: const Text('Adicionar texto ou status'),
                subtitle: const Text('Crie um story apenas com texto'),
                onTap: () {
                  Navigator.pop(context);
                  // 🔸 Aqui você pode abrir uma tela de texto (futuramente)
                  debugPrint('Adicionar texto/story rápido');
                },
              ),
              const SizedBox(height: 15),
            ],
          ),
        );
      },
    );
  }



  // 🔹 CADA POST (COM ANIMAÇÃO DE CORAÇÃO) 🔹
  Widget _buildPostItem(DocumentSnapshot post) {
    final data = post.data() as Map<String, dynamic>;
    final authorId = data['authorId'];
    final likes = data['likes'] as List<dynamic>? ?? [];
    final isLiked = likes.contains(_currentUserId);
    final postTime =
        (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

    return StreamBuilder<DocumentSnapshot>(
      stream:
      FirebaseFirestore.instance.collection('users').doc(authorId).snapshots(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        final authorName =
            userData?['displayName'] ?? data['authorName'] ?? 'Usuário';
        final photoUrl = userData?['photoURL'];

        return _AnimatedPostCard(
          photoUrl: photoUrl,
          authorName: authorName,
          postTime: postTime,
          imageUrl: data['imageUrl'],
          caption: data['text'],
          isLiked: isLiked,
          likes: likes.length,
          onLike: () => _toggleLike(post.id, authorId, likes),
          onComment: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) =>
                      CommentsPage(postId: post.id, postAuthorId: authorId))),
        );
      },
    );
  }

  Widget _emptyFeedMessage() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.photo_library_outlined, size: 60, color: Colors.black45),
        const SizedBox(height: 16),
        const Text(
          'Nenhuma publicação encontrada',
          style: TextStyle(color: Colors.black54, fontSize: 16),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const CreatePostPage())),
          icon: const Icon(Icons.add),
          label: const Text('Fazer uma publicação'),
        ),
      ]),
    );
  }
}

// 🔹 CLASSE SEPARADA PARA O CARD COM ANIMAÇÃO 🔹
class _AnimatedPostCard extends StatefulWidget {
  final String? photoUrl;
  final String authorName;
  final DateTime postTime;
  final String? imageUrl;
  final String? caption;
  final bool isLiked;
  final int likes;
  final VoidCallback onLike;
  final VoidCallback onComment;

  const _AnimatedPostCard({
    required this.photoUrl,
    required this.authorName,
    required this.postTime,
    required this.imageUrl,
    required this.caption,
    required this.isLiked,
    required this.likes,
    required this.onLike,
    required this.onComment,
  });

  @override
  State<_AnimatedPostCard> createState() => _AnimatedPostCardState();
}

class _AnimatedPostCardState extends State<_AnimatedPostCard>
    with SingleTickerProviderStateMixin {
  bool showHeart = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _scaleAnimation =
        Tween<double>(begin: 0.8, end: 1.2).chain(CurveTween(curve: Curves.easeOut))
            .animate(_controller);
  }

  void _triggerHeartAnimation() {
    setState(() => showHeart = true);
    _controller.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => showHeart = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Cabeçalho
        ListTile(
          leading: CircleAvatar(
            radius: 20,
            backgroundImage: (widget.photoUrl != null && widget.photoUrl!.isNotEmpty)
                ? NetworkImage(widget.photoUrl!)
                : const AssetImage('assets/icon/logo_principal.png')
            as ImageProvider,
          ),
          title: Text(widget.authorName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(timeago.format(widget.postTime, locale: 'pt_BR'),
              style: const TextStyle(color: Colors.black54, fontSize: 12)),
          trailing: const Icon(Icons.more_vert),
        ),

        // Imagem com animação
        if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
          GestureDetector(
            onDoubleTap: () {
              widget.onLike();
              _triggerHeartAnimation();
            },
            child: Stack(alignment: Alignment.center, children: [
              Image.network(widget.imageUrl!,
                  width: double.infinity, fit: BoxFit.cover),
              if (showHeart)
                ScaleTransition(
                  scale: _scaleAnimation,
                  child: const Icon(Icons.favorite,
                      color: Colors.white, size: 100, shadows: [
                        Shadow(color: Colors.black54, blurRadius: 10)
                      ]),
                ),
            ]),
          ),

        // Botões
        Row(children: [
          IconButton(
            icon: Icon(widget.isLiked ? Icons.favorite : Icons.favorite_border,
                color: widget.isLiked ? Colors.red : Colors.black87),
            onPressed: widget.onLike,
          ),
          IconButton(
              icon: const Icon(Icons.chat_bubble_outline, color: Colors.black87),
              onPressed: widget.onComment),
          const Spacer(),
          IconButton(
              icon: const Icon(Icons.share_outlined, color: Colors.black87),
              onPressed: () {}),
        ]),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('${widget.likes} curtidas',
              style:
              const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
        ),

        if (widget.caption != null && widget.caption!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: RichText(
              text: TextSpan(style: const TextStyle(color: Colors.black), children: [
                TextSpan(
                    text: '${widget.authorName} ',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: widget.caption!),
              ]),
            ),
          ),
        const SizedBox(height: 10),
      ]),
    );
  }
}
