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
    setState(() {
      if (_currentIndex > 0) {
        _currentIndex--;
        _loadStory(story: widget.stories[_currentIndex]);
      } else {
        // Reinicia o primeiro story
        _loadStory(story: widget.stories[_currentIndex]);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _loadStory({required DocumentSnapshot story, bool animateToPage = true}) {
    _animationController.stop();
    _animationController.reset();

    final data = story.data() as Map<String, dynamic>;
    final type = data['type'];

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
      _animationController.duration = const Duration(seconds: 5);
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
  }

  void _resumeStory() {
    setState(() => _isPaused = false);
    _animationController.forward();
    _videoController?.play();
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white70)),
          ),
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
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Story excluído com sucesso.')),
      );

      // Se for o único story, fecha a tela. Caso contrário, vai para o próximo.
      if (widget.stories.length <= 1) {
        Navigator.pop(context);
      } else {
        setState(() {
          widget.stories.removeAt(_currentIndex);
          // Se o story excluído era o último, volta um índice
          if (_currentIndex >= widget.stories.length) {
            _currentIndex = widget.stories.length - 1;
          }
          _loadStory(story: widget.stories[_currentIndex]);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir story: $e')),
        );
      }
    }
  }

  Future<void> _toggleReaction(String reactionType) async {
    final user = FirebaseAuth.instance.currentUser!;
    final storyId = widget.stories[_currentIndex].id;
    
    // Obter dados atualizados do documento para evitar sobrescrever reações de outros
    final doc = await FirebaseFirestore.instance.collection('stories').doc(storyId).get();
    if (!doc.exists) return;
    
    final storyData = doc.data() as Map<String, dynamic>;
    final reactions = Map<String, dynamic>.from(storyData['reactions'] ?? {});

    if (reactions[user.uid]?['type'] == reactionType) {
      reactions.remove(user.uid);
    } else {
      reactions[user.uid] = {
        'type': reactionType,
        'name': user.displayName ?? 'Usuário',
        'photo': user.photoURL ?? '',
      };
    }

    await FirebaseFirestore.instance.collection('stories').doc(storyId).update({
      'reactions': reactions,
    });

    // Atualiza a lista local de stories para refletir a mudança visualmente
    setState(() {
      widget.stories[_currentIndex] = doc; // O objeto final DocumentSnapshot não é editável, mas podemos substituir na lista se ela for mutável ou apenas forçar o rebuild.
      // Na verdade, como DocumentSnapshot é imutável e widget.stories pode ser imutável, 
      // o ideal seria um StreamBuilder por story, mas vamos forçar o rebuild do frame atual.
    });

    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.stories[_currentIndex];
    final data = story.data() as Map<String, dynamic>;
    final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});

    final storyId = widget.stories[_currentIndex].id;

    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('stories').doc(storyId).snapshots(),
        builder: (context, snapshot) {
          // Se o documento não existe (foi excluído), evitamos o cast e mostramos um carregando
          // ou usamos o dado que já tínhamos em memória na lista original.
          if (!snapshot.hasData || !snapshot.data!.exists) {
            // Se ainda houver stories na lista, mostramos o dado local enquanto a página muda
            if (widget.stories.isNotEmpty && _currentIndex < widget.stories.length) {
              final localData = widget.stories[_currentIndex].data() as Map<String, dynamic>?;
              if (localData == null) return const Center(child: CircularProgressIndicator(color: Colors.white));
              return _buildStoryContent(localData, {}, storyId); 
            }
            return const Center(child: CircularProgressIndicator(color: Colors.white));
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
      onTapDown: (details) => _onTapDown(details),
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

              if (s['type'] == 'image') {
                return Image.network(s['mediaUrl'], fit: BoxFit.contain);
              } else if (s['type'] == 'video') {
                if (_videoController != null && _videoController!.value.isInitialized) {
                  return Center(
                    child: AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    ),
                  );
                }
              } else if (s['type'] == 'poll') {
                return _buildPollView(s);
              }
              return const Center(child: CircularProgressIndicator(color: Colors.white));
            },
          ),

          // Top UI
          Positioned(
            top: 50,
            left: 10,
            right: 10,
            child: Column(
              children: [
                Row(
                  children: widget.stories.asMap().entries.map((e) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: AnimatedBuilder(
                          animation: _animationController,
                          builder: (context, child) {
                            return LinearProgressIndicator(
                              value: e.key == _currentIndex
                                  ? _animationController.value
                                  : (e.key < _currentIndex ? 1.0 : 0.0),
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                              minHeight: 2,
                            );
                          },
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundImage: (data['authorPhoto'] != null && data['authorPhoto'].toString().isNotEmpty)
                          ? NetworkImage(data['authorPhoto'])
                          : const AssetImage('assets/icon/logo_principal.png') as ImageProvider,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['authorName'] ?? 'Usuário',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                        if (data['timestamp'] != null)
                          Text(
                            timeago.format((data['timestamp'] as Timestamp).toDate(), locale: 'pt_BR'),
                            style: const TextStyle(color: Colors.white70, fontSize: 10),
                          ),
                      ],
                    ),
                    const Spacer(),
                    if (data['authorId'] == FirebaseAuth.instance.currentUser?.uid)
                      IconButton(
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        onPressed: () => _showStoryMenu(context, storyId),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bottom Reactions
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (reactions.isNotEmpty)
                  _buildReactionsSummary(reactions),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _reactionButton('like', '👍', reactions),
                    const SizedBox(width: 20),
                    _reactionButton('love', '❤️', reactions),
                    const SizedBox(width: 20),
                    _reactionButton('fire', '🔥', reactions),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _reactionButton(String type, String emoji, Map<String, dynamic> reactions) {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final isSelected = reactions[userId]?['type'] == type;

    return GestureDetector(
      onTap: () => _toggleReaction(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withOpacity(0.3) : Colors.black45,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 1.5) : null,
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }

  Widget _buildReactionsSummary(Map<String, dynamic> reactions) {
    return GestureDetector(
      onTap: () => _showReactionsList(reactions),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: reactions.values.take(3).toList().asMap().entries.map((e) {
                return Padding(
                  padding: EdgeInsets.only(left: e.key * 15.0),
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: Colors.white,
                    child: CircleAvatar(
                      radius: 9,
                      backgroundImage: e.value['photo'].isNotEmpty
                          ? NetworkImage(e.value['photo'])
                          : const AssetImage('assets/icon/logo_principal.png') as ImageProvider,
                    ),
                  ),
                );
              }).toList(),
            ),
            SizedBox(width: reactions.length > 1 ? (reactions.length.clamp(0, 3) * 10).toDouble() : 8),
            Text(
              '${reactions.length} reações',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  void _showReactionsList(Map<String, dynamic> reactions) {
    _pauseStory();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Reações', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: reactions.values.map((r) {
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: r['photo'].isNotEmpty
                            ? NetworkImage(r['photo'])
                            : const AssetImage('assets/icon/logo_principal.png') as ImageProvider,
                      ),
                      title: Text(r['name'], style: const TextStyle(color: Colors.white)),
                      trailing: Text(r['type'] == 'like' ? '👍' : r['type'] == 'love' ? '❤️' : '🔥', style: const TextStyle(fontSize: 20)),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) => _resumeStory());
  }

  Widget _buildPollView(Map<String, dynamic> data) {
    final question = data['question'] ?? 'Pergunta';
    final options = List<String>.from(data['options'] ?? ['Opção 1', 'Opção 2']);
    final votes = Map<String, dynamic>.from(data['votes'] ?? {});
    final userId = FirebaseAuth.instance.currentUser!.uid;

    int totalVotes = 0;
    votes.forEach((key, value) {
      if (value is List) totalVotes += value.length;
    });

    bool hasVoted = false;
    int votedIndex = -1;
    votes.forEach((key, value) {
      if (value is List && value.contains(userId)) {
        hasVoted = true;
        votedIndex = int.tryParse(key) ?? -1;
      }
    });

    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 20)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              question,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 24),
            ...options.asMap().entries.map((e) {
              final index = e.key;
              final text = e.value;
              final optionVotes = (votes[index.toString()] as List? ?? []).length;
              final percent = totalVotes == 0 ? 0.0 : optionVotes / totalVotes;

              return GestureDetector(
                onTap: () async {
                  if (!hasVoted) {
                    final storyId = widget.stories[_currentIndex].id;
                    
                    // Pausa o story enquanto vota
                    _pauseStory();
                    
                    try {
                      await FirebaseFirestore.instance.collection('stories').doc(storyId).update({
                        'votes.${index}': FieldValue.arrayUnion([userId]),
                      });
                      
                      // Atualiza o estado local do snapshot se necessário, 
                      // mas o ideal é que o pai ou um StreamBuilder cuide disso.
                      // Como estamos usando widget.stories (lista estática passada no início),
                      // vamos atualizar os dados localmente para feedback instantâneo.
                      setState(() {
                        final currentVotes = List<dynamic>.from(votes[index.toString()] ?? []);
                        currentVotes.add(userId);
                        votes[index.toString()] = currentVotes;
                      });
                      
                      HapticFeedback.mediumImpact();
                    } catch (e) {
                      debugPrint('Erro ao votar: $e');
                    } finally {
                      _resumeStory();
                    }
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  height: 50,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12, width: 1.5),
                    color: hasVoted && votedIndex == index ? Colors.blueAccent.withOpacity(0.1) : Colors.transparent,
                  ),
                  child: Stack(
                    children: [
                      if (hasVoted)
                        AnimatedFractionallySizedBox(
                          widthFactor: percent,
                          duration: const Duration(milliseconds: 500),
                          child: Container(
                            color: Colors.blueAccent.withOpacity(0.2),
                          ),
                        ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(text, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black)),
                              if (hasVoted)
                                Text('${(percent * 100).round()}%', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w900)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  void _onTapDown(TapDownDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dx = details.globalPosition.dx;

    if (dx < screenWidth / 3) {
      _previousStory();
    } else if (dx > 2 * screenWidth / 3) {
      _nextStory();
    }
  }
}
