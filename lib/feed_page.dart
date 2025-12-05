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
import 'package:run_walk_app/create_challenge_page.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:run_walk_app/profile_page.dart';
import 'package:video_player/video_player.dart';

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

  // 🌟 Stream para contar as notificações não lidas
  late final Stream<int> _unreadNotificationsCountStream;

  @override
  void initState() {
    super.initState();
    timeago.setLocaleMessages('pt_BR', timeago.PtBrMessages());
    _setupFeedStream();

    _unreadNotificationsCountStream = _getUnreadNotificationsCountStream();
  }

  Stream<int> _getUnreadNotificationsCountStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
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
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const Text(
                'Crie algo incrível!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              _buildCreateOption(
                icon: Icons.edit,
                color: Colors.deepPurpleAccent,
                title: 'Faça uma Publicação',
                subtitle: 'Compartilhe sua corrida, foto ou reflexão do dia',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const CreatePostPage()),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openChallengeCreator() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🔰 Criador de Desafios em desenvolvimento!')),
    );
  }

  void _startRunSession() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🏃 Corrida iniciada!')),
    );
  }

  void _publishAchievement() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🏆 Publique sua conquista em breve!')),
    );
  }

  void _exploreRoutes() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🗺️ Exploração de rotas chegando!')),
    );
  }

  Widget _buildCreateOption({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: color.withOpacity(0.15),
        child: Icon(icon, color: color, size: 26),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 13, color: Colors.black54),
      ),
      onTap: onTap,
    );
  }

  Widget _buildFeedToggleButton(String label, String mode) {
    final bool isSelected = _selectedFeed == mode;
    return GestureDetector(
      onTap: () {
        if (_selectedFeed != mode) {
          setState(() {
            _selectedFeed = mode;
            _setupFeedStream();
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
    final userRef =
    FirebaseFirestore.instance.collection('users').doc(_currentUserId);
    final followingSnapshot = await userRef.collection('following').get();

    List<String> followingIds =
    followingSnapshot.docs.map((doc) => doc.id).toList();

    Query query = FirebaseFirestore.instance.collection('posts');

    if (_selectedFeed == 'following') {
      if (followingIds.isEmpty) {
        query = query.where('authorId', isEqualTo: _currentUserId);
      } else {
        followingIds.add(_currentUserId);
        query = query.where('authorId', whereIn: followingIds);
      }
    } else {
      if (followingIds.isEmpty) {
        query = FirebaseFirestore.instance.collection('posts');
      } else {
        final excluded = [...followingIds, _currentUserId];
        query = query.where(
          'authorId',
          whereNotIn:
          excluded.length > 10 ? excluded.take(10).toList() : excluded,
        );
      }
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
          'senderName':
          FirebaseAuth.instance.currentUser?.displayName ?? 'Alguém',
          'senderId': userId,
          'senderPhotoUrl': FirebaseAuth.instance.currentUser?.photoURL,
          'message':
          '${FirebaseAuth.instance.currentUser?.displayName ?? 'Alguém'} curtiu sua publicação.',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      }
    } else {
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
            onPressed: () => _showCreateOptions(context),
          ),
          StreamBuilder<int>(
            stream: _unreadNotificationsCountStream,
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;

              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.favorite_border),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const NotificationsPage(),
                      ),
                    ),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    )
                ],
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildFeedBody(),
    );
  }

  Widget _buildFeedBody() {
    return Column(
      children: [
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
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _postsStream,
            builder: (context, snapshot) {
              if (_isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _emptyFeedMessage();
              }

              final posts = snapshot.data!.docs;
              return ListView.builder(
                itemCount: posts.length,
                itemBuilder: (context, index) => _buildPostItem(posts[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  // STORIES (mantidos para uso futuro, se quiser ativar)
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
                leading: const Icon(Icons.photo_library_rounded,
                    color: Colors.green),
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
    final type = data['type'] ?? 'post';

    final authorId = data['authorId'] as String;
    final postId = post.id;
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

        if (type == 'challenge') {
          return ChallengePostCard(
            postId: post.id,
            data: data,
            currentUserId: _currentUserId,
          );
        }
        if (type == 'achievement') {
          return _AchievementPostCard(data: data);
        }

        // 🎯 Mídia
        final mediaType = data['mediaType'] as String?;
        final mediaUrl = data['mediaUrl'] as String?;
        final imageUrl = data['imageUrl'] as String?;
        final videoUrl = data['videoUrl'] as String?;

        final resolvedType = mediaType ??
            (videoUrl != null && videoUrl.isNotEmpty
                ? 'video'
                : (imageUrl != null && imageUrl.isNotEmpty ? 'image' : 'none'));

        final resolvedUrl = resolvedType == 'video'
            ? (mediaUrl ?? videoUrl)
            : (mediaUrl ?? imageUrl);

        // 🏃‍♂️ resumo da corrida (opcional)
        final hasRun = data['hasRun'] == true;
        final runSummaryRaw =
        data['runSummary'] as Map<String, dynamic>?; // pode ser null

        double? distanceKm;
        int? durationSec;
        double? pace;

        if (hasRun && runSummaryRaw != null) {
          final d = runSummaryRaw['distanceKm'];
          final t = runSummaryRaw['durationSec'];
          final p = runSummaryRaw['pace'];

          if (d is num) distanceKm = d.toDouble();
          if (t is num) durationSec = t.toInt();
          if (p is num) pace = p.toDouble();
        }

        // 📍 localização (opcional)
        final hasLocation = data['hasLocation'] == true;
        final locRaw = data['location'] as Map<String, dynamic>?;

        double? locLat;
        double? locLng;
        if (hasLocation && locRaw != null) {
          final lt = locRaw['lat'];
          final lg = locRaw['lng'];
          if (lt is num) locLat = lt.toDouble();
          if (lg is num) locLng = lg.toDouble();
        }

        return _AnimatedPostCard(
          postId: postId,
          authorId: authorId,
          photoUrl: photoUrl,
          authorName: authorName,
          postTime: postTime,
          imageUrl: imageUrl,
          mediaType: resolvedType,
          mediaUrl: resolvedUrl,
          caption: data['text'],

          // corrida
          hasRun: hasRun,
          distanceKm: distanceKm,
          durationSec: durationSec,
          pace: pace,

          // localização
          hasLocation: hasLocation,
          locLat: locLat,
          locLng: locLng,

          onLikeTap: (myReaction) =>
              _toggleLike(postId, authorId, myReaction),
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

class _AchievementPostCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AchievementPostCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final icon = data['icon'] ?? '🏆';
    final title = data['title'] ?? 'Conquista Desconhecida';
    final userName = data['authorName'] ?? 'Jogador';
    final timestamp =
        (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: Colors.white,
      elevation: 3,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.amber.shade50, Colors.white],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 36)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("$userName conquistou:",
                      style:
                      const TextStyle(fontSize: 13, color: Colors.black54)),
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                    timeago.format(timestamp, locale: 'pt_BR'),
                    style: const TextStyle(
                        fontSize: 11, color: Colors.black45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunStat extends StatelessWidget {
  final String label;
  final String value;
  const _RunStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.black54)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
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
  final String? mediaType; // 'image' | 'video' | 'none'
  final String? mediaUrl;
  final String? caption;
  final Future<void> Function(String? myCurrentReaction) onLikeTap;
  final VoidCallback onComment;

  // 🏃‍♂️ corrida
  final bool hasRun;
  final double? distanceKm;
  final int? durationSec;
  final double? pace;

  // 📍 localização
  final bool hasLocation;
  final double? locLat;
  final double? locLng;

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
    this.mediaType,
    this.mediaUrl,
    this.hasRun = false,
    this.distanceKm,
    this.durationSec,
    this.pace,
    this.hasLocation = false,
    this.locLat,
    this.locLng,
    super.key,
  });

  @override
  State<_AnimatedPostCard> createState() => _AnimatedPostCardState();
}

class _AnimatedPostCardState extends State<_AnimatedPostCard>
    with TickerProviderStateMixin {
  bool showHeart = false;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isVideoPlaying = false;

  late final AnimationController _heartController =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final Animation<double> _heartScale = Tween<double>(begin: 0.7, end: 1.3)
      .chain(CurveTween(curve: Curves.easeOutBack))
      .animate(_heartController);

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
  void initState() {
    super.initState();
    if (widget.mediaType == 'video' && widget.mediaUrl != null) {
      _initVideoController();
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedPostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIsVideo =
        oldWidget.mediaType == 'video' && oldWidget.mediaUrl != null;
    final newIsVideo =
        widget.mediaType == 'video' && widget.mediaUrl != null;

    if (newIsVideo && (!oldIsVideo || oldWidget.mediaUrl != widget.mediaUrl)) {
      _initVideoController();
    } else if (!newIsVideo && oldIsVideo) {
      _disposeVideoController();
    }
  }

  String _formatDuration(int totalSeconds) {
    final d = Duration(seconds: totalSeconds);
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Widget _buildRunAndLocationCard() {
    final hasRunData = widget.hasRun &&
        widget.distanceKm != null &&
        widget.durationSec != null &&
        widget.pace != null;

    final hasLocData =
        widget.hasLocation && widget.locLat != null && widget.locLng != null;

    if (!hasRunData && !hasLocData) {
      return const SizedBox.shrink();
    }

    Widget metric(String label, String value) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F6F6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE0F5E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.directions_run,
                  color: Colors.green, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasRunData)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        metric('Distância',
                            '${widget.distanceKm!.toStringAsFixed(2)} km'),
                        metric('Tempo', _formatDuration(widget.durationSec!)),
                        metric('Pace',
                            '${widget.pace!.toStringAsFixed(2)} min/km'),
                      ],
                    ),
                  if (hasRunData && hasLocData) const SizedBox(height: 6),
                  if (hasLocData)
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            size: 16, color: Colors.redAccent),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Perto de (${widget.locLat!.toStringAsFixed(4)}, '
                                '${widget.locLng!.toStringAsFixed(4)})',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _heartController.dispose();
    _overlayController.dispose();
    _disposeVideoController();
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

  Future<void> _initVideoController() async {
    if (widget.mediaType != 'video' || widget.mediaUrl == null) return;

    _videoController?.dispose();
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(widget.mediaUrl!),
    )..setLooping(true);

    try {
      await _videoController!.initialize();
      if (!mounted) return;
      setState(() {
        _isVideoInitialized = true;
      });
    } catch (e) {
      debugPrint('Erro ao inicializar vídeo: $e');
    }
  }

  void _disposeVideoController() {
    _videoController?.dispose();
    _videoController = null;
    _isVideoInitialized = false;
    _isVideoPlaying = false;
  }

  Widget _buildVideoPlayer() {
    if (_videoController == null) {
      return Container(
        height: 260,
        color: Colors.black12,
        child: const Center(
          child: Icon(Icons.videocam_off, size: 40, color: Colors.black45),
        ),
      );
    }

    if (!_isVideoInitialized) {
      return Container(
        height: 260,
        color: Colors.black12,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final aspect = _videoController!.value.aspectRatio == 0
        ? 16 / 9
        : _videoController!.value.aspectRatio;

    return AspectRatio(
      aspectRatio: aspect,
      child: VideoPlayer(_videoController!),
    );
  }

  void _showPostOptions(BuildContext context) async {
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    final isOwner = widget.authorId == currentUserId;

    final followingRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('following')
        .doc(widget.authorId);
    final followingSnap = await followingRef.get();
    final isFollowing = followingSnap.exists;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              if (isOwner) ...[
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.blueAccent),
                  title: const Text('Editar publicação'),
                  onTap: () {
                    Navigator.pop(context);
                    _openEditPostModal(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.redAccent),
                  title: const Text('Excluir publicação'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _confirmDeletePost(context);
                  },
                ),
              ] else if (!isFollowing) ...[
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_rounded,
                      color: Colors.green),
                  title: const Text('Seguir jogador'),
                  onTap: () async {
                    Navigator.pop(context);
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(currentUserId)
                        .collection('following')
                        .doc(widget.authorId)
                        .set({
                      'timestamp': FieldValue.serverTimestamp(),
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                          Text('✅ Agora você está seguindo este jogador!')),
                    );
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.person_remove_alt_1,
                      color: Colors.orange),
                  title: const Text('Deixar de seguir jogador'),
                  onTap: () async {
                    Navigator.pop(context);
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(currentUserId)
                        .collection('following')
                        .doc(widget.authorId)
                        .delete();

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content:
                          Text('👋 Você deixou de seguir este jogador.')),
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeletePost(BuildContext context) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Excluir publicação'),
        content: const Text(
          'Tem certeza que deseja excluir esta publicação?\nEssa ação não pode ser desfeita.',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance
                  .collection('posts')
                  .doc(widget.postId)
                  .delete();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('🗑️ Publicação excluída com sucesso!')),
              );
            },
            icon: const Icon(Icons.delete, color: Colors.white),
            label: const Text('Excluir'),
            style:
            ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
          ),
        ],
      ),
    );
  }

  void _openEditPostModal(BuildContext context) {
    final TextEditingController captionController =
    TextEditingController(text: widget.caption ?? '');
    String? updatedImageUrl = widget.imageUrl;
    bool isUpdating = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 25,
                bottom: MediaQuery.of(context).viewInsets.bottom + 25,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '✏️ Editar Publicação',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: captionController,
                      maxLines: null,
                      decoration: InputDecoration(
                        hintText: 'Escreva algo...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: isUpdating
                          ? null
                          : () async {
                        setModalState(() => isUpdating = true);

                        await FirebaseFirestore.instance
                            .collection('posts')
                            .doc(widget.postId)
                            .update({
                          'text': captionController.text.trim(),
                          'imageUrl': updatedImageUrl,
                        });

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    '✅ Publicação atualizada com sucesso!')),
                          );
                        }
                      },
                      icon: isUpdating
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Icon(Icons.check_circle_outline,
                          color: Colors.white),
                      label: const Text('Salvar alterações'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        minimumSize: const Size(double.infinity, 45),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

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

    final myDoc =
    reactionsCol.doc(FirebaseAuth.instance.currentUser!.uid).snapshots();
    final allDocs = reactionsCol.snapshots();

    final hasImage =
        widget.imageUrl != null && widget.imageUrl!.isNotEmpty;
    final isVideo =
        widget.mediaType == 'video' && widget.mediaUrl != null;

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
                  leading: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ProfilePage(userId: widget.authorId),
                        ),
                      );
                    },
                    child: CircleAvatar(
                      radius: 20,
                      backgroundImage: (widget.photoUrl != null &&
                          widget.photoUrl!.isNotEmpty)
                          ? NetworkImage(widget.photoUrl!)
                          : const AssetImage(
                          'assets/icon/logo_principal.png')
                      as ImageProvider,
                    ),
                  ),
                  title: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ProfilePage(userId: widget.authorId),
                        ),
                      );
                    },
                    child: Text(
                      widget.authorName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  subtitle: Text(
                    timeago.format(widget.postTime, locale: 'pt_BR'),
                    style: const TextStyle(
                        color: Colors.black54, fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showPostOptions(context),
                  ),
                ),

                // 🏃‍♂️ / 📍 Card de corrida + localização
                _buildRunAndLocationCard(),

                // Mídia (foto ou vídeo)
                if (hasImage || isVideo)
                  StreamBuilder<DocumentSnapshot>(
                    stream: myDoc,
                    builder: (context, mySnap) {
                      final myReaction =
                      (mySnap.data?.data() as Map<String, dynamic>?)?['type']
                      as String?;

                      return GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          if (isVideo &&
                              _videoController != null &&
                              _isVideoInitialized) {
                            setState(() {
                              if (_videoController!.value.isPlaying) {
                                _videoController!.pause();
                                _isVideoPlaying = false;
                              } else {
                                _videoController!.play();
                                _isVideoPlaying = true;
                              }
                            });
                          }
                        },
                        onDoubleTap: () async {
                          await widget.onLikeTap(myReaction);
                          _triggerHeart();
                          HapticFeedback.lightImpact();
                        },
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (isVideo)
                              _buildVideoPlayer()
                            else
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
                                        color: Colors.black54,
                                        blurRadius: 12),
                                  ],
                                ),
                              ),
                            if (isVideo &&
                                _videoController != null &&
                                _isVideoInitialized)
                              Positioned(
                                bottom: 12,
                                right: 12,
                                child: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Colors.black54,
                                  child: Icon(
                                    _videoController!.value.isPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    color: Colors.white,
                                  ),
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
                          (mySnap.data?.data()
                          as Map<String, dynamic>?)?['type']
                          as String?;
                          final isActive = myType != null;
                          final text =
                              _label[myType ?? 'like'] ?? 'Curtir';
                          final color = myType == 'love'
                              ? Colors.redAccent
                              : (isActive
                              ? Colors.blueAccent
                              : Colors.black87);
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6.0),
                              child: AnimatedContainer(
                                duration:
                                const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? color.withOpacity(0.08)
                                      : Colors.transparent,
                                  borderRadius:
                                  BorderRadius.circular(18),
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
                          final count =
                              snapshot.data?.docs.length ?? 0;
                          return GestureDetector(
                            onTap: widget.onComment,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6.0, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                      Icons.chat_bubble_outline,
                                      color: Colors.black87),
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
                      final type =
                      (d.data() as Map<String, dynamic>)['type'];
                      if (counts.containsKey(type)) {
                        counts[type] = counts[type]! + 1;
                      }
                    }
                    final total =
                    counts.values.fold<int>(0, (a, b) => a + b);
                    final nonZero = counts.entries
                        .where((e) => e.value > 0)
                        .toList()
                      ..sort((a, b) =>
                          b.value.compareTo(a.value));

                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: total == 0
                          ? const SizedBox.shrink()
                          : Row(
                        children: [
                          Flexible(
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 6,
                              children: nonZero.map((e) {
                                final emoji =
                                    _emoji[e.key] ?? '';
                                return Row(
                                  mainAxisSize:
                                  MainAxisSize.min,
                                  children: [
                                    Text(emoji,
                                        style:
                                        const TextStyle(
                                            fontSize:
                                            16)),
                                    const SizedBox(width: 4),
                                    Text(
                                      e.value.toString(),
                                      style: const TextStyle(
                                        fontWeight:
                                        FontWeight.bold,
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
                if (widget.caption != null &&
                    widget.caption!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(color: Colors.black),
                        children: [
                          TextSpan(
                            text: '${widget.authorName} ',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold),
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
                bottom: 72,
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
        padding:
        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
  State<_ReactionBubble> createState() =>
      _ReactionBubbleState();
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
                  child: Text(widget.emoji,
                      style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.label,
                style: const TextStyle(
                    fontSize: 11, color: Colors.black87),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ====================================
// ChallengePostCard (desafios)
// ====================================
class ChallengePostCard extends StatefulWidget {
  final String postId;
  final Map<String, dynamic> data;
  final String currentUserId;

  const ChallengePostCard({
    super.key,
    required this.postId,
    required this.data,
    required this.currentUserId,
  });

  @override
  State<ChallengePostCard> createState() =>
      _ChallengePostCardState();
}

class _ChallengePostCardState extends State<ChallengePostCard> {
  bool _loading = false;
  Map<String, dynamic>? _authorData;

  @override
  void initState() {
    super.initState();
    _loadAuthorData();
  }

  Future<void> _loadAuthorData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.data['authorId'])
          .get();
      if (doc.exists) setState(() => _authorData = doc.data());
    } catch (e) {
      debugPrint("Erro ao carregar autor do desafio: $e");
    }
  }

  Future<void> _acceptChallenge() async {
    setState(() => _loading = true);
    final ref =
    FirebaseFirestore.instance.collection('posts').doc(widget.postId);

    await ref.update({
      'participants':
      FieldValue.arrayUnion([widget.currentUserId]),
      'progress.${widget.currentUserId}': {
        'distance': 0.0,
        'status': 'in_progress',
      },
    });

    setState(() => _loading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('🔥 Você entrou no desafio! Boa sorte!')),
    );
  }

  Future<void> _confirmCancelChallenge() async {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder:
          (context, animation, secondaryAnimation, child) {
        final curvedValue =
            Curves.easeOutBack.transform(animation.value) - 1.0;

        return Transform.translate(
          offset: Offset(curvedValue * 20, 0),
          child: Opacity(
            opacity: animation.value,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange, size: 28),
                  SizedBox(width: 8),
                  Text(
                    'Tem certeza?',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: const Text(
                'Se você desistir agora, seu nome vai brilhar no mural dos desistentes 😏\n\n'
                    'Pense bem... os outros jogadores vão ver 👀',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.4),
              ),
              actionsAlignment:
              MainAxisAlignment.spaceBetween,
              actions: [
                TextButton.icon(
                  icon: const Icon(
                      Icons.sports_motorsports_rounded,
                      color: Colors.green),
                  label: const Text(
                    'Continuar no desafio',
                    style: TextStyle(color: Colors.green),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.exit_to_app_rounded,
                      color: Colors.white),
                  label: const Text('Desistir'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    await _cancelChallenge();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _cancelChallenge() async {
    setState(() => _loading = true);
    final ref =
    FirebaseFirestore.instance.collection('posts').doc(widget.postId);

    await ref.update({
      'participants':
      FieldValue.arrayRemove([widget.currentUserId]),
      'quitters':
      FieldValue.arrayUnion([widget.currentUserId]),
      'progress.${widget.currentUserId}.status': 'cancelled',
    });

    setState(() => _loading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('❌ Você cancelou sua inscrição neste desafio.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final participants = List<String>.from(d['participants'] ?? []);
    final quitters = List<String>.from(d['quitters'] ?? []);
    final progress = Map<String, dynamic>.from(d['progress'] ?? {});
    final joined =
    participants.contains(widget.currentUserId);
    final totalKm = (d['distance'] ?? 0.0).toDouble();

    final authorName = _authorData?['displayName'] ??
        d['authorName'] ??
        'Jogador';
    final authorPhoto = _authorData?['photoURL'];

    return Card(
      margin: const EdgeInsets.symmetric(
          vertical: 8, horizontal: 12),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfilePage(
                            userId: widget.data['authorId']),
                      ),
                    );
                  },
                  child: CircleAvatar(
                    radius: 22,
                    backgroundImage: authorPhoto != null &&
                        authorPhoto.isNotEmpty
                        ? NetworkImage(authorPhoto)
                        : const AssetImage(
                        'assets/icon/logo_principal.png')
                    as ImageProvider,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfilePage(
                              userId: widget.data['authorId']),
                        ),
                      );
                    },
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Criado por $authorName',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Colors.black,
                          ),
                        ),
                        Text(
                          timeago.format(
                            (d['timestamp'] as Timestamp?)
                                ?.toDate() ??
                                DateTime.now(),
                            locale: 'pt_BR',
                          ),
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const Divider(
                height: 24,
                thickness: 1,
                color: Colors.black12),

            Text('🏁 ${d['title'] ?? 'Desafio de Corrida'}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
            const SizedBox(height: 8),
            Text('Distância: ${d['distance']} km',
                style: const TextStyle(
                    color: Colors.black87)),
            Text(
              'Prazo: ${d['deadline'].toDate().day}/${d['deadline'].toDate().month}/${d['deadline'].toDate().year}',
              style: const TextStyle(
                  color: Colors.black54),
            ),
            const SizedBox(height: 16),

            if (joined)
              ElevatedButton.icon(
                onPressed:
                _loading ? null : _confirmCancelChallenge,
                icon: const Icon(Icons.cancel,
                    color: Colors.white),
                label: _loading
                    ? const CircularProgressIndicator(
                    color: Colors.white)
                    : const Text('Cancelar inscrição'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  Colors.redAccent,
                  minimumSize:
                  const Size(double.infinity, 45),
                ),
              )
            else if (quitters
                .contains(widget.currentUserId))
              ElevatedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.block),
                label: const Text(
                    'Você desistiu deste desafio 😬'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                  minimumSize:
                  const Size(double.infinity, 45),
                ),
              )
            else
              ElevatedButton.icon(
                onPressed:
                _loading ? null : _acceptChallenge,
                icon: const Icon(Icons.flag),
                label: _loading
                    ? const CircularProgressIndicator(
                    color: Colors.white)
                    : const Text('Aceito o Desafio'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  minimumSize:
                  const Size(double.infinity, 45),
                ),
              ),
            const SizedBox(height: 20),

            const Text('Jogadores inscritos:',
                style: TextStyle(
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (participants.isEmpty)
              const Text('Ainda ninguém se inscreveu 😅')
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: participants.map((uid) {
                  return _buildPlayerAvatar(
                      uid, progress, totalKm);
                }).toList(),
              ),
            const SizedBox(height: 16),

            if (quitters.isNotEmpty) ...[
              const Divider(),
              const SizedBox(height: 6),
              const Text('Jogadores desistentes:',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.red)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: quitters.map((uid) {
                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .get(),
                    builder: (context, snapshot) {
                      final user =
                      snapshot.data?.data()
                      as Map<String, dynamic>?;
                      final name =
                          user?['displayName'] ?? 'Jogador';
                      final photo =
                      user?['photoURL'];
                      return Column(
                        mainAxisSize:
                        MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundImage: photo !=
                                null
                                ? NetworkImage(photo)
                                : const AssetImage(
                                'assets/icon/logo_principal.png')
                            as ImageProvider,
                            backgroundColor:
                            Colors.red.shade100,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            name.split(' ').first,
                            style: const TextStyle(
                                fontSize: 11,
                                color:
                                Colors.redAccent),
                          ),
                        ],
                      );
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 20),

            if (participants.isNotEmpty)
              Center(
                child: OutlinedButton.icon(
                  onPressed: () => _showRanking(
                      context, progress, totalKm),
                  icon: const Icon(
                      Icons.bar_chart_rounded,
                      color: Colors.blueAccent),
                  label: const Text(
                    "Ver Ranking",
                    style: TextStyle(
                        color: Colors.blueAccent,
                        fontWeight:
                        FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                        color: Colors.blueAccent),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerAvatar(String uid,
      Map<String, dynamic> progress, double totalKm) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(),
      builder: (context, snapshot) {
        final user =
        snapshot.data?.data() as Map<String, dynamic>?;
        final name =
            user?['displayName'] ?? 'Jogador';
        final photo =
        user?['photoURL'];
        final playerProgress =
        (progress[uid]?['distance'] ?? 0.0)
            .toDouble();
        final status =
            progress[uid]?['status'] ?? 'in_progress';

        return GestureDetector(
          onTap: () => _showPlayerProgress(
            context,
            name,
            photo,
            playerProgress,
            totalKm,
            status,
          ),
          child: Column(
            mainAxisSize:
            MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 25,
                backgroundImage: photo != null
                    ? NetworkImage(photo)
                    : const AssetImage(
                    'assets/icon/logo_principal.png')
                as ImageProvider,
              ),
              const SizedBox(height: 4),
              Text(name.split(' ').first,
                  style: const TextStyle(
                      fontSize: 11)),
            ],
          ),
        );
      },
    );
  }

  void _showPlayerProgress(
      BuildContext context,
      String name,
      String? photoUrl,
      double currentKm,
      double totalKm,
      String status,
      ) {
    final percent =
    (currentKm / totalKm).clamp(0.0, 1.0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius:
        BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              bottom: MediaQuery.of(context)
                  .viewInsets
                  .bottom +
                  20,
              top: 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize:
                MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 35,
                    backgroundImage: photoUrl != null
                        ? NetworkImage(photoUrl)
                        : const AssetImage(
                        'assets/icon/logo_principal.png')
                    as ImageProvider,
                  ),
                  const SizedBox(height: 12),
                  Text(name,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight:
                          FontWeight.bold)),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: percent,
                    backgroundColor:
                    Colors.grey[300],
                    color: status ==
                        'completed'
                        ? Colors.green
                        : status ==
                        'cancelled'
                        ? Colors.red
                        : Colors.orange,
                    minHeight: 10,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${currentKm.toStringAsFixed(2)} km / ${totalKm.toStringAsFixed(2)} km',
                    style: const TextStyle(
                        fontWeight:
                        FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    status == 'completed'
                        ? '✅ Desafio concluído!'
                        : status ==
                        'cancelled'
                        ? '❌ Desafio cancelado'
                        : '🏃 Em andamento...',
                    style: TextStyle(
                      color: status ==
                          'completed'
                          ? Colors.green
                          : status ==
                          'cancelled'
                          ? Colors.red
                          : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showRanking(
      BuildContext context,
      Map<String, dynamic> progress,
      double totalKm,
      ) {
    final ranking = progress.entries.toList()
      ..sort((a, b) =>
          (b.value['distance'] ?? 0).compareTo(a.value['distance'] ?? 0));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius:
        BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: MediaQuery.of(context)
                  .viewInsets
                  .bottom +
                  20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize:
                MainAxisSize.min,
                children: [
                  const Text(
                    '🏆 Ranking do Desafio',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight:
                      FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (ranking.isEmpty)
                    const Text(
                        'Nenhum progresso registrado ainda 😅')
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics:
                      const NeverScrollableScrollPhysics(),
                      itemCount: ranking.length,
                      itemBuilder:
                          (context, index) {
                        final uid =
                            ranking[index].key;
                        final dist =
                        (ranking[index].value['distance'] ??
                            0.0)
                            .toDouble();
                        final status =
                            ranking[index].value['status'] ??
                                'in_progress';
                        final medal = index == 0
                            ? '🥇'
                            : index == 1
                            ? '🥈'
                            : index == 2
                            ? '🥉'
                            : '🏃';
                        final percent =
                        (dist / totalKm)
                            .clamp(0.0, 1.0);

                        return FutureBuilder<
                            DocumentSnapshot>(
                          future: FirebaseFirestore
                              .instance
                              .collection('users')
                              .doc(uid)
                              .get(),
                          builder:
                              (context, snapshot) {
                            final user = snapshot
                                .data
                                ?.data()
                            as Map<String,
                                dynamic>?;
                            final name =
                                user?['displayName'] ??
                                    'Jogador';
                            final photo =
                            user?['photoURL'];

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage:
                                photo != null
                                    ? NetworkImage(
                                    photo)
                                    : const AssetImage(
                                    'assets/icon/logo_principal.png')
                                as ImageProvider,
                              ),
                              title: Text(
                                '$medal $name',
                                style: const TextStyle(
                                    fontWeight:
                                    FontWeight
                                        .bold),
                              ),
                              subtitle:
                              LinearProgressIndicator(
                                value: percent,
                                backgroundColor:
                                Colors.grey[300],
                                color: status ==
                                    'completed'
                                    ? Colors
                                    .green
                                    : Colors
                                    .orange,
                                minHeight: 6,
                              ),
                              trailing: Text(
                                '${dist.toStringAsFixed(2)} km',
                                style: const TextStyle(
                                    fontWeight:
                                    FontWeight
                                        .w600,
                                    color: Colors
                                        .black87),
                              ),
                            );
                          },
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
