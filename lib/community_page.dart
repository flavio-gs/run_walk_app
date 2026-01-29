import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:run_walk_app/profile_page.dart';
import 'package:run_walk_app/create_challenge_page.dart';
import 'package:run_walk_app/grupo/create_group_page.dart';
import 'package:run_walk_app/grupo/groups_explore_page.dart';
import 'package:run_walk_app/theme/season_theme_scope.dart';
import 'challenge_details_page.dart';
import 'grupo/group_page.dart';

// ✅ AJUSTE AQUI se o seu tema tiver outro nome:
// Exemplo: final s = SeasonTheme.of(context);
// Campos esperados: bg, card, primary, stroke, text, textMuted, danger, success...
dynamic _S(BuildContext context) => SeasonThemeScope.of(context); // <-- troque se precisar

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ValueNotifier<String> _searchQuery = ValueNotifier('');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchQuery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _S(context);

    return Scaffold(
      backgroundColor: s.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: s.background,
        surfaceTintColor: s.background,
        centerTitle: true,
        toolbarHeight: 64,
        title: Text(
          'Comunidade',
          style: TextStyle(
            color: s.foreground,
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: -0.2,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(118),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: _SearchBar(
                  onChanged: (v) => _searchQuery.value = v,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: s.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: s.border),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    indicator: BoxDecoration(
                      color: s.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    labelColor: Colors.black, // texto preto no botão primary (fica lindo)
                    unselectedLabelColor: s.mutedForeground,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w900),
                    tabs: const [
                      Tab(text: 'Descobrir'),
                      Tab(text: 'Ranking'),
                      Tab(text: 'Desafios'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const BouncingScrollPhysics(),
        children: [
          _DiscoverTab(
            firestore: _firestore,
            auth: _auth,
            searchQuery: _searchQuery,
          ),
          _RankingTab(
            firestore: _firestore,
            auth: _auth,
          ),
          _CommunityChallengesTab(
            firestore: _firestore,
            auth: _auth,
          ),
        ],
      ),
    );
  }
}

/// 🔍 Barra de busca
class _SearchBar extends StatefulWidget {
  final ValueChanged<String>? onChanged;
  const _SearchBar({this.onChanged});

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final s = _S(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: s.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: s.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: s.mutedForeground),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: (v) => setState(() {
                widget.onChanged?.call(v);
              }),
              style: TextStyle(color: s.foreground, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: 'Encontre jogadores...',
                hintStyle:
                TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w600),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            IconButton(
              splashRadius: 18,
              onPressed: () {
                setState(() {
                  _controller.clear();
                  widget.onChanged?.call('');
                });
              },
              icon: Icon(Icons.close, color: s.mutedForeground),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: s.primary.withOpacity(0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: s.primary.withOpacity(0.35)),
              ),
              child: Text(
                'Dica: use @',
                style: TextStyle(
                  color: s.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================
// 🔥 ABA: DESAFIOS DA COMUNIDADE
// =============================================================
class _CommunityChallengesTab extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  const _CommunityChallengesTab({
    required this.firestore,
    required this.auth,
  });

  @override
  State<_CommunityChallengesTab> createState() => _CommunityChallengesTabState();
}

class _CommunityChallengesTabState extends State<_CommunityChallengesTab> {
  String _filter = 'ativos'; // ativos | encerrados
  bool _loading = false;
  List<QueryDocumentSnapshot> _challenges = [];

  @override
  void initState() {
    super.initState();
    _loadChallenges();
  }

  Future<void> _loadChallenges() async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now();
      Query query = widget.firestore.collection('challenges');

      if (_filter == 'ativos') {
        query = query.where('endDate', isGreaterThan: Timestamp.fromDate(now));
      } else {
        query = query.where('endDate',
            isLessThanOrEqualTo: Timestamp.fromDate(now));
      }

      final snap = await query.orderBy('startDate', descending: true).get();
      setState(() => _challenges = snap.docs);
    } catch (e) {
      debugPrint('Erro ao carregar desafios: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _S(context);

    return Scaffold(
      backgroundColor: s.background,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 10,
        ),
        child: FloatingActionButton.extended(
          backgroundColor: s.primary,
          foregroundColor: Colors.black,
          icon: const Icon(Icons.add),
          label:
          const Text('Criar desafio', style: TextStyle(fontWeight: FontWeight.w900)),
          onPressed: () async {
            final created = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateChallengePage()),
            );

            if (created == true && mounted) {
              _loadChallenges();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Desafio criado com sucesso 🎯')),
              );
            }
          },
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            24 + MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight + 60,
          ),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '🏁 Desafios da Comunidade',
                  style: TextStyle(
                    color: s.foreground,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                PopupMenuButton<String>(
                  color: s.card,
                  icon: Icon(Icons.filter_list, color: s.mutedForeground),
                  onSelected: (v) {
                    setState(() => _filter = v);
                    _loadChallenges();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'ativos',
                      child: Text('Ativos', style: TextStyle(color: s.foreground)),
                    ),
                    PopupMenuItem(
                      value: 'encerrados',
                      child: Text('Encerrados', style: TextStyle(color: s.foreground)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: s.primary),
                ),
              )
            else if (_challenges.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'Nenhum desafio encontrado 🚀',
                    style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w700),
                  ),
                ),
              )
            else
              Column(
                children: _challenges.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final title = data['title'] ?? 'Desafio sem título';
                  final type = data['type'] ?? 'geral';
                  final start = (data['startDate'] as Timestamp?)?.toDate();
                  final end = (data['endDate'] as Timestamp?)?.toDate();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: s.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: s.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: s.foreground,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _TypeBadge(type: type),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          start != null && end != null
                              ? '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')} → ${end.day.toString().padLeft(2, '0')}/${end.month.toString().padLeft(2, '0')}'
                              : 'Sem data',
                          style: TextStyle(
                            color: s.mutedForeground,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      trailing:
                      Icon(Icons.arrow_forward_ios, color: s.mutedForeground, size: 16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChallengeDetailsPage(challengeId: doc.id),
                          ),
                        );
                      },
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// 1️⃣ ABA "DESCOBRIR"
// =============================================================
class _DiscoverTab extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final ValueNotifier<String> searchQuery;

  const _DiscoverTab({
    required this.firestore,
    required this.auth,
    required this.searchQuery,
    Key? key,
  }) : super(key: key);

  @override
  State<_DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<_DiscoverTab> {
  List<QueryDocumentSnapshot> _nearbyUsers = [];
  bool _loadingNearby = false;

  static const double _nearbyDelta = 0.2; // ~22 km

  @override
  void initState() {
    super.initState();
    _findNearbyRunners();
  }

  Future<void> _findNearbyRunners() async {
    try {
      setState(() => _loadingNearby = true);

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão de localização negada')),
        );
        setState(() => _loadingNearby = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      final lat = pos.latitude;
      final lng = pos.longitude;

      final minLat = lat - _nearbyDelta;
      final maxLat = lat + _nearbyDelta;
      final minLng = lng - _nearbyDelta;
      final maxLng = lng + _nearbyDelta;
      final currentUserId = widget.auth.currentUser?.uid;

      final q = await widget.firestore
          .collection('users')
          .where('isOnline', isEqualTo: true)
          .where('lat', isGreaterThanOrEqualTo: minLat)
          .where('lat', isLessThanOrEqualTo: maxLat)
          .get();

      final nearby = q.docs.where((d) {
        final m = d.data() as Map<String, dynamic>;
        final userLng = (m['lng'] ?? 0).toDouble();
        final uid = (m['uid'] ?? m['userId'])?.toString();
        if (d.id == currentUserId || uid == currentUserId) return false;
        return userLng >= minLng && userLng <= maxLng;
      }).toList();

      if (mounted) setState(() => _nearbyUsers = nearby);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao buscar próximos: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingNearby = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final s = _S(context);

    return ValueListenableBuilder<String>(
      valueListenable: widget.searchQuery,
      builder: (_, query, __) {
        final q = query.trim().toLowerCase();
        final isUserSearch = q.startsWith('@');
        final searchTerm = q.isNotEmpty ? q.substring(1) : '';

        final userStream = (isUserSearch && searchTerm.length >= 2)
            ? widget.firestore
            .collection('users')
            .where('username', isGreaterThanOrEqualTo: searchTerm)
            .where('username', isLessThanOrEqualTo: '$searchTerm\uf8ff')
            .limit(30)
            .snapshots()
            : null;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            // 🔥 Ações rápidas
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: s.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: s.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const CreateGroupPage()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: s.primary,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.groups_rounded),
                      label: const Text(
                        'Criar Clã',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: s.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: s.primary.withOpacity(0.25)),
                    ),
                    child: IconButton(
                      splashRadius: 18,
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const GroupsExplorePage()),
                        );
                      },
                      icon: Icon(Icons.explore_rounded, color: s.primary),
                      tooltip: 'Explorar grupos',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            if (!isUserSearch) ...[
              _MyClansBlock(firestore: widget.firestore, auth: widget.auth),
              const SizedBox(height: 14),
            ],

            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                isUserSearch ? 'Resultados da busca' : 'Corredores próximos',
                style: TextStyle(
                  color: s.foreground,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),

            if (isUserSearch && searchTerm.length >= 2)
              StreamBuilder<QuerySnapshot>(
                stream: userStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: CircularProgressIndicator(color: s.primary),
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          'Nenhum usuário encontrado 😕',
                          style: TextStyle(color: s.primary, fontWeight: FontWeight.w800),
                        ),
                      ),
                    );
                  }

                  final docs = snapshot.data!.docs.cast<QueryDocumentSnapshot>();
                  return _buildUserList(docs);
                },
              )
            else if (_loadingNearby)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: s.primary),
                ),
              )
            else if (_nearbyUsers.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      'Nenhum corredor próximo encontrado 😔',
                      style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w700),
                    ),
                  ),
                )
              else
                _buildUserList(_nearbyUsers),
          ],
        );
      },
    );
  }

  Widget _buildUserList(List<QueryDocumentSnapshot> docs) {
    final s = _S(context);
    final currentUserId = widget.auth.currentUser?.uid;

    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemCount: docs.length,
        itemBuilder: (_, i) {
          final data = docs[i].data() as Map<String, dynamic>;
          final photoUrl = data['photoUrl'] ?? data['photoURL'];
          final targetUserId = (data['uid'] ?? data['userId'] ?? docs[i].id).toString();

          return StreamBuilder<DocumentSnapshot>(
            stream: widget.firestore
                .collection('users')
                .doc(currentUserId)
                .collection('following')
                .doc(targetUserId)
                .snapshots(),
            builder: (_, snapshot) {
              final isFollowing = snapshot.hasData && snapshot.data!.exists;

              return Container(
                width: 240,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: s.background,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: s.primary.withOpacity(0.8)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: s.primary.withOpacity(0.8),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.45),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: photoUrl != null && photoUrl.toString().isNotEmpty
                                ? Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Icon(Icons.person, color: s.mutedForeground),
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Center(
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: s.primary,
                                    ),
                                  ),
                                );
                              },
                            )
                                : Icon(Icons.person, color: s.mutedForeground),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            data['displayName'] ?? 'Corredor',
                            style: TextStyle(
                              color: s.foreground,
                              fontWeight: FontWeight.w900,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '@${data['username'] ?? 'sem_username'}',
                      style: TextStyle(
                        color: s.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 16, color: s.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            data['city'] ?? '---',
                            style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              if (currentUserId == null || currentUserId == targetUserId) return;

                              if (isFollowing) {
                                await widget.firestore
                                    .collection('users')
                                    .doc(currentUserId)
                                    .collection('following')
                                    .doc(targetUserId)
                                    .delete();

                                await widget.firestore
                                    .collection('users')
                                    .doc(targetUserId)
                                    .collection('followers')
                                    .doc(currentUserId)
                                    .delete();
                              } else {
                                await widget.firestore
                                    .collection('users')
                                    .doc(currentUserId)
                                    .collection('following')
                                    .doc(targetUserId)
                                    .set({'timestamp': FieldValue.serverTimestamp()});

                                await widget.firestore
                                    .collection('users')
                                    .doc(targetUserId)
                                    .collection('followers')
                                    .doc(currentUserId)
                                    .set({'timestamp': FieldValue.serverTimestamp()});
                              }

                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isFollowing
                                      ? 'Você deixou de seguir'
                                      : 'Agora você segue este corredor 🎉'),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: isFollowing ? Colors.white : s.primary,
                              foregroundColor: isFollowing ? Colors.black : Colors.white,
                              side: isFollowing
                                  ? const BorderSide(color: Colors.black12)
                                  : BorderSide.none,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              isFollowing ? 'Seguindo' : 'Seguir',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: s.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: s.primary.withOpacity(0.25)),
                          ),
                          child: IconButton(
                            splashRadius: 18,
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProfilePage(userId: targetUserId),
                                ),
                              );
                            },
                            icon: Icon(Icons.info_outline, color: s.primary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MyClansBlock extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  const _MyClansBlock({
    required this.firestore,
    required this.auth,
    Key? key,
  }) : super(key: key);

  @override
  State<_MyClansBlock> createState() => _MyClansBlockState();
}

class _MyClansBlockState extends State<_MyClansBlock> {
  Stream<List<String>> _myGroupIdsStream(String uid) {
    return widget.firestore
        .collectionGroup('members')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final ids = snap.docs
          .map((d) => d.reference.parent.parent?.id)
          .whereType<String>()
          .toSet()
          .toList();
      ids.sort();
      return ids;
    });
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _myGroupsStream(String uid) {
    return _myGroupIdsStream(uid).asyncMap((ids) async {
      if (ids.isEmpty) return <QueryDocumentSnapshot<Map<String, dynamic>>>[];

      final chunks = <List<String>>[];
      for (var i = 0; i < ids.length; i += 10) {
        chunks.add(ids.sublist(i, (i + 10 > ids.length) ? ids.length : i + 10));
      }

      final results = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (final chunk in chunks) {
        final q = await widget.firestore
            .collection('groups')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        results.addAll(q.docs);
      }

      final filtered = results.where((d) {
        final data = d.data();
        return (data['deleted'] == true) == false;
      }).toList();

      filtered.sort((a, b) {
        final an = (a.data()['name'] ?? '').toString().toLowerCase();
        final bn = (b.data()['name'] ?? '').toString().toLowerCase();
        return an.compareTo(bn);
      });

      return filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _S(context);
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: s.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: s.border),
      ),
      child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        stream: _myGroupsStream(uid),
        builder: (_, snap) {
          if (!snap.hasData) {
            return Row(
              children: [
                Icon(Icons.shield_rounded, color: s.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Carregando seus clãs...',
                    style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w800),
                  ),
                ),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: s.primary),
                ),
              ],
            );
          }

          final groupsDocs = snap.data ?? [];
          if (groupsDocs.isEmpty) {
            return Row(
              children: [
                Icon(Icons.shield_rounded, color: s.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Você ainda não faz parte de nenhum clã.',
                    style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w800),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const GroupsExplorePage()),
                  ),
                  child: const Text('Explorar', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            );
          }

          final groupIds = groupsDocs.map((d) => d.id).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_rounded, color: s.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Meus Clãs',
                      style: TextStyle(
                        color: s.foreground,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    '${groupIds.length}',
                    style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: groupIds.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _GroupCardLive(
                    groupId: groupIds[i],
                    firestore: widget.firestore,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GroupCardLive extends StatelessWidget {
  final String groupId;
  final FirebaseFirestore firestore;
  const _GroupCardLive({required this.groupId, required this.firestore});

  @override
  Widget build(BuildContext context) {
    final s = _S(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: firestore.collection('groups').doc(groupId).snapshots(),
      builder: (_, gSnap) {
        if (!gSnap.hasData) return const SizedBox.shrink();

        final data = gSnap.data!.data();
        if (data == null) return const SizedBox.shrink();
        if (data['deleted'] == true) return const SizedBox.shrink();

        final name = (data['name'] ?? 'Clã').toString();
        final isPublic = (data['isPublic'] ?? true) == true;
        final membersCount = (data['membersCount'] ?? 0);

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: uid == null
              ? null
              : firestore.collection('groups').doc(groupId).collection('members').doc(uid).snapshots(),
          builder: (_, mSnap) {
            final role = (mSnap.data?.data() ?? const {})['role']?.toString() ?? 'member';
            final isAdmin = role == 'owner' || role == 'admin';

            final pendingStream = isAdmin
                ? firestore
                .collection('groups')
                .doc(groupId)
                .collection('join_requests')
                .where('status', isEqualTo: 'pending')
                .limit(1)
                .snapshots()
                : null;

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: pendingStream,
              builder: (_, pSnap) {
                final hasPending = (pSnap.data?.docs.isNotEmpty ?? false);

                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => GroupPage(groupId: groupId)),
                    );
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 240,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: s.background,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: s.primary.withOpacity(0.35)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.25),
                              blurRadius: 16,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: s.primary.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: s.primary.withOpacity(0.25)),
                                  ),
                                  child: Icon(
                                    isPublic ? Icons.public_rounded : Icons.lock_rounded,
                                    color: s.primary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: s.foreground,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.people_alt_rounded, size: 16, color: s.mutedForeground),
                                const SizedBox(width: 6),
                                Text(
                                  '$membersCount membros',
                                  style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            const SizedBox(height: 1),
                            InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => GroupPage(groupId: groupId)),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.open_in_new_rounded, size: 18, color: s.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Abrir',
                                      style: TextStyle(
                                        color: s.mutedForeground,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hasPending)
                        Positioned(
                          right: 10,
                          top: 10,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// helper p/ firstOrNull (sem package)
extension _FirstOrNullExt<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

// =============================================================
// 2️⃣ ABA "RANKING" — (era _ChallengesTab)
// =============================================================
class _RankingTab extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  const _RankingTab({required this.firestore, required this.auth});

  @override
  State<_RankingTab> createState() => _RankingTabState();
}

class _RankingTabState extends State<_RankingTab> {
  String _rankingType = 'global'; // global | weekly | friends
  String _metric = 'km'; // km | xp | territories
  bool _loading = false;
  List<QueryDocumentSnapshot> _docs = [];
  int? _userPosition;

  int _xpRounded(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.round();
    final parsed = num.tryParse(v.toString().replaceAll(',', '.'));
    return (parsed ?? 0).round();
  }

  String _fmtXp(dynamic v) => '${_xpRounded(v)} XP';

  @override
  void initState() {
    super.initState();
    _loadRanking();
  }

  Future<List<QueryDocumentSnapshot>> _getUsersByIdsChunked(List<String> ids) async {
    if (ids.isEmpty) return [];
    final chunks = <List<String>>[];
    for (var i = 0; i < ids.length; i += 10) {
      chunks.add(ids.sublist(i, (i + 10 > ids.length) ? ids.length : i + 10));
    }

    final all = <QueryDocumentSnapshot>[];
    for (final c in chunks) {
      final s = await widget.firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: c)
          .get();
      all.addAll(s.docs);
    }
    return all;
  }

  Future<void> _loadRanking() async {
    setState(() => _loading = true);

    try {
      Query query;
      final me = widget.auth.currentUser?.uid;

      final bool isTerritories = _metric == 'territories';
      final String orderField = isTerritories ? 'territories.activeCount' : _metric;

      if (isTerritories) {
        if (_rankingType == 'weekly') _rankingType = 'global';

        if (_rankingType == 'friends') {
          final followsSnap = await widget.firestore
              .collection('users')
              .doc(me)
              .collection('following')
              .get();

          final friendIds = followsSnap.docs.map((d) => d.id).toList();
          if (me != null && me.isNotEmpty) friendIds.add(me);

          // ✅ chunk para não quebrar
          final docs = await _getUsersByIdsChunked(friendIds);
          docs.sort((a, b) {
            final ad = (a.data() as Map<String, dynamic>);
            final bd = (b.data() as Map<String, dynamic>);
            final av = (ad['territories']?['activeCount'] ?? 0) as num;
            final bv = (bd['territories']?['activeCount'] ?? 0) as num;
            return bv.compareTo(av);
          });

          final top = docs.take(50).toList();

          final index = top.indexWhere((d) => d.id == me);
          setState(() {
            _docs = top;
            _userPosition = index != -1 ? index + 1 : null;
          });

          return;
        } else {
          query = widget.firestore
              .collection('users')
              .orderBy(orderField, descending: true)
              .limit(50);
        }
      } else {
        if (_rankingType == 'weekly') {
          final now = DateTime.now();
          final weekStart =
          DateTime(now.year, now.month, now.day - (now.weekday - 1));
          query = widget.firestore
              .collection('leaderboard_weekly')
              .where('weekStart',
              isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart));
        } else if (_rankingType == 'friends') {
          final followsSnap = await widget.firestore
              .collection('users')
              .doc(me)
              .collection('following')
              .get();

          final friendIds = followsSnap.docs.map((d) => d.id).toList();
          if (me != null && me.isNotEmpty) friendIds.add(me);

          // ⚠️ leaderboard_global friends ainda tem whereIn(10)
          // Se você quiser, eu te passo o mesmo chunk aqui também (ou muda estrutura).
          query = widget.firestore
              .collection('leaderboard_global')
              .where('userId',
              whereIn: friendIds.isEmpty ? ['dummy'] : friendIds);
        } else {
          query = widget.firestore.collection('leaderboard_global');
        }

        query = query.orderBy(orderField, descending: true).limit(50);
      }

      final snap = await query.get();
      final docs = snap.docs;

      final index = docs.indexWhere((d) {
        final data = d.data() as Map<String, dynamic>;
        return isTerritories ? (d.id == me) : (data['userId'] == me);
      });

      setState(() {
        _docs = docs;
        _userPosition = index != -1 ? index + 1 : null;
      });
    } catch (e) {
      debugPrint('Erro ao carregar ranking: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeRanking(String type) {
    if (_metric == 'territories' && type == 'weekly') type = 'global';
    setState(() => _rankingType = type);
    _loadRanking();
  }

  void _changeMetric(String metric) {
    setState(() => _metric = metric);
    if (metric == 'territories' && _rankingType == 'weekly') {
      setState(() => _rankingType = 'global');
    }
    _loadRanking();
  }

  @override
  Widget build(BuildContext context) {
    final s = _S(context);
    final bool isTerritories = _metric == 'territories';

    return Container(
      color: s.background,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Text(
            '🏆 Rankings',
            style: TextStyle(
              color: s.foreground,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ToggleChip(
                label: '🌍 Global',
                active: _rankingType == 'global',
                onTap: () => _changeRanking('global'),
              ),
              Opacity(
                opacity: isTerritories ? 0.45 : 1,
                child: IgnorePointer(
                  ignoring: isTerritories,
                  child: _ToggleChip(
                    label: '🗓️ Semanal',
                    active: _rankingType == 'weekly',
                    onTap: () => _changeRanking('weekly'),
                  ),
                ),
              ),
              _ToggleChip(
                label: '👥 Amigos',
                active: _rankingType == 'friends',
                onTap: () => _changeRanking('friends'),
              ),
            ],
          ),

          if (isTerritories) ...[
            const SizedBox(height: 8),
            Text(
              '🗺️ Territórios ativos = territórios que ainda são seus agora.',
              style: TextStyle(
                color: s.mutedForeground,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ToggleChip(
                label: '⚡ XP',
                active: _metric == 'xp',
                onTap: () => _changeMetric('xp'),
              ),
              const SizedBox(width: 8),
              _ToggleChip(
                label: '🏃 KM',
                active: _metric == 'km',
                onTap: () => _changeMetric('km'),
              ),
              const SizedBox(width: 8),
              _ToggleChip(
                label: '🗺️ Territórios',
                active: _metric == 'territories',
                onTap: () => _changeMetric('territories'),
              ),
            ],
          ),

          const SizedBox(height: 20),

          _loading
              ? Center(child: CircularProgressIndicator(color: s.primary))
              : _docs.isEmpty
              ? Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Text(
                'Nenhum dado encontrado neste ranking.',
                style: TextStyle(
                  color: s.mutedForeground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
              : Column(
            children: [
              _PodiumTop3(docs: _docs, metric: _metric),
              const SizedBox(height: 12),

              Container(
                decoration: BoxDecoration(
                  color: s.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: s.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < _docs.length; i++)
                      if (i >= 3)
                        Builder(builder: (_) {
                          final data =
                          _docs[i].data() as Map<String, dynamic>;

                          final displayName = (data['displayName'] ??
                              data['username'] ??
                              'Runner')
                              .toString();

                          final value = _metric == 'xp'
                              ? _fmtXp(data['xp'])
                              : _metric == 'territories'
                              ? '🗺️ ${(data['territories']?['activeCount'] ?? 0)}'
                              : '${((data['km'] ?? 0) as num).toDouble().toStringAsFixed(2)} km';

                          return _LeaderTile(
                            position: i + 1,
                            name: displayName,
                            value: value,
                          );
                        }),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              if (_userPosition != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: s.primary.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: s.primary.withOpacity(0.35)),
                  ),
                  child: Center(
                    child: Text(
                      '🏁 Você está em $_userPositionº lugar '
                          '${_rankingType == 'weekly'
                          ? 'nesta semana!'
                          : _rankingType == 'friends'
                          ? 'entre seus amigos!'
                          : 'no global!'}',
                      style: TextStyle(
                        color: s.foreground,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = _S(context);
    final bg = active ? s.primary : s.card;
    final border = active ? s.primary.withOpacity(0.9) : s.border;
    final txt = active ? Colors.black : s.mutedForeground;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: 1.2),
          boxShadow: [
            BoxShadow(
              blurRadius: 14,
              offset: const Offset(0, 6),
              color: Colors.black.withOpacity(active ? 0.35 : 0.25),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: txt,
            fontWeight: FontWeight.w900,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

class _LeaderTile extends StatelessWidget {
  final int position;
  final String name;
  final String value;

  const _LeaderTile({
    required this.position,
    required this.name,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final s = _S(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.white10,
        child: Text(
          '$position',
          style: TextStyle(color: s.foreground, fontWeight: FontWeight.w900),
        ),
      ),
      title: Text(
        name,
        style: TextStyle(color: s.foreground, fontWeight: FontWeight.w800),
      ),
      trailing: Text(
        value,
        style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PodiumTop3 extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final String metric; // 'xp' | 'km' | 'territories'
  const _PodiumTop3({required this.docs, required this.metric});

  int _xpRounded(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.round();
    final parsed = num.tryParse(v.toString().replaceAll(',', '.'));
    return (parsed ?? 0).round();
  }

  String _fmtXp(dynamic v) => '${_xpRounded(v)} XP';

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) return const SizedBox.shrink();
    final s = _S(context);

    String fmt(int i) {
      final m = docs[i].data() as Map<String, dynamic>;
      if (metric == 'xp') return _fmtXp(m['xp']);
      if (metric == 'territories') {
        final active = (m['territories']?['activeCount'] ?? 0);
        return '🗺️ $active';
      }
      final km = ((m['km'] ?? 0) as num).toDouble();
      return '${km.toStringAsFixed(2)} km';
    }

    String name(int i) {
      final m = docs[i].data() as Map<String, dynamic>;
      return (m['displayName'] ?? m['username'] ?? 'Runner').toString();
    }

    Widget tile(int pos, int index) {
      final isAvailable = docs.length > index;

      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: s.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: s.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.20),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: s.primary.withOpacity(0.25)),
                ),
                child: Text(
                  '$pos',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: s.primary,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isAvailable ? name(index) : '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900, color: s.foreground),
              ),
              const SizedBox(height: 6),
              Text(
                isAvailable ? fmt(index) : '',
                style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        tile(2, 1),
        const SizedBox(width: 10),
        tile(1, 0),
        const SizedBox(width: 10),
        tile(3, 2),
      ],
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final String type; // geral | grupo | oficial
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final s = _S(context);
    final t = type.toLowerCase();
    final label = t == 'oficial' ? 'OFICIAL' : t == 'grupo' ? 'GRUPO' : 'GERAL';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: s.primary.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: s.primary.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: s.primary,
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
