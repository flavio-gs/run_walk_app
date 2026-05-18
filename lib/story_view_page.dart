import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:timeago/timeago.dart' as timeago;

class StoryViewPage extends StatefulWidget {
  final String authorId;
  final List<DocumentSnapshot> stories;

  const StoryViewPage({
    super.key,
    required this.authorId,
    required this.stories,
  });

  @override
  State<StoryViewPage> createState() => _StoryViewPageState();
}

class _StoryViewPageState extends State<StoryViewPage> with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animationController;
  int _currentIndex = 0;
  VideoPlayerController? _videoController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _animationController = AnimationController(vsync: this);

    _loadStory(story: widget.stories[_currentIndex], animateToPage: false);

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextStory();
      }
    });
  }

  void _nextStory() {
    _animationController.stop();
    _animationController.reset();
    _audioPlayer.stop();
    setState(() {
      if (_currentIndex + 1 < widget.stories.length) {
        _currentIndex++;
        _loadStory(story: widget.stories[_currentIndex]);
      } else {
        Navigator.pop(context);
      }
    });
  }

  void _previousStory() {
    _animationController.stop();
    _animationController.reset();
    _audioPlayer.stop();
    setState(() {
      if (_currentIndex > 0) {
        _currentIndex--;
        _loadStory(story: widget.stories[_currentIndex]);
      } else {
        _loadStory(story: widget.stories[_currentIndex]);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    _videoController?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _loadStory({required DocumentSnapshot story, bool animateToPage = true}) {
    _animationController.stop();
    _animationController.reset();
    _audioPlayer.stop();

    final data = story.data() as Map<String, dynamic>;
    final type = data['type'];

    if (data['music'] != null) {
      _audioPlayer.play(UrlSource(data['music']['previewUrl']));
    }

    // Marca como visualizado
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance.collection('stories').doc(story.id).update({
        'viewers': FieldValue.arrayUnion([user.uid])
      });
    }

    if (type == 'video') {
      _videoController?.dispose();
      _videoController = VideoPlayerController.networkUrl(Uri.parse(data['mediaUrl']))
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {});
          if (_videoController!.value.isInitialized) {
            _animationController.duration = _videoController!.value.duration;
            _videoController!.play();
            if (!_isPaused) _animationController.forward();
          }
        });
    } else {
      if (data['music'] != null) {
        _animationController.duration = const Duration(seconds: 30);
      } else {
        _animationController.duration = const Duration(seconds: 5);
      }
      if (!_isPaused) _animationController.forward();
    }

    if (animateToPage) {
      _pageController.animateToPage(
        _currentIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _pauseStory() {
    setState(() => _isPaused = true);
    _animationController.stop();
    _videoController?.pause();
    _audioPlayer.pause();
  }

  void _resumeStory() {
    setState(() => _isPaused = false);
    _animationController.forward();
    _videoController?.play();
    _audioPlayer.resume();
  }

  void _showStoryMenu(BuildContext context, String storyId) {
    _pauseStory();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Excluir story', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(storyId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.close, color: Colors.white),
                title: const Text('Cancelar', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    ).then((_) => _resumeStory());
  }

  void _confirmDelete(String storyId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Excluir story?', style: TextStyle(color: Colors.white)),
        content: const Text('Tem certeza que deseja apagar este story para sempre?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(color: Colors.white70))),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteStory(storyId);
            },
            child: const Text('Excluir', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteStory(String storyId) async {
    try {
      await FirebaseFirestore.instance.collection('stories').doc(storyId).delete();
      if (!mounted) return;
      if (widget.stories.length <= 1) {
        Navigator.pop(context);
      } else {
        setState(() {
          widget.stories.removeAt(_currentIndex);
          if (_currentIndex >= widget.stories.length) _currentIndex = widget.stories.length - 1;
          _loadStory(story: widget.stories[_currentIndex]);
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleReaction(String reactionType) async {
    final user = FirebaseAuth.instance.currentUser!;
    final storyId = widget.stories[_currentIndex].id;
    final doc = await FirebaseFirestore.instance.collection('stories').doc(storyId).get();
    if (!doc.exists) return;
    final storyData = doc.data() as Map<String, dynamic>;
    final reactions = Map<String, dynamic>.from(storyData['reactions'] ?? {});

    if (reactions[user.uid]?['type'] == reactionType) {
      reactions.remove(user.uid);
    } else {
      reactions[user.uid] = {'type': reactionType, 'name': user.displayName ?? 'Usuário', 'photo': user.photoURL ?? ''};
    }
    await FirebaseFirestore.instance.collection('stories').doc(storyId).update({'reactions': reactions});
    setState(() => widget.stories[_currentIndex] = doc);
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final storyId = widget.stories[_currentIndex].id;
    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('stories').doc(storyId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            if (widget.stories.isNotEmpty && _currentIndex < widget.stories.length) {
              final localData = widget.stories[_currentIndex].data() as Map<String, dynamic>?;
              if (localData == null) return const Center(child: CircularProgressIndicator());
              return _buildStoryContent(localData, {}, storyId);
            }
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});
          return _buildStoryContent(data, reactions, storyId);
        },
      ),
    );
  }

  Widget _buildStoryContent(Map<String, dynamic> data, Map<String, dynamic> reactions, String storyId) {
    return GestureDetector(
      onLongPressStart: (_) => _pauseStory(),
      onLongPressEnd: (_) => _resumeStory(),
      onTapDown: (details) {
        final dx = details.globalPosition.dx;
        final width = MediaQuery.of(context).size.width;
        if (dx < width / 3) _previousStory(); else if (dx > 2 * width / 3) _nextStory();
      },
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.stories.length,
            itemBuilder: (context, index) {
              final s = (index == _currentIndex)
                  ? data
                  : widget.stories[index].data() as Map<String, dynamic>;
              
              final Color bgColor = s['backgroundColor'] != null ? Color(int.parse(s['backgroundColor'])) : Colors.black;
              final List<dynamic> items = s['items'] ?? [];

              return Stack(
                children: [
                  Container(color: bgColor),
                  if (s['mediaUrl'] != null)
                    Center(
                      child: s['type'] == 'video' && index == _currentIndex && _videoController != null 
                        ? AspectRatio(aspectRatio: _videoController!.value.aspectRatio, child: VideoPlayer(_videoController!)) 
                        : Image.network(s['mediaUrl'], fit: BoxFit.contain)
                    ),
                  
                  if (s['type'] == 'poll') _buildPollView(s),

                  ...items.map((item) => Positioned(
                    left: item['dx'],
                    top: item['dy'],
                    child: Transform.scale(
                      scale: item['scale'] ?? 1.0,
                      child: Text(item['content'], style: TextStyle(color: Colors.white, fontSize: item['type'] == 0 ? 28 : 50, fontWeight: FontWeight.bold, shadows: const [Shadow(blurRadius: 10, color: Colors.black45)])),
                    ),
                  )),
                ],
              );
            },
          ),

          // Top UI
          Positioned(
            top: 50,
            left: 10,
            right: 10,
            child: Column(
              children: [
                Row(children: widget.stories.asMap().entries.map((e) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: AnimatedBuilder(animation: _animationController, builder: (context, child) => LinearProgressIndicator(value: e.key == _currentIndex ? _animationController.value : (e.key < _currentIndex ? 1.0 : 0.0), backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(Colors.white), minHeight: 2))))).toList()),
                const SizedBox(height: 12),
                Row(children: [
                  CircleAvatar(radius: 18, backgroundImage: NetworkImage(data['authorPhoto'])),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(data['authorName'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    if (data['timestamp'] != null) Text(timeago.format((data['timestamp'] as Timestamp).toDate(), locale: 'pt_BR'), style: const TextStyle(color: Colors.white70, fontSize: 10)),
                  ]),
                  const Spacer(),
                  if (data['authorId'] == FirebaseAuth.instance.currentUser?.uid) IconButton(icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: () => _showStoryMenu(context, storyId)),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                ]),
              ],
            ),
          ),
          
          if (data['music'] != null) Positioned(top: 120, left: 20, child: Chip(label: Text("${data['music']['trackName']} - ${data['music']['artistName']}", style: const TextStyle(fontSize: 10)))),

          // Bottom UI
          Positioned(bottom: 40, left: 0, right: 0, child: Column(children: [
            if (reactions.isNotEmpty) _buildReactionsSummary(reactions),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _reactionButton('like', '👍', reactions),
              const SizedBox(width: 20),
              _reactionButton('love', '❤️', reactions),
              const SizedBox(width: 20),
              _reactionButton('fire', '🔥', reactions),
            ])
          ])),
        ],
      ),
    );
  }

  Widget _reactionButton(String type, String emoji, Map<String, dynamic> reactions) {
    final isSelected = reactions[FirebaseAuth.instance.currentUser!.uid]?['type'] == type;
    return GestureDetector(
      onTap: () => _toggleReaction(type),
      child: CircleAvatar(backgroundColor: isSelected ? Colors.white30 : Colors.black45, child: Text(emoji, style: const TextStyle(fontSize: 24))),
    );
  }

  Widget _buildReactionsSummary(Map<String, dynamic> reactions) {
    return GestureDetector(
      onTap: () => _showReactionsList(reactions),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)), child: Text('${reactions.length} reações', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
    );
  }

  void _showReactionsList(Map<String, dynamic> reactions) {
    _pauseStory();
    showModalBottomSheet(context: context, backgroundColor: Colors.grey[900], builder: (context) => ListView(shrinkWrap: true, children: reactions.values.map((r) => ListTile(leading: CircleAvatar(backgroundImage: NetworkImage(r['photo'])), title: Text(r['name'], style: const TextStyle(color: Colors.white)), trailing: Text(r['type'] == 'like' ? '👍' : r['type'] == 'love' ? '❤️' : '🔥'))).toList())).then((_) => _resumeStory());
  }

  Widget _buildPollView(Map<String, dynamic> data) {
    final options = List<String>.from(data['options'] ?? []);
    final votes = Map<String, dynamic>.from(data['votes'] ?? {});
    final userId = FirebaseAuth.instance.currentUser!.uid;
    int total = 0; votes.forEach((k, v) => total += (v as List).length);
    bool voted = votes.values.any((v) => (v as List).contains(userId));

    return Center(
      child: Container(
        padding: const EdgeInsets.all(20), margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(15)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(data['question'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 20),
          ...options.asMap().entries.map((e) {
            final count = (votes[e.key.toString()] as List).length;
            final pct = total == 0 ? 0 : (count / total * 100).round();
            return GestureDetector(
              onTap: () { if (!voted) FirebaseFirestore.instance.collection('stories').doc(widget.stories[_currentIndex].id).update({'votes.${e.key}': FieldValue.arrayUnion([userId])}); },
              child: Container(
                margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(e.value), if (voted) Text('$pct%')]),
              ),
            );
          })
        ]),
      ),
    );
  }
}
