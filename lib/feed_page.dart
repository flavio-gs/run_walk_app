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
import 'package:run_walk_app/create_story_page.dart';
import 'package:run_walk_app/story_view_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'package:run_walk_app/theme/season_theme_scope.dart';

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

  String _selectedTypeFilter = 'all';

  static const Map<String, String> _typeLabels = {
    'all': 'Todos',
    'post': 'Posts',
    'achievement': 'Conquistas',
    'challenge': 'Desafios',
    'territory': 'Batalhas',
    'promocional': 'Promoções',
  };


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
    final s = SeasonThemeScope.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: s.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: s.mutedForeground.withOpacity(0.24),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Text(
                'Crie algo incrível!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: s.foreground,
                ),
              ),
              const SizedBox(height: 16),
              _buildCreateOption(
                context: context,
                icon: Icons.add_a_photo_rounded,
                color: s.primary,
                title: 'Adicionar ao Story',
                subtitle: 'Poste uma foto, vídeo ou enquete rápida',
                onTap: () {
                  Navigator.pop(context);
                  _showStoryOptions();
                },
              ),
              const SizedBox(height: 8),
              _buildCreateOption(
                context: context,
                icon: Icons.edit,
                color: s.primary,
                title: 'Faça uma Publicação',
                subtitle: 'Compartilhe sua corrida, foto ou reflexão do dia',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CreatePostPage()),
                  );
                },
              ),
              const SizedBox(height: 8),
              _buildCreateOption(
                context: context,
                icon: Icons.flag_rounded,
                color: s.primary,
                title: 'Criar Desafio',
                subtitle: 'Convide a galera e veja quem aguenta 😈',
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CreateChallengePage()),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openTypeFilterSheet() {
    final s = SeasonThemeScope.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: s.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: s.mutedForeground.withOpacity(0.24),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Text(
                  'Filtrar feed',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: s.foreground,
                  ),
                ),
                const SizedBox(height: 10),
                ..._typeLabels.entries.map((e) {
                  final isSelected = _selectedTypeFilter == e.key;
                  return ListTile(
                    leading: Icon(
                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                      color: isSelected ? s.primary : s.mutedForeground,
                    ),
                    title: Text(
                      e.value,
                      style: TextStyle(
                        color: s.foreground,
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                      ),
                    ),
                    onTap: () {
                      setState(() => _selectedTypeFilter = e.key);
                      Navigator.pop(context);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }


  Widget _buildCreateOption({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final s = SeasonThemeScope.of(context);

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: color.withOpacity(0.15),
        child: Icon(icon, color: color, size: 26),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 16,
          color: s.foreground,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 13,
          color: s.mutedForeground.withOpacity(0.85),
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
    );
  }

  Widget _buildFeedToggleButton(String label, String mode) {
    final s = SeasonThemeScope.of(context);

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
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? s.primary : s.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? s.primary.withOpacity(0.9) : s.border,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 14,
              offset: const Offset(0, 6),
              color: Colors.black.withOpacity(isSelected ? 0.35 : 0.25),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : s.foreground,
            fontWeight: FontWeight.w800,
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
          whereNotIn: excluded.length > 10 ? excluded.take(10).toList() : excluded,
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
    final user = FirebaseAuth.instance.currentUser!;
    final userId = user.uid;

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
        'displayName': user.displayName ?? 'Usuário',
        'photoURL': user.photoURL ?? '',
        'userId': userId,
      });

      if (userId != authorId) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(authorId)
            .collection('notifications')
            .add({
          'type': 'like',
          'senderName': user.displayName ?? 'Alguém',
          'senderId': userId,
          'senderPhotoUrl': user.photoURL,
          'message':
          '${user.displayName ?? 'Alguém'} curtiu sua publicação.',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      }
    } else {
      await reactionRef.set({
        'type': 'like',
        'timestamp': FieldValue.serverTimestamp(),
        'displayName': user.displayName ?? 'Usuário',
        'photoURL': user.photoURL ?? '',
        'userId': userId,
      }, SetOptions(merge: true));
    }

    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final s = SeasonThemeScope.of(context);

    return Scaffold(
      backgroundColor: s.background,
      appBar: AppBar(
        backgroundColor: s.background,
        elevation: 0,
        title: Text(
          'RunFeed',
          style: TextStyle(
            color: s.foreground,
            fontWeight: FontWeight.w800,
            fontSize: 22,
            letterSpacing: 0.2,
          ),
        ),
        iconTheme: IconThemeData(color: s.primary),
        actions: [
          IconButton(
            icon: Icon(Icons.search_rounded, color: s.foreground.withOpacity(0.7)),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SearchUsersPage()),
            ).then((_) => _setupFeedStream()),
          ),
          IconButton(
            icon: Icon(Icons.add_box_outlined, color: s.foreground.withOpacity(0.7)),
            onPressed: () => _showCreateOptions(context),
          ),
          StreamBuilder<int>(
            stream: _unreadNotificationsCountStream,
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;

              return Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.favorite_border, color: s.foreground.withOpacity(0.7)),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const NotificationsPage()),
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
                          color: s.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: s.background, width: 1.6),
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
          ? Center(child: CircularProgressIndicator(color: s.primary))
          : _buildFeedBody(),
    );
  }

  Widget _buildFeedBody() {
    final s = SeasonThemeScope.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildFeedToggleButton('Seguindo', 'following'),
                    const SizedBox(width: 12),
                    _buildFeedToggleButton('Global', 'global'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _openTypeFilterSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: s.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: s.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.filter_alt_rounded, color: s.foreground.withOpacity(0.8), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _typeLabels[_selectedTypeFilter] ?? 'Todos',
                        style: TextStyle(
                          color: s.foreground,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        Divider(height: 1, color: s.border.withOpacity(0.8)),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _postsStream,
            builder: (context, snapshot) {
              if (_isLoading) {
                return Center(child: CircularProgressIndicator(color: s.primary));
              }

              final posts = snapshot.hasData ? snapshot.data!.docs : [];

              // ✅ aplica filtro por tipo (no client)
              final filteredPosts = posts.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final type = (data['type'] ?? 'post').toString();
                if (_selectedTypeFilter == 'all') return true;
                return type == _selectedTypeFilter;
              }).toList();

              final int itemCount = filteredPosts.isEmpty ? 2 : filteredPosts.length + 1;

              return ListView.builder(
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  if (index == 0) return _buildStoriesBar();

                  if (filteredPosts.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 100),
                      child: _emptyFeedMessage(),
                    );
                  }

                  return _buildPostItem(filteredPosts[index - 1]);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ITEM DO FEED
  Widget _buildPostItem(DocumentSnapshot post) {
    final data = post.data() as Map<String, dynamic>;

    final postId = post.id;
    final postTime = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

    final type = (data['type'] ?? 'post').toString();
    final authorId = (data['authorId'] ?? '').toString();

    // ✅ TERRITORY BATTLE (VS)
    if (type == 'territory' && (data['loserId'] != null || data['previousOwner'] != null)) {
      return TerritoryBattlePostCard(
        postId: postId,
        data: data,
        postTime: postTime,
        onComment: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CommentsPage(postId: postId, postAuthorId: authorId),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(authorId).snapshots(),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        final authorName = userData?['displayName'] ?? data['authorName'] ?? 'Usuário';
        final photoUrl = userData?['photoURL'];

        if (type == 'challenge') {
          return ChallengePostCard(
            postId: postId,
            data: data,
            currentUserId: _currentUserId,
          );
        }

        if (type == 'achievement') {
          return _AchievementPostCard(data: data);
        }

        if (type == 'promocional') {
          return PromoPostCard(
            postId: postId,
            data: data,
            postTime: postTime,
            authorId: authorId,
            onComment: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CommentsPage(postId: postId, postAuthorId: authorId),
              ),
            ),
          );
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

        final resolvedUrl = resolvedType == 'video' ? (mediaUrl ?? videoUrl) : (mediaUrl ?? imageUrl);

        // 🏃‍♂️ resumo da corrida (opcional)
        final hasRun = data['hasRun'] == true;
        final runSummaryRaw = data['runSummary'] as Map<String, dynamic>?;

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
          caption: (data['text'] ?? data['title'] ?? '').toString(),

          // corrida
          hasRun: hasRun,
          distanceKm: distanceKm,
          durationSec: durationSec,
          pace: pace,

          // localização
          hasLocation: hasLocation,
          locLat: locLat,
          locLng: locLng,

          onLikeTap: (myReaction) => _toggleLike(postId, authorId, myReaction),
          onComment: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CommentsPage(postId: postId, postAuthorId: authorId),
            ),
          ),
        );
      },
    );
  }

  // ====================================
  // STORIES SECTION
  // ====================================

  Widget _buildStoriesBar() {
    final s = SeasonThemeScope.of(context);
    final twentyFourHoursAgo = DateTime.now().subtract(const Duration(hours: 24));

    return Container(
      height: 115,
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: s.background,
        border: Border(bottom: BorderSide(color: s.border.withOpacity(0.4), width: 0.5)),
      ),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('stories')
            .where('timestamp', isGreaterThan: Timestamp.fromDate(twentyFourHoursAgo))
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          final Map<String, List<DocumentSnapshot>> storiesByAuthor = {};
          if (snapshot.hasData) {
            for (var doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final authorId = data['authorId'] as String? ?? '';
              if (authorId.isNotEmpty) {
                storiesByAuthor.putIfAbsent(authorId, () => <DocumentSnapshot>[]).add(doc);
              }
            }
          }

          storiesByAuthor.remove(_currentUserId);

          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: storiesByAuthor.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildMyStoryItem();
              }
              final authorId = storiesByAuthor.keys.elementAt(index - 1);
              final authorStories = storiesByAuthor[authorId]!;
              return _buildOtherStoryItem(authorId, authorStories);
            },
          );
        },
      ),
    );
  }

  Widget _buildMyStoryItem() {
    final user = FirebaseAuth.instance.currentUser;
    final s = SeasonThemeScope.of(context);
    final twentyFourHoursAgo = DateTime.now().subtract(const Duration(hours: 24));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('stories')
          .where('authorId', isEqualTo: _currentUserId)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(twentyFourHoursAgo))
          .snapshots(),
      builder: (context, snapshot) {
        final hasStories = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
        final stories = snapshot.hasData ? snapshot.data!.docs : <DocumentSnapshot>[];

        return GestureDetector(
          onTap: () {
            if (hasStories) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => StoryViewPage(authorId: _currentUserId, stories: stories),
                ),
              );
            } else {
              _showStoryOptions();
            }
          },
          onLongPress: _showStoryOptions,
          child: Container(
            margin: const EdgeInsets.only(right: 12),
            width: 72,
            child: Column(
              children: [
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: hasStories ? s.primary : s.border,
                          width: hasStories ? 2 : 1,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: s.card,
                        backgroundImage: (user?.photoURL != null && user!.photoURL!.isNotEmpty)
                            ? NetworkImage(user.photoURL!)
                            : const AssetImage('assets/icon/logo_principal.png') as ImageProvider,
                      ),
                    ),
                    if (!hasStories)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: s.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: s.background, width: 2),
                          ),
                          padding: const EdgeInsets.all(2),
                          child: const Icon(Icons.add, size: 16, color: Colors.black),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Seu story',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: s.foreground.withOpacity(0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOtherStoryItem(String authorId, List<DocumentSnapshot> stories) {
    final s = SeasonThemeScope.of(context);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(authorId).snapshots(),
      builder: (context, userSnap) {
        final userData = userSnap.data?.data() as Map<String, dynamic>?;
        final name = userData?['displayName'] ?? 'Usuário';
        final photoUrl = userData?['photoURL'];

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => StoryViewPage(authorId: authorId, stories: stories),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(right: 12),
            width: 72,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [s.primary, Colors.orange, Colors.purpleAccent],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: s.background,
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: s.card,
                      backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                          ? NetworkImage(photoUrl)
                          : const AssetImage('assets/icon/logo_principal.png') as ImageProvider,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  name.split(' ').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: s.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showStoryOptions() {
    final s = SeasonThemeScope.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: s.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: s.mutedForeground.withOpacity(0.24),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Text(
                  'Adicionar ao Story',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: s.foreground),
                ),
                const SizedBox(height: 25),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStoryOption(
                      icon: Icons.camera_alt_rounded,
                      label: 'Câmera',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const CreateStoryPage(type: 'image')),
                        );
                      },
                    ),
                    _buildStoryOption(
                      icon: Icons.poll_rounded,
                      label: 'Enquete',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const CreateStoryPage(type: 'poll')),
                        );
                      },
                    ),
                    _buildStoryOption(
                      icon: Icons.videocam_rounded,
                      label: 'Vídeo',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const CreateStoryPage(type: 'video')),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStoryOption({required IconData icon, required String label, required VoidCallback onTap}) {
    final s = SeasonThemeScope.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: s.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: s.primary, size: 32),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: s.foreground,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyFeedMessage() {
    final s = SeasonThemeScope.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, size: 60, color: s.mutedForeground.withOpacity(0.75)),
            const SizedBox(height: 14),
            Text(
              'Nenhuma publicação encontrada',
              style: TextStyle(color: s.primary, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CreatePostPage()),
              ),
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text('Fazer uma publicação'),
              style: ElevatedButton.styleFrom(
                backgroundColor: s.primary,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementPostCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AchievementPostCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final s = SeasonThemeScope.of(context);

    final icon = (data['icon'] ?? '🏆').toString();
    final title = (data['title'] ?? 'Conquista Desconhecida').toString();
    final userName = (data['authorName'] ?? 'Jogador').toString();
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

    final muted = s.mutedForeground;
    final border = s.border;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      decoration: BoxDecoration(
        color: s.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 8),
            color: Colors.black.withOpacity(0.28),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            Positioned(
              left: -40,
              top: -60,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s.primary.withOpacity(0.10),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: s.primary.withOpacity(0.9), width: 1.3),
                    ),
                    child: CircleAvatar(
                      radius: 26,
                      backgroundColor: s.foreground.withOpacity(0.06),
                      child: Text(icon, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$userName conquistou',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: muted,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            color: s.foreground,
                            fontWeight: FontWeight.w900,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.schedule_rounded, size: 14, color: muted),
                            const SizedBox(width: 6),
                            Text(
                              timeago.format(timestamp, locale: 'pt_BR'),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: s.primary.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: s.primary.withOpacity(0.45)),
                              ),
                              child: Text(
                                'CONQUISTA',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: s.primary,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.7,
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
    final s = SeasonThemeScope.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: s.mutedForeground, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 13,
            color: s.foreground,
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

class _AnimatedPostCardState extends State<_AnimatedPostCard> with TickerProviderStateMixin {
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
    final oldIsVideo = oldWidget.mediaType == 'video' && oldWidget.mediaUrl != null;
    final newIsVideo = widget.mediaType == 'video' && widget.mediaUrl != null;

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
    final s = SeasonThemeScope.of(context);

    final hasRunData = widget.hasRun &&
        widget.distanceKm != null &&
        widget.durationSec != null &&
        widget.pace != null;

    final hasLocData = widget.hasLocation && widget.locLat != null && widget.locLng != null;

    if (!hasRunData && !hasLocData) return const SizedBox.shrink();

    final muted = s.mutedForeground;
    final border = s.border;

    Widget metric(String label, String value) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: s.foreground)),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: s.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: s.primary.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: s.primary.withOpacity(0.35)),
              ),
              child: Icon(Icons.directions_run, color: s.primary, size: 24),
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
                        metric('Distância', '${widget.distanceKm!.toStringAsFixed(2)} km'),
                        metric('Tempo', _formatDuration(widget.durationSec!)),
                        metric('Pace', '${widget.pace!.toStringAsFixed(2)} min/km'),
                      ],
                    ),
                  if (hasRunData && hasLocData) const SizedBox(height: 6),
                  if (hasLocData)
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 16, color: s.primary.withOpacity(0.9)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Perto de (${widget.locLat!.toStringAsFixed(4)}, ${widget.locLng!.toStringAsFixed(4)})',
                            style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w600),
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
    final user = FirebaseAuth.instance.currentUser!;
    final userId = user.uid;

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
        'displayName': user.displayName,
        'photoURL': user.photoURL,
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
    final s = SeasonThemeScope.of(context);

    if (_videoController == null) {
      return Container(
        height: 260,
        color: s.card,
        child: Center(
          child: Icon(Icons.videocam_off, size: 40, color: s.mutedForeground),
        ),
      );
    }

    if (!_isVideoInitialized) {
      return Container(
        height: 260,
        color: s.card,
        child: Center(
          child: CircularProgressIndicator(color: s.primary),
        ),
      );
    }

    final aspect = _videoController!.value.aspectRatio == 0 ? 16 / 9 : _videoController!.value.aspectRatio;

    return AspectRatio(
      aspectRatio: aspect,
      child: VideoPlayer(_videoController!),
    );
  }

  void _showPostOptions(BuildContext context) async {
    final s = SeasonThemeScope.of(context);

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
      backgroundColor: s.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final ss = SeasonThemeScope.of(context);

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 16),
                decoration: BoxDecoration(
                  color: ss.mutedForeground.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              if (isOwner) ...[
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.blueAccent),
                  title: Text('Editar publicação', style: TextStyle(color: ss.foreground)),
                  onTap: () {
                    Navigator.pop(context);
                    _openEditPostModal(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.redAccent),
                  title: Text('Excluir publicação', style: TextStyle(color: ss.foreground)),
                  onTap: () async {
                    Navigator.pop(context);
                    await _confirmDeletePost(context);
                  },
                ),
              ] else if (!isFollowing) ...[
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_rounded, color: Colors.green),
                  title: Text('Seguir jogador', style: TextStyle(color: ss.foreground)),
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

                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✅ Agora você está seguindo este jogador!')),
                    );
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.person_remove_alt_1, color: Colors.orange),
                  title: Text('Deixar de seguir jogador', style: TextStyle(color: ss.foreground)),
                  onTap: () async {
                    Navigator.pop(context);
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(currentUserId)
                        .collection('following')
                        .doc(widget.authorId)
                        .delete();

                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('👋 Você deixou de seguir este jogador.')),
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
    final s = SeasonThemeScope.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: s.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Excluir publicação', style: TextStyle(color: s.foreground)),
        content: Text(
          'Tem certeza que deseja excluir esta publicação?\nEssa ação não pode ser desfeita.',
          style: TextStyle(fontSize: 15, color: s.mutedForeground),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: TextStyle(color: s.mutedForeground)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance.collection('posts').doc(widget.postId).delete();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('🗑️ Publicação excluída com sucesso!')),
              );
            },
            icon: const Icon(Icons.delete, color: Colors.white),
            label: const Text('Excluir'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
          ),
        ],
      ),
    );
  }

  void _openEditPostModal(BuildContext context) {
    final s = SeasonThemeScope.of(context);

    final TextEditingController captionController =
    TextEditingController(text: widget.caption ?? '');
    String? updatedImageUrl = widget.imageUrl;
    bool isUpdating = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: s.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        final ss = SeasonThemeScope.of(context);

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
                    Text(
                      '✏️ Editar Publicação',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: ss.foreground,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: captionController,
                      maxLines: null,
                      style: TextStyle(color: ss.foreground),
                      decoration: InputDecoration(
                        hintText: 'Escreva algo...',
                        hintStyle: TextStyle(color: ss.mutedForeground),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: ss.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: ss.primary.withOpacity(0.9)),
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
                            const SnackBar(content: Text('✅ Publicação atualizada com sucesso!')),
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
                          : const Icon(Icons.check_circle_outline, color: Colors.white),
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
    final s = SeasonThemeScope.of(context);

    final CollectionReference<Map<String, dynamic>> reactionsCol =
    FirebaseFirestore.instance
        .collection('posts')
        .doc(widget.postId)
        .collection('reactions');

    final String? uid = FirebaseAuth.instance.currentUser?.uid;

    final Stream<DocumentSnapshot<Map<String, dynamic>>> myDoc =
    (uid != null)
        ? reactionsCol.doc(uid).snapshots()
        : Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();


    final DocumentReference<Map<String, dynamic>> myRef =
    reactionsCol.doc(FirebaseAuth.instance.currentUser!.uid);

    final Stream<QuerySnapshot<Map<String, dynamic>>> allDocs =
    reactionsCol.snapshots();


    final hasImage = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;
    final isVideo = widget.mediaType == 'video' && widget.mediaUrl != null;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (showOverlay) {
          setState(() => showOverlay = false);
          _overlayController.reverse();
        }
      },
      child: Container(
        color: s.background,
        margin: const EdgeInsets.only(bottom: 10),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: s.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: s.border),
            boxShadow: [
              BoxShadow(
                blurRadius: 18,
                offset: const Offset(0, 8),
                color: Colors.black.withOpacity(0.35),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
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
                              builder: (_) => ProfilePage(userId: widget.authorId),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: s.primary.withOpacity(0.9), width: 1.3),
                          ),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: s.foreground.withOpacity(0.06),
                            backgroundImage: (widget.photoUrl != null && widget.photoUrl!.isNotEmpty)
                                ? NetworkImage(widget.photoUrl!)
                                : const AssetImage('assets/icon/logo_principal.png') as ImageProvider,
                          ),
                        ),
                      ),
                      title: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfilePage(userId: widget.authorId),
                            ),
                          );
                        },
                        child: Text(
                          widget.authorName,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: s.foreground,
                          ),
                        ),
                      ),
                      subtitle: Text(
                        timeago.format(widget.postTime, locale: 'pt_BR'),
                        style: TextStyle(color: s.mutedForeground, fontSize: 12),
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.more_vert, color: s.mutedForeground),
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
                          (mySnap.data?.data() as Map<String, dynamic>?)?['type'] as String?;

                          return GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () {
                              if (isVideo && _videoController != null && _isVideoInitialized) {
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
                                        Shadow(color: Colors.black54, blurRadius: 12),
                                      ],
                                    ),
                                  ),
                                if (isVideo && _videoController != null && _isVideoInitialized)
                                  Positioned(
                                    bottom: 12,
                                    right: 12,
                                    child: CircleAvatar(
                                      radius: 20,
                                      backgroundColor: Colors.black54,
                                      child: Icon(
                                        _videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
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
                              (mySnap.data?.data() as Map<String, dynamic>?)?['type'] as String?;

                              final isActive = myType != null;
                              final text = _label[myType ?? 'like'] ?? 'Curtir';

                              final color = myType == 'love'
                                  ? Colors.redAccent
                                  : (isActive ? s.primary : s.foreground.withOpacity(0.7));

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
                                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isActive ? color.withOpacity(0.12) : Colors.transparent,
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
                                            fontWeight: FontWeight.w800,
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
                                      Icon(Icons.chat_bubble_outline, color: s.foreground.withOpacity(0.7)),
                                      const SizedBox(width: 6),
                                      Text(
                                        count.toString(),
                                        style: TextStyle(
                                          color: s.foreground.withOpacity(0.7),
                                          fontWeight: FontWeight.w800,
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
                            icon: Icon(Icons.share_outlined, color: s.foreground.withOpacity(0.7)),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ),

                    // Contador de reações por tipo + total
                    StreamBuilder<QuerySnapshot>(
                      stream: allDocs,
                      builder: (context, snap) {
                        if (!snap.hasData) return const SizedBox(height: 8);

                        final counts = <String, int>{
                          'love': 0,
                          'haha': 0,
                          'strong': 0,
                          'like': 0,
                        };

                        for (final d in snap.data!.docs) {
                          final type = (d.data() as Map<String, dynamic>)['type'];
                          if (counts.containsKey(type)) counts[type] = counts[type]! + 1;
                        }

                        final total = counts.values.fold<int>(0, (a, b) => a + b);
                        final nonZero = counts.entries.where((e) => e.value > 0).toList()
                          ..sort((a, b) => b.value.compareTo(a.value));

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: total == 0
                              ? const SizedBox.shrink()
                              : Row(
                            children: [
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
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: s.foreground,
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
                                style: TextStyle(
                                  color: s.mutedForeground,
                                  fontWeight: FontWeight.w700,
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(color: s.foreground),
                            children: [
                              TextSpan(
                                text: '${widget.authorName} ',
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                              TextSpan(
                                text: widget.caption!,
                                style: TextStyle(
                                  color: s.foreground.withOpacity(0.75),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
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
                    bottom: 330,
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
    final s = SeasonThemeScope.of(context);

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: s.card,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
          border: Border.all(color: s.border),
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

class _ReactionBubbleState extends State<_ReactionBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );
  late final Animation<double> _scale = Tween<double>(begin: 1.0, end: 1.2).animate(_c);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = SeasonThemeScope.of(context);

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
                  backgroundColor: s.background,
                  radius: 22,
                  child: Text(widget.emoji, style: const TextStyle(fontSize: 22)),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.label,
                style: TextStyle(fontSize: 11, color: s.mutedForeground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ====================================
// ChallengePostCard (desafios) — corrigido/otimizado
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
  State<ChallengePostCard> createState() => _ChallengePostCardState();
}

class _ChallengePostCardState extends State<ChallengePostCard> {
  bool _loading = false;
  Map<String, dynamic>? _authorData;

  // ✅ cache simples pra não ficar dando get() repetido
  static final Map<String, Map<String, dynamic>?> _userCache = {};

  @override
  void initState() {
    super.initState();
    _loadAuthorData();
  }

  Future<Map<String, dynamic>?> _fetchUser(String uid) async {
    if (_userCache.containsKey(uid)) return _userCache[uid];

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      _userCache[uid] = data;
      return data;
    } catch (_) {
      _userCache[uid] = null;
      return null;
    }
  }

  Future<void> _loadAuthorData() async {
    final authorId = (widget.data['authorId'] ?? '').toString();
    if (authorId.isEmpty) return;

    final data = await _fetchUser(authorId);
    if (!mounted) return;
    setState(() => _authorData = data);
  }

  Future<void> _acceptChallenge() async {
    if (_loading) return;

    setState(() => _loading = true);
    final ref = FirebaseFirestore.instance.collection('posts').doc(widget.postId);

    try {
      await ref.update({
        'participants': FieldValue.arrayUnion([widget.currentUserId]),
        'progress.${widget.currentUserId}': {
          'distance': 0.0,
          'status': 'in_progress',
        },
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🔥 Você entrou no desafio! Boa sorte!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao entrar no desafio: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmCancelChallenge() async {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedValue = Curves.easeOutBack.transform(animation.value) - 1.0;

        return Transform.translate(
          offset: Offset(curvedValue * 20, 0),
          child: Opacity(
            opacity: animation.value,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                  SizedBox(width: 8),
                  Text('Tem certeza?', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: const Text(
                'Se você desistir agora, seu nome vai brilhar no mural dos desistentes 😏\n\n'
                    'Pense bem... os outros jogadores vão ver 👀',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.4),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.sports_motorsports_rounded, color: Colors.green),
                  label: const Text('Continuar no desafio', style: TextStyle(color: Colors.green)),
                  onPressed: () => Navigator.pop(context),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.exit_to_app_rounded, color: Colors.white),
                  label: const Text('Desistir'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    if (_loading) return;

    setState(() => _loading = true);
    final ref = FirebaseFirestore.instance.collection('posts').doc(widget.postId);

    try {
      await ref.update({
        'participants': FieldValue.arrayRemove([widget.currentUserId]),
        'quitters': FieldValue.arrayUnion([widget.currentUserId]),
        'progress.${widget.currentUserId}.status': 'cancelled',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Você cancelou sua inscrição neste desafio.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao cancelar desafio: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime _safePostTime(Map<String, dynamic> d) {
    final t = d['timestamp'];
    if (t is Timestamp) return t.toDate();
    if (t is DateTime) return t;
    return DateTime.now();
  }

  DateTime? _safeDeadline(Map<String, dynamic> d) {
    final dl = d['deadline'];
    if (dl is Timestamp) return dl.toDate();
    if (dl is DateTime) return dl;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final d = widget.data;

    final participants = List<String>.from((d['participants'] ?? const []) as List);
    final quitters = List<String>.from((d['quitters'] ?? const []) as List);
    final progress = Map<String, dynamic>.from((d['progress'] ?? const {}) as Map);

    final joined = participants.contains(widget.currentUserId);
    final totalKm = (d['distance'] is num) ? (d['distance'] as num).toDouble() : 0.0;

    final authorName =
    (_authorData?['displayName'] ?? d['authorName'] ?? 'Jogador').toString();
    final authorPhoto = (_authorData?['photoURL'] ?? '').toString();

    final postTime = _safePostTime(d);
    final deadline = _safeDeadline(d);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header autor
            Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfilePage(userId: (d['authorId'] ?? '').toString()),
                    ),
                  ),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundImage: authorPhoto.trim().isNotEmpty
                        ? NetworkImage(authorPhoto)
                        : const AssetImage('assets/icon/logo_principal.png') as ImageProvider,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfilePage(userId: (d['authorId'] ?? '').toString()),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Criado por $authorName',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          timeago.format(postTime, locale: 'pt_BR'),
                          style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.6)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const Divider(height: 24, thickness: 1),

            Text(
              '🏁 ${(d['title'] ?? 'Desafio de Corrida').toString()}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Distância: ${totalKm.toStringAsFixed(2)} km',
              style: TextStyle(color: cs.onSurface.withOpacity(0.9)),
            ),
            if (deadline != null)
              Text(
                'Prazo: ${deadline.day}/${deadline.month}/${deadline.year}',
                style: TextStyle(color: cs.onSurface.withOpacity(0.6)),
              ),
            const SizedBox(height: 16),

            // CTA
            if (joined)
              ElevatedButton.icon(
                onPressed: _loading ? null : _confirmCancelChallenge,
                icon: const Icon(Icons.cancel, color: Colors.white),
                label: _loading
                    ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
                    : const Text('Cancelar inscrição'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  minimumSize: const Size(double.infinity, 45),
                ),
              )
            else if (quitters.contains(widget.currentUserId))
              ElevatedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.block),
                label: const Text('Você desistiu deste desafio 😬'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                  minimumSize: const Size(double.infinity, 45),
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: _loading ? null : _acceptChallenge,
                icon: const Icon(Icons.flag),
                label: _loading
                    ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
                    : const Text('Aceito o Desafio'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  minimumSize: const Size(double.infinity, 45),
                ),
              ),

            const SizedBox(height: 20),

            const Text('Jogadores inscritos:', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (participants.isEmpty)
              const Text('Ainda ninguém se inscreveu 😅')
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: participants.map((uid) {
                  return _buildPlayerAvatar(uid, progress, totalKm);
                }).toList(),
              ),

            const SizedBox(height: 16),

            if (quitters.isNotEmpty) ...[
              const Divider(),
              const SizedBox(height: 6),
              const Text(
                'Jogadores desistentes:',
                style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: quitters.map((uid) => _buildQuitterAvatar(uid)).toList(),
              ),
            ],

            const SizedBox(height: 20),

            if (participants.isNotEmpty)
              Center(
                child: OutlinedButton.icon(
                  onPressed: () => _showRanking(context, progress, totalKm),
                  icon: const Icon(Icons.bar_chart_rounded, color: Colors.blueAccent),
                  label: const Text(
                    "Ver Ranking",
                    style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.blueAccent),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuitterAvatar(String uid) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchUser(uid),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final name = (user?['displayName'] ?? 'Jogador').toString();
        final photo = (user?['photoURL'] ?? '').toString();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundImage: photo.trim().isNotEmpty
                  ? NetworkImage(photo)
                  : const AssetImage('assets/icon/logo_principal.png') as ImageProvider,
              backgroundColor: Colors.red.shade100,
            ),
            const SizedBox(height: 4),
            Text(
              name.split(' ').first,
              style: const TextStyle(fontSize: 11, color: Colors.redAccent),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlayerAvatar(String uid, Map<String, dynamic> progress, double totalKm) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchUser(uid),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final name = (user?['displayName'] ?? 'Jogador').toString();
        final photo = (user?['photoURL'] ?? '').toString();

        final p = (progress[uid] is Map) ? Map<String, dynamic>.from(progress[uid] as Map) : const {};
        final playerProgress = (p['distance'] is num) ? (p['distance'] as num).toDouble() : 0.0;
        final status = (p['status'] ?? 'in_progress').toString();

        return GestureDetector(
          onTap: () => _showPlayerProgress(
            context,
            name,
            photo.trim().isEmpty ? null : photo,
            playerProgress,
            totalKm,
            status,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 25,
                backgroundImage: photo.trim().isNotEmpty
                    ? NetworkImage(photo)
                    : const AssetImage('assets/icon/logo_principal.png') as ImageProvider,
              ),
              const SizedBox(height: 4),
              Text(name.split(' ').first, style: const TextStyle(fontSize: 11)),
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
    final safeTotal = totalKm <= 0 ? 1.0 : totalKm;
    final percent = (currentKm / safeTotal).clamp(0.0, 1.0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        final cs = Theme.of(context).colorScheme;

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 35,
                    backgroundImage: photoUrl != null
                        ? NetworkImage(photoUrl)
                        : const AssetImage('assets/icon/logo_principal.png') as ImageProvider,
                  ),
                  const SizedBox(height: 12),
                  Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: percent,
                    backgroundColor: Colors.grey[300],
                    color: status == 'completed'
                        ? Colors.green
                        : status == 'cancelled'
                        ? Colors.red
                        : Colors.orange,
                    minHeight: 10,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${currentKm.toStringAsFixed(2)} km / ${totalKm.toStringAsFixed(2)} km',
                    style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    status == 'completed'
                        ? '✅ Desafio concluído!'
                        : status == 'cancelled'
                        ? '❌ Desafio cancelado'
                        : '🏃 Em andamento...',
                    style: TextStyle(
                      color: status == 'completed'
                          ? Colors.green
                          : status == 'cancelled'
                          ? Colors.red
                          : Colors.orange,
                      fontWeight: FontWeight.w700,
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
    final entries = progress.entries
        .where((e) => e.value is Map)
        .map((e) => MapEntry(e.key, Map<String, dynamic>.from(e.value as Map)))
        .toList();

    entries.sort((a, b) {
      final da = (a.value['distance'] is num) ? (a.value['distance'] as num).toDouble() : 0.0;
      final db = (b.value['distance'] is num) ? (b.value['distance'] as num).toDouble() : 0.0;
      return db.compareTo(da);
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        final cs = Theme.of(context).colorScheme;

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '🏆 Ranking do Desafio',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (entries.isEmpty)
                    const Text('Nenhum progresso registrado ainda 😅')
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final uid = entries[index].key;
                        final dist =
                        (entries[index].value['distance'] is num) ? (entries[index].value['distance'] as num).toDouble() : 0.0;
                        final status = (entries[index].value['status'] ?? 'in_progress').toString();

                        final medal = index == 0
                            ? '🥇'
                            : index == 1
                            ? '🥈'
                            : index == 2
                            ? '🥉'
                            : '🏃';

                        final safeTotal = totalKm <= 0 ? 1.0 : totalKm;
                        final percent = (dist / safeTotal).clamp(0.0, 1.0);

                        return FutureBuilder<Map<String, dynamic>?>(
                          future: _fetchUser(uid),
                          builder: (context, snapshot) {
                            final user = snapshot.data;
                            final name = (user?['displayName'] ?? 'Jogador').toString();
                            final photo = (user?['photoURL'] ?? '').toString();

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundImage: photo.trim().isNotEmpty
                                    ? NetworkImage(photo)
                                    : const AssetImage('assets/icon/logo_principal.png') as ImageProvider,
                              ),
                              title: Text(
                                '$medal $name',
                                style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface),
                              ),
                              subtitle: LinearProgressIndicator(
                                value: percent,
                                backgroundColor: Colors.grey[300],
                                color: status == 'completed' ? Colors.green : Colors.orange,
                                minHeight: 6,
                              ),
                              trailing: Text(
                                '${dist.toStringAsFixed(2)} km',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface.withOpacity(0.9),
                                ),
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

// ====================================
// TerritoryBattlePostCard (batalhas) — só ajustes pequenos de robustez
// ====================================
class TerritoryBattlePostCard extends StatelessWidget {
  final String postId;
  final Map<String, dynamic> data;
  final DateTime postTime;
  final VoidCallback onComment;

  const TerritoryBattlePostCard({
    super.key,
    required this.postId,
    required this.data,
    required this.postTime,
    required this.onComment,
  });

  @override
  Widget build(BuildContext context) {
    var s = SeasonThemeScope.of(context);
    final primary = s.primary;
    final onSurface = s.primaryForeground;

    final winnerName = (data['winnerName'] ?? data['authorName'] ?? 'Jogador').toString();
    final winnerPhoto = (data['winnerPhoto'] ?? data['authorPhoto'] ?? '').toString();

    final loserName = (data['loserName'] ?? 'Jogador').toString();
    final loserPhoto = (data['loserPhoto'] ?? '').toString();

    final progressRaw = data['progress'];
    final double progress = (progressRaw is num) ? progressRaw.toDouble().clamp(0.0, 1.0) : 0.0;

    final territoryId = (data['territoryId'] ?? '').toString();
    final battleTitle = (data['battleTitle'] ?? data['text'] ?? data['title'] ?? '').toString();

    // 🔥 barras estilo luta
    final double winnerBar = (0.55 + (progress * 0.45)).clamp(0.0, 1.0);
    final double loserBar = (1.0 - winnerBar).clamp(0.0, 1.0);

    final CollectionReference<Map<String, dynamic>> reactionsCol =
    FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .collection('reactions');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final Stream<DocumentSnapshot<Map<String, dynamic>>> myDoc =
    (uid != null)
        ? reactionsCol.doc(uid).snapshots()
        : Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: s.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 8),
            color: Colors.black.withOpacity(0.35),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // topo
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: primary.withOpacity(0.45)),
                    ),
                    child: Text(
                      'BATALHA',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: primary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    timeago.format(postTime, locale: 'pt_BR'),
                    style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ],
              ),
            ),

            // VS header (fundo gamer)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    s.secondaryForeground.withOpacity(0.06),
                    s.secondaryForeground.withOpacity(0.02),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border(
                  top: BorderSide(color: s.border),
                  bottom: BorderSide(color: s.border),
                ),
              ),
              child: Row(
                children: [
                  _fighter(
                    name: winnerName,
                    photoUrl: winnerPhoto,
                    sideLabel: "WIN",
                    sideColor: Colors.greenAccent,
                    context: context, s: s = SeasonThemeScope.of(context),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(width: 56, child: _vsCenter(progress: progress)),
                  const SizedBox(width: 10),
                  _fighter(
                    name: loserName,
                    photoUrl: loserPhoto,
                    sideLabel: "LOSE",
                    sideColor: Colors.redAccent,
                    alignRight: true,
                    context: context,
                    s: s = SeasonThemeScope.of(context),
                  ),
                ],
              ),
            ),

            // barras de vida
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Column(
                children: [
                  _hpBar(label: winnerName, value: winnerBar, alignRight: false,context: context,
                    s: s = SeasonThemeScope.of(context),),
                  const SizedBox(height: 8),
                  _hpBar(label: loserName, value: loserBar, alignRight: true, context: context,
                    s: s = SeasonThemeScope.of(context),),
                ],
              ),
            ),

            if (battleTitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
                child: Text(
                  battleTitle,
                  style: TextStyle(color: s.secondary.withOpacity(0.7), fontWeight: FontWeight.w700, height: 1.2),
                ),
              ),

            if (territoryId.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
                child: Text(
                  'Território: $territoryId',
                  style: TextStyle(color: s.primary, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),

            // ações
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
              child: Row(
                children: [
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: myDoc,
                    builder: (context, snap) {
                      final data = snap.data?.data();
                      final myType = data?['type'] as String?;
                      final isLiked = myType == 'like' || myType == 'love';

                      return IconButton(
                        icon: Icon(
                          isLiked ? Icons.favorite_rounded : Icons.favorite_border,
                          color: isLiked ? Colors.redAccent : s.mutedForeground,
                        ),
                        onPressed: () async {
                          final uid = FirebaseAuth.instance.currentUser!.uid;

                          // ✅ usa o reactionsCol tipado
                          final ref = reactionsCol.doc(uid);

                          if (myType != null) {
                            await ref.delete();
                          } else {
                            await ref.set({
                              'type': 'like',
                              'timestamp': FieldValue.serverTimestamp(),
                            });
                          }

                          HapticFeedback.selectionClick();
                        },
                      );
                    },
                  ),

                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('posts').doc(postId).collection('comments').snapshots(),
                    builder: (context, snap) {
                      final count = snap.data?.docs.length ?? 0;
                      return TextButton.icon(
                        onPressed: onComment,
                        icon: Icon(Icons.chat_bubble_outline, color: s.mutedForeground),
                        label: Text(
                          count.toString(),
                          style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w800),
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.share_outlined, color: s.mutedForeground),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vsCenter({required double progress}) {
    final pct = (progress * 100).round();
    final isFull = progress >= 0.999;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'VS',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.25),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(
            isFull ? 'KO!' : '$pct%',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ],
    );
  }

  Widget _fighter({
    required BuildContext context,
    required String name,
    required String photoUrl,
    required String sideLabel,
    required Color sideColor,
    bool alignRight = false,
    required dynamic s,
  }) {

    final avatar = CircleAvatar(
      radius: 22,
      backgroundColor: Colors.white10,
      backgroundImage: (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
      child: (photoUrl.isEmpty) ? const Icon(Icons.person, color: Colors.white54) : null,
    );

    final label = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: sideColor.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: sideColor.withOpacity(0.5)),
      ),
      child: Text(
        sideLabel,
        style: TextStyle(
          color: sideColor,
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: 0.8,
        ),
      ),
    );

    final nameText = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      style: TextStyle(color: s.primary, fontWeight: FontWeight.w900),
    );

    final info = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        label,
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 110),
          child: nameText,
        ),
      ],
    );

    return Expanded(
      child: Row(
        mainAxisAlignment: alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: alignRight
            ? [Flexible(child: info), const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), Flexible(child: info)],
      ),
    );
  }

  Widget _hpBar({
    required String label,
    required double value,
    required bool alignRight,
    required dynamic s, required BuildContext context,
  }) {
    final v = value.clamp(0.0, 1.0);
    return Row(
      children: [
        if (!alignRight)
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: s.secondaryForeground, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        Expanded(
          flex: 2,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 10,
              backgroundColor: s.muted,
              valueColor: AlwaysStoppedAnimation<Color>(
                alignRight ? Colors.redAccent : Colors.greenAccent,
              ),
            ),
          ),
        ),
        if (alignRight)
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(color: s.secondaryForeground, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

// ====================================
// PromoPostCard — corrigido/robusto
// ====================================
class PromoPostCard extends StatelessWidget {
  final String postId;
  final Map<String, dynamic> data;
  final DateTime postTime;
  final String authorId;
  final VoidCallback onComment;

  const PromoPostCard({
    super.key,
    required this.postId,
    required this.data,
    required this.postTime,
    required this.authorId,
    required this.onComment,
  });

  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link inválido.')));
      return;
    }

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    var s = SeasonThemeScope.of(context);
    final primary = s.primary;
    final onSurface = s.primaryForeground;

    final muted = s.mutedForeground;
    final border = s.border;

    final title = (data['title'] ?? 'Promoção').toString();
    final text = (data['text'] ?? '').toString();
    final imageUrl = (data['imageUrl'] ?? '').toString();

    final ctaText = (data['ctaButtonText'] ?? 'Saiba mais').toString();
    final ctaUrl = (data['ctaButtonUrl'] ?? '').toString();
    final promoCode = (data['promoCode'] ?? '').toString();

    final hasCta = ctaUrl.trim().isNotEmpty;

    final CollectionReference<Map<String, dynamic>> reactionsCol =
    FirebaseFirestore.instance
        .collection('posts')
        .doc(postId)
        .collection('reactions');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final Stream<DocumentSnapshot<Map<String, dynamic>>> myDoc =
    (uid != null)
        ? reactionsCol.doc(uid).snapshots()
        : Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: s.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: s.border),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 8),
            color: s.mutedForeground.withOpacity(0.35),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: primary.withOpacity(0.45)),
                    ),
                    child: Text(
                      'PROMOÇÃO',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: primary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    timeago.format(postTime, locale: 'pt_BR'),
                    style: TextStyle(
                      color: s.mutedForeground,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Imagem
            if (imageUrl.trim().isNotEmpty)
              Image.network(
                imageUrl,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),

            // Conteúdo
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: s.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      height: 1.15,
                    ),
                  ),
                  if (text.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      text,
                      style: TextStyle(
                        color: muted.withOpacity(0.7),
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],

                  if (promoCode.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: s.accent.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.discount_rounded, size: 16, color: onSurface.withOpacity(0.7)),
                              const SizedBox(width: 8),
                              Text(
                                promoCode,
                                style: TextStyle(
                                  color: s.accentForeground,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: promoCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('✅ Cupom copiado!')),
                            );
                            HapticFeedback.selectionClick();
                          },
                          icon: Icon(Icons.copy_rounded, size: 18, color: primary),
                          label: Text('Copiar', style: TextStyle(color: primary, fontWeight: FontWeight.w900)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: primary.withOpacity(0.65)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: hasCta ? () => _openUrl(context, ctaUrl) : null,
                      icon: const Icon(Icons.open_in_new_rounded, color: Colors.black),
                      label: Text(
                        ctaText,
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        disabledBackgroundColor: Colors.white24,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Ações
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
              child: Row(
                children: [
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: myDoc,
                    builder: (context, snap) {
                      final data = snap.data?.data();
                      final myType = data?['type'] as String?;
                      final isLiked = myType == 'like' || myType == 'love';

                      return IconButton(
                        icon: Icon(
                          isLiked ? Icons.favorite_rounded : Icons.favorite_border,
                          color: isLiked ? Colors.redAccent : muted.withOpacity(0.7),
                        ),
                        onPressed: () async {
                          final uid = FirebaseAuth.instance.currentUser!.uid;

                          // ✅ usa o reactionsCol tipado
                          final ref = reactionsCol.doc(uid);

                          if (myType != null) {
                            await ref.delete();
                          } else {
                            await ref.set({
                              'type': 'like',
                              'timestamp': FieldValue.serverTimestamp(),
                            });
                          }

                          HapticFeedback.selectionClick();
                        },
                      );
                    },
                  ),

                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('posts').doc(postId).collection('comments').snapshots(),
                    builder: (context, snap) {
                      final count = snap.data?.docs.length ?? 0;
                      return TextButton.icon(
                        onPressed: onComment,
                        icon: Icon(Icons.chat_bubble_outline, color: muted.withOpacity(0.7)),
                        label: Text(
                          count.toString(),
                          style: TextStyle(color: muted.withOpacity(0.7), fontWeight: FontWeight.w800),
                        ),
                      );
                    },
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.share_outlined, color: muted.withOpacity(0.7)),
                    onPressed: () {},
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


