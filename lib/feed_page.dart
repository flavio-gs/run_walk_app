import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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
  String _selectedFeed = 'following'; // valores: 'following' ou 'global'

  final _currentUserId = FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
    _setupFeedStream();
  }

  Widget _buildFeedToggleButton(String label, String mode) {
    final bool isSelected = _selectedFeed == mode;
    return GestureDetector(
      onTap: () {
        if (_selectedFeed != mode) {
          setState(() {
            _selectedFeed = mode;
            _setupFeedStream(); // recarrega posts
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00C853) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF00C853) : Colors.grey.shade400,
            width: 1.3,
          ),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: const Color(0xFF00C853).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }


  Future<void> _setupFeedStream() async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(_currentUserId);
    final followingSnapshot = await userRef.collection('following').get();

    List<String> followingIds = followingSnapshot.docs.map((doc) => doc.id).toList();

    Query query = FirebaseFirestore.instance.collection('posts');

    if (_selectedFeed == 'following') {
      // mostra apenas quem sigo (e eu mesmo)
      followingIds.add(_currentUserId);
      query = query.where('authorId', whereIn: followingIds);
    } else {
      // modo global: mostra posts de quem eu NÃO sigo
      query = query.where('authorId', whereNotIn: followingIds.length < 10 ? [...followingIds, _currentUserId] : followingIds.take(10).toList());
      // Firestore limita whereNotIn a 10 elementos, então tratamos listas grandes
    }

    if (mounted) {
      setState(() {
        _postsStream = query.orderBy('timestamp', descending: true).snapshots();
        _isLoading = false;
      });
    }
  }


  Future<void> _toggleLike(
      String postId,
      String authorId,
      String? currentReactionOfMe,
      ) async {
    final userId = _currentUserId;
    final reactionRef = FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .collection('reactions')
        .doc(userId);

    // Tap simples: curtir (like) se não tiver reação; remover se já for like
    if (currentReactionOfMe == 'like') {
      await reactionRef.delete();
    } else if (currentReactionOfMe == null) {
      await reactionRef.set({
        'type': 'like',
        'timestamp': FieldValue.serverTimestamp(),
      });
      if (userId != authorId) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(authorId)
            .collection('notifications')
            .add({
          'type': 'like',
          'message':
          '${FirebaseAuth.instance.currentUser?.displayName ?? 'Alguém'} curtiu sua publicação.',
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    } else {
      // tinha outra reação (ex: love/haha/strong) → vira like
      await reactionRef.update({
        'type': 'like',
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'RunFeed',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SearchUsersPage()),
            ).then((_) => _setupFeedStream()),
          ),
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CreatePostPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.favorite_border),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const NotificationsPage(),
              ),
            ),
          ),
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildFeedToggleButton('Seguindo', 'following'),
                  const SizedBox(width: 12),
                  _buildFeedToggleButton('Global', 'global'),
                ],
              ),
            ),

            const Divider(height: 1, color: Colors.black26),
            ...posts.map((post) => _buildPostItem(post)).toList(),
          ],
        );
      },
    );
  }

  // STORIES
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

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: users.length + 1,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            itemBuilder: (context, index) {
              if (index == 0) {
                final photoUrl = currentUser?.photoURL;
                return GestureDetector(
                  onTap: () => _showAddStoryOptions(context),
                  child: Column(
                    children: [
                      Stack(
                        children: [
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
                              backgroundImage: (photoUrl != null &&
                                  photoUrl.isNotEmpty)
                                  ? NetworkImage(photoUrl)
                                  : const AssetImage(
                                  'assets/icon/logo_principal.png')
                              as ImageProvider,
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.blueAccent,
                                border:
                                Border.all(color: Colors.white, width: 2),
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
                          style:
                          TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                );
              }

              final userDoc = users[index - 1];
              final userData = userDoc.data() as Map<String, dynamic>;
              final userId = userDoc.id;
              final name = userData['displayName'] ?? 'Usuário';
              final photoUrl = userData['photoURL'];

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('stories')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, storySnap) {
                  if (!storySnap.hasData || storySnap.data!.docs.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  final stories = storySnap.data!.docs.where((doc) {
                    final expiresAt =
                    DateTime.tryParse(doc['expiresAt'] ?? '');
                    return expiresAt != null &&
                        expiresAt.isAfter(DateTime.now());
                  }).toList();

                  if (stories.isEmpty) return const SizedBox.shrink();

                  final latestStory =
                  stories.first.data() as Map<String, dynamic>;

                  return GestureDetector(
                    onTap: () => _openStoryViewer(stories, name, photoUrl),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        children: [
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFFFF9100), Color(0xFF00C853)],
                              ),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(3),
                            child: CircleAvatar(
                              radius: 30,
                              backgroundImage:
                              NetworkImage(latestStory['imageUrl']),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(name.split(' ').first,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black54)),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

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
                  _addStory(ImageSource.camera);
                },
              ),
              ListTile(
                leading:
                const Icon(Icons.photo_library_rounded, color: Colors.green),
                title: const Text('Escolher da galeria'),
                subtitle: const Text('Selecione uma imagem existente'),
                onTap: () {
                  Navigator.pop(context);
                  _addStory(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 15),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addStory(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile =
      await picker.pickImage(source: source, imageQuality: 85);
      if (pickedFile == null) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final file = File(pickedFile.path);

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('stories')
          .child(user.uid)
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      await storageRef.putFile(file);
      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('stories')
          .add({
        'imageUrl': downloadUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'expiresAt':
        DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Story adicionado com sucesso!')),
      );
    } catch (e) {
      debugPrint("Erro ao enviar story: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  void _openStoryViewer(
      List<QueryDocumentSnapshot> stories,
      String name,
      String? photoUrl,
      ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          body: PageView.builder(
            itemCount: stories.length,
            itemBuilder: (context, index) {
              final data = stories[index].data() as Map<String, dynamic>;
              return Stack(
                children: [
                  Positioned.fill(
                    child: Image.network(
                      data['imageUrl'],
                      fit: BoxFit.cover,
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundImage: (photoUrl != null &&
                                photoUrl.isNotEmpty)
                                ? NetworkImage(photoUrl)
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 40,
                    right: 15,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
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

  // ITEM DO FEED
  Widget _buildPostItem(DocumentSnapshot post) {
    final data = post.data() as Map<String, dynamic>;
    final authorId = data['authorId'] as String;
    final postId = post.id;
    final postTime =
        (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(authorId)
          .snapshots(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        final authorName =
            userData?['displayName'] ?? data['authorName'] ?? 'Usuário';
        final photoUrl = userData?['photoURL'];

        return _AnimatedPostCard(
          postId: postId,
          authorId: authorId,
          photoUrl: photoUrl,
          authorName: authorName,
          postTime: postTime,
          imageUrl: data['imageUrl'],
          caption: data['text'],
          onLikeTap: (myReaction) =>
              _toggleLike(postId, authorId, myReaction), // tap simples
          onComment: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  CommentsPage(postId: postId, postAuthorId: authorId),
            ),
          ),
        );
      },
    );
  }

  Widget _emptyFeedMessage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo_library_outlined,
              size: 60, color: Colors.black45),
          const SizedBox(height: 16),
          const Text(
            'Nenhuma publicação encontrada',
            style: TextStyle(color: Colors.black54, fontSize: 16),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CreatePostPage()),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Fazer uma publicação'),
          ),
        ],
      ),
    );
  }
}

// =======================
// CARD DO POST + REAÇÕES
// =======================
class _AnimatedPostCard extends StatefulWidget {
  final String postId;
  final String authorId;
  final String? photoUrl;
  final String authorName;
  final DateTime postTime;
  final String? imageUrl;
  final String? caption;
  final Future<void> Function(String? myCurrentReaction) onLikeTap;
  final VoidCallback onComment;

  const _AnimatedPostCard({
    required this.postId,
    required this.authorId,
    required this.photoUrl,
    required this.authorName,
    required this.postTime,
    required this.imageUrl,
    required this.caption,
    required this.onLikeTap,
    required this.onComment,
    super.key,
  });

  @override
  State<_AnimatedPostCard> createState() => _AnimatedPostCardState();
}

class _AnimatedPostCardState extends State<_AnimatedPostCard>
    with TickerProviderStateMixin {
  // coração no double tap
  bool showHeart = false;
  late final AnimationController _heartController =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final Animation<double> _heartScale = Tween<double>(begin: 0.7, end: 1.3)
      .chain(CurveTween(curve: Curves.easeOutBack))
      .animate(_heartController);

  // overlay de reações
  bool showOverlay = false;
  late final AnimationController _overlayController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  late final Animation<double> _overlayScale =
  Tween<double>(begin: 0.9, end: 1.0).animate(_overlayController);
  late final Animation<double> _overlayFade =
  Tween<double>(begin: 0.0, end: 1.0).animate(_overlayController);

  @override
  void dispose() {
    _heartController.dispose();
    _overlayController.dispose();
    super.dispose();
  }

  void _triggerHeart() async {
    setState(() => showHeart = true);
    _heartController.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) setState(() => showHeart = false);
  }

  Future<void> _setReaction(String? type) async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('reactions')
        .doc(userId);

    if (type == null) {
      await ref.delete();
    } else {
      await ref.set({
        'type': type,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  // Mapa de emojis/labels
  static const Map<String, String> _emoji = {
    'love': '❤️',
    'haha': '😂',
    'strong': '💪',
    'like': '👍',
  };

  static const Map<String, String> _label = {
    'love': 'Amei',
    'haha': 'Haha',
    'strong': 'Força',
    'like': 'Curtir',
  };

  @override
  Widget build(BuildContext context) {
    final reactionsCol = FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('reactions');

    final myDoc = reactionsCol.doc(FirebaseAuth.instance.currentUser!.uid).snapshots();
    final allDocs = reactionsCol.snapshots();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (showOverlay) {
          setState(() => showOverlay = false);
          _overlayController.reverse();
        }
      },
      child: Container(
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cabeçalho
                ListTile(
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundImage: (widget.photoUrl != null &&
                        widget.photoUrl!.isNotEmpty)
                        ? NetworkImage(widget.photoUrl!)
                        : const AssetImage('assets/icon/logo_principal.png')
                    as ImageProvider,
                  ),
                  title: Text(widget.authorName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    timeago.format(widget.postTime, locale: 'pt_BR'),
                    style:
                    const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  trailing: const Icon(Icons.more_vert),
                ),

                // Imagem com double tap = curtir (like) + coração
                if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
                  StreamBuilder<DocumentSnapshot>(
                    stream: myDoc,
                    builder: (context, mySnap) {
                      final myReaction =
                      (mySnap.data?.data() as Map<String, dynamic>?)?['type']
                      as String?;
                      return GestureDetector(
                        onDoubleTap: () async {
                          // double tap faz "like" (ou remove se já for like)
                          await widget.onLikeTap(myReaction);
                          _triggerHeart();
                          HapticFeedback.lightImpact();
                        },
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Image.network(
                              widget.imageUrl!,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                            if (showHeart)
                              ScaleTransition(
                                scale: _heartScale,
                                child: const Icon(
                                  Icons.favorite_rounded,
                                  color: Colors.white,
                                  size: 110,
                                  shadows: [
                                    Shadow(
                                        color: Colors.black54, blurRadius: 12)
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),

                // Linha de botões (Like / Comment / Share)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Row(
                    children: [
                      // Botão de curtir com tap e long-press
                      StreamBuilder<DocumentSnapshot>(
                        stream: myDoc,
                        builder: (context, mySnap) {
                          final myType =
                          (mySnap.data?.data() as Map<String, dynamic>?)?['type']
                          as String?;
                          final isActive = myType != null;
                          final text = _label[myType ?? 'like'] ?? 'Curtir';
                          final color = myType == 'love'
                              ? Colors.redAccent
                              : (isActive ? Colors.blueAccent : Colors.black87);
                          final icon = myType == 'love'
                              ? Icons.favorite_rounded
                              : Icons.thumb_up_alt_rounded;

                          return GestureDetector(
                            onTap: () => widget.onLikeTap(myType),
                            onLongPressStart: (_) {
                              setState(() => showOverlay = true);
                              _overlayController.forward(from: 0);
                              HapticFeedback.selectionClick();
                            },
                            child: Padding(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 6.0),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? color.withOpacity(0.08)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Row(
                                  children: [
                                    Icon(icon, color: color, size: 22),
                                    const SizedBox(width: 6),
                                    Text(
                                      text,
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('posts')
                            .doc(widget.postId)
                            .collection('comments')
                            .snapshots(),
                        builder: (context, snapshot) {
                          final count = snapshot.data?.docs.length ?? 0;
                          return GestureDetector(
                            onTap: widget.onComment,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.chat_bubble_outline, color: Colors.black87),
                                  const SizedBox(width: 4),
                                  Text(
                                    count.toString(),
                                    style: const TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.share_outlined,
                            color: Colors.black87),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),

                // Contador de reações por tipo + total
                StreamBuilder<QuerySnapshot>(
                  stream: allDocs,
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const SizedBox(height: 8);
                    }
                    final counts = <String, int>{
                      'love': 0,
                      'haha': 0,
                      'strong': 0,
                      'like': 0,
                    };
                    for (final d in snap.data!.docs) {
                      final type = (d.data() as Map<String, dynamic>)['type'];
                      if (counts.containsKey(type)) {
                        counts[type] = counts[type]! + 1;
                      }
                    }
                    final total = counts.values.fold<int>(0, (a, b) => a + b);
                    final nonZero = counts.entries
                        .where((e) => e.value > 0)
                        .toList()
                      ..sort((a, b) => b.value.compareTo(a.value)); // ranking

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: total == 0
                          ? const SizedBox.shrink()
                          : Row(
                        children: [
                          // Emojis com contagem
                          Flexible(
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 6,
                              children: nonZero.map((e) {
                                final emoji = _emoji[e.key] ?? '';
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(emoji, style: const TextStyle(fontSize: 16)),
                                    const SizedBox(width: 4),
                                    Text(
                                      e.value.toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '$total',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                // Legenda
                if (widget.caption != null && widget.caption!.isNotEmpty)
                  Padding(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(color: Colors.black),
                        children: [
                          TextSpan(
                            text: '${widget.authorName} ',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: widget.caption!),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
              ],
            ),

            // Overlay (balão) acima do botão de curtir
            if (showOverlay)
              Positioned(
                left: 12,
                bottom: 72, // sobe acima da linha de botões
                child: FadeTransition(
                  opacity: _overlayFade,
                  child: ScaleTransition(
                    scale: _overlayScale,
                    child: _ReactionsOverlay(
                      onSelect: (type) async {
                        await _setReaction(type);
                        if (mounted) {
                          setState(() => showOverlay = false);
                          _overlayController.reverse();
                        }
                        HapticFeedback.mediumImpact();
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================
// OVERLAY DE REAÇÕES (balão)
// ============================
class _ReactionsOverlay extends StatelessWidget {
  final void Function(String type) onSelect;
  const _ReactionsOverlay({required this.onSelect});

  static const reactions = [
    ('love', '❤️', 'Amei'),
    ('haha', '😂', 'Haha'),
    ('strong', '💪', 'Força'),
    ('like', '👍', 'Like'),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: reactions.map((e) {
            final type = e.$1;
            final emoji = e.$2;
            final label = e.$3;
            return _ReactionBubble(
              emoji: emoji,
              label: label,
              onTap: () => onSelect(type),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ReactionBubble extends StatefulWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;
  const _ReactionBubble({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  @override
  State<_ReactionBubble> createState() => _ReactionBubbleState();
}

class _ReactionBubbleState extends State<_ReactionBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );
  late final Animation<double> _scale =
  Tween<double>(begin: 1.0, end: 1.2).animate(_c);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _c.forward(),
      onExit: (_) => _c.reverse(),
      child: GestureDetector(
        onTapDown: (_) => _c.forward(),
        onTapCancel: () => _c.reverse(),
        onTapUp: (_) => _c.reverse(),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _scale,
                child: CircleAvatar(
                  backgroundColor: Colors.white,
                  radius: 22,
                  child: Text(widget.emoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.label,
                style: const TextStyle(fontSize: 11, color: Colors.black87),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
