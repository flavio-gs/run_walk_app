import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:run_walk_app/profile_page.dart';
import 'package:run_walk_app/create_challenge_page.dart';
import 'package:run_walk_app/grupo/create_group_page.dart';
import 'package:run_walk_app/grupo/groups_explore_page.dart';


import 'challenge_details_page.dart';
import 'grupo/group_page.dart'; // 🔹 página de criação de desafios (já tens)

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


  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);
  static const Color kCard = Color(0xFF12121A);
  static const Color kStroke = Color(0x1FFFFFFF); // branco 12%



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
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kBg,
        surfaceTintColor: kBg,
        centerTitle: true,
        toolbarHeight: 64,
        title: const Text(
          'Comunidade',
          style: TextStyle(
            color: Colors.white,
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
                    color: kCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    indicator: BoxDecoration(
                      color: kOrange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    labelColor: Colors.black,              // igual feed: selecionado preto no laranja
                    unselectedLabelColor: Colors.white70,
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
          _DiscoverTab(firestore: _firestore, auth: _auth, searchQuery: _searchQuery),
          _ChallengesTab(firestore: _firestore, auth: _auth),
          _CommunityChallengesTab(firestore: _firestore, auth: _auth),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A), // kCard
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
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
          const Icon(Icons.search, color: Colors.white60),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: (v) => setState(() {
                widget.onChanged?.call(v);
              }),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                hintText: 'Encontre jogadores...',
                hintStyle: TextStyle(color: Colors.white54, fontWeight: FontWeight.w600),
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
              icon: const Icon(Icons.close, color: Colors.white54),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF7A00).withOpacity(0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFFF7A00).withOpacity(0.35)),
              ),
              child: const Text(
                'Dica: use @',
                style: TextStyle(
                  color: Color(0xFFFF7A00),
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
// 🔥 NOVA ABA: DESAFIOS DA COMUNIDADE
// =============================================================
class _CommunityChallengesTab extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  const _CommunityChallengesTab({
    required this.firestore,
    required this.auth,
  });

  @override
  State<_CommunityChallengesTab> createState() =>
      _CommunityChallengesTabState();
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
        query = query.where('endDate', isLessThanOrEqualTo: Timestamp.fromDate(now));
      }

      final snap = await query.orderBy('startDate', descending: true).get();
      setState(() => _challenges = snap.docs);
    } catch (e) {
      debugPrint('Erro ao carregar desafios: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0F), // kBg
        floatingActionButton: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 10, // ajusta aqui
          ),
          child: FloatingActionButton.extended(
            backgroundColor: const Color(0xFFFF7A00),
            foregroundColor: Colors.black,
            icon: const Icon(Icons.add),
            label: const Text('Criar desafio', style: TextStyle(fontWeight: FontWeight.w900)),
        onPressed: () async {
          final created = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateChallengePage()),
          );

          // 🔹 Se o usuário criou um desafio com sucesso, recarrega a lista
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
                const Text(
                  '🏁 Desafios da Comunidade',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                PopupMenuButton<String>(
                  color: const Color(0xFF12121A), // kCard
                  icon: const Icon(Icons.filter_list, color: Colors.white60),
                  onSelected: (v) {
                    setState(() => _filter = v);
                    _loadChallenges();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'ativos', child: Text('Ativos', style: TextStyle(color: Colors.white))),
                    PopupMenuItem(value: 'encerrados', child: Text('Encerrados', style: TextStyle(color: Colors.white))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: Color(0xFFFF7A00)),
                ),
              )
            else if (_challenges.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'Nenhum desafio encontrado 🚀',
                    style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w700),
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
                      color: const Color(0xFF12121A), // kCard
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
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
                          style: const TextStyle(
                            color: Colors.white60,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 16),
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
// 1️⃣ ABA "DESCOBRIR" — busca de corredores e sugestões
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

  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);
  static const Color kCard = Color(0xFF12121A);
  static const Color kStroke = Color(0x1FFFFFFF); // branco 12%

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
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão de localização negada')),
        );
        setState(() => _loadingNearby = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao buscar próximos: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingNearby = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: widget.searchQuery,
      builder: (_, query, __) {
        final q = query.trim().toLowerCase();
        final isUserSearch = q.startsWith('@');
        final searchTerm = q.isNotEmpty ? q.substring(1) : '';

        // 🔎 Stream para busca por username
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
                color: kCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white10),
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
                        backgroundColor: kOrange,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                      color: kOrange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kOrange.withOpacity(0.25)),
                    ),
                    child: IconButton(
                      splashRadius: 18,
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const GroupsExplorePage()),
                        );
                      },
                      icon: const Icon(Icons.explore_rounded, color: kOrange),
                      tooltip: 'Explorar grupos',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 🛡️ Meus Clãs
            if (!isUserSearch) ...[
              _MyClansBlock(
                firestore: widget.firestore,
                auth: widget.auth,
              ),
              const SizedBox(height: 14),
            ],


            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                isUserSearch ? 'Resultados da busca' : 'Corredores próximos',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),

            // 🔹 Caso seja busca por usuário com @
            if (isUserSearch && searchTerm.length >= 2)
              StreamBuilder<QuerySnapshot>(
                stream: userStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.black),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          'Nenhum usuário encontrado 😕',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    );
                  }

                  final docs = snapshot.data!.docs;
                  return _buildUserList(docs);
                },
              )

            // 🔹 Caso contrário, mostra os corredores próximos
            else if (_loadingNearby)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: Colors.black),
                ),
              )
            else if (_nearbyUsers.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      'Nenhum corredor próximo encontrado 😔',
                      style: TextStyle(color: Colors.black54),
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
          final targetUserId =
          (data['uid'] ?? data['userId'] ?? docs[i].id).toString();

          return StreamBuilder<DocumentSnapshot>(
            stream: widget.firestore
                .collection('users')
                .doc(currentUserId)
                .collection('following')
                .doc(targetUserId)
                .snapshots(),
            builder: (_, snapshot) {
              final isFollowing =
                  snapshot.hasData && snapshot.data!.exists;

              return Container(
                width: 240,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.orangeAccent),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
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
                            border: Border.all(color: kOrange.withOpacity(0.8), width: 1.2),
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
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.person,
                                color: Colors.white70,
                              ),
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return const Center(
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: kOrange,
                                    ),
                                  ),
                                );
                              },
                            )
                                : const Icon(
                              Icons.person,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            data['displayName'] ?? 'Corredor',
                            style: const TextStyle(
                              color: Colors.white,
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
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 16, color: Colors.deepOrange),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            data['city'] ?? '---',
                            style: const TextStyle(color: Colors.white30, fontWeight: FontWeight.w600),
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
                              backgroundColor: isFollowing ? Colors.white : const Color(0xFFFF6D00),
                              foregroundColor: isFollowing ? Colors.black : Colors.white,
                              side: isFollowing ? const BorderSide(color: Colors.black12) : BorderSide.none,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                            color: const Color(0xFFFF6D00).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFFF6D00).withOpacity(0.25)),
                          ),
                          child: IconButton(
                            splashRadius: 18,
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => ProfilePage(userId: targetUserId)),
                              );
                            },
                            icon: const Icon(Icons.info_outline, color: Color(0xFFFF6D00)),
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
  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);
  static const Color kCard = Color(0xFF12121A);

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
      ids.sort(); // opcional
      return ids;
    });
  }



  @override
  @override
  Widget build(BuildContext context) {
    final uid = widget.auth.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: StreamBuilder<List<String>>(
        stream: _myGroupIdsStream(uid),
        builder: (_, idsSnap) {
          if (!idsSnap.hasData) {
            return const Row(
              children: [
                Icon(Icons.shield_rounded, color: kOrange),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Carregando seus clãs...',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
                ),
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kOrange)),
              ],
            );
          }

          final groupIds = idsSnap.data ?? [];
          if (groupIds.isEmpty) {
            return Row(
              children: [
                const Icon(Icons.shield_rounded, color: kOrange),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Você ainda não faz parte de nenhum clã.',
                      style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800)),
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

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield_rounded, color: kOrange),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Meus Clãs',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                  ),
                  Text('${groupIds.length}',
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w900)),
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

  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: firestore.collection('groups').doc(groupId).snapshots(),
      builder: (_, gSnap) {
        final data = gSnap.data?.data() ?? {};
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

            // 🔴 “notificação”: existe algum join_request pendente?
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
                          color: kBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: kOrange.withOpacity(0.35)),
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
                                    color: kOrange.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: kOrange.withOpacity(0.25)),
                                  ),
                                  child: Icon(
                                    isPublic ? Icons.public_rounded : Icons.lock_rounded,
                                    color: kOrange,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.people_alt_rounded, size: 16, color: Colors.white38),
                                const SizedBox(width: 6),
                                Text(
                                  '$membersCount membros',
                                  style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            const Spacer(),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => GroupPage(groupId: groupId)),
                                  );
                                },
                                icon: const Icon(Icons.open_in_new_rounded),
                                label: const Text('Abrir'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(color: kOrange.withOpacity(0.4)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 🔴 Bolinha de notificação (admin/owner e tem pendente)
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
// 3️⃣ ABA "RANKING / DESAFIOS" — Rankings globais e de amigos
// + Ranking por Territórios Ativos (users.territories.activeCount)
// =============================================================

class _ChallengesTab extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  const _ChallengesTab({required this.firestore, required this.auth});

  @override
  State<_ChallengesTab> createState() => _ChallengesTabState();
}

class _ChallengesTabState extends State<_ChallengesTab> {
  String _rankingType = 'global'; // global | weekly | friends
  String _metric = 'km'; // km | xp | territories
  bool _loading = false;
  List<QueryDocumentSnapshot> _docs = [];
  int? _userPosition;

  static const Color kOrange = Color(0xFFFF7A00);
  static const Color kBg = Color(0xFF0B0B0F);
  static const Color kCard = Color(0xFF12121A);
  static const Color kStroke = Color(0x1FFFFFFF); // branco 12%

  @override
  void initState() {
    super.initState();
    _loadRanking();
  }

  Future<void> _loadRanking() async {
    setState(() => _loading = true);

    try {
      Query query;

      final me = widget.auth.currentUser?.uid;

      final bool isTerritories = _metric == 'territories';
      final String orderField = isTerritories ? 'territories.activeCount' : _metric;

      // ✅ Se for ranking por territórios: vem da coleção users (territories.activeCount)
      if (isTerritories) {
        // 🔸 Semanal não faz sentido para "territórios ativos" (é estado atual).
        // Se o usuário estiver em weekly e trocar para territórios, a gente força global.
        if (_rankingType == 'weekly') {
          _rankingType = 'global';
        }

        if (_rankingType == 'friends') {
          final followsSnap = await widget.firestore
              .collection('users')
              .doc(me)
              .collection('following')
              .get();

          final friendIds = followsSnap.docs.map((d) => d.id).toList();
          if (me != null && me.isNotEmpty) friendIds.add(me);

          query = widget.firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: friendIds.isEmpty ? ['dummy'] : friendIds)
              .orderBy(orderField, descending: true)
              .limit(50);
        } else {
          query = widget.firestore
              .collection('users')
              .orderBy(orderField, descending: true)
              .limit(50);
        }
      } else {
        // ✅ XP / KM: mantém seu leaderboard como está
        if (_rankingType == 'weekly') {
          final now = DateTime.now();
          final weekStart = DateTime(now.year, now.month, now.day - (now.weekday - 1));
          query = widget.firestore
              .collection('leaderboard_weekly')
              .where('weekStart', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart));
        } else if (_rankingType == 'friends') {
          final followsSnap = await widget.firestore
              .collection('users')
              .doc(me)
              .collection('following')
              .get();

          final friendIds = followsSnap.docs.map((d) => d.id).toList();
          if (me != null && me.isNotEmpty) friendIds.add(me);

          query = widget.firestore
              .collection('leaderboard_global')
              .where('userId', whereIn: friendIds.isEmpty ? ['dummy'] : friendIds);
        } else {
          query = widget.firestore.collection('leaderboard_global');
        }

        query = query.orderBy(orderField, descending: true).limit(50);
      }

      final snap = await query.get();
      final docs = snap.docs;

      // ✅ posição do usuário:
      // - no users: doc.id é o uid
      // - no leaderboard: tem userId
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
      setState(() => _loading = false);
    }
  }

  void _changeRanking(String type) {
    // ✅ Se estiver em "territories", não deixa ir para weekly
    if (_metric == 'territories' && type == 'weekly') {
      type = 'global';
    }
    setState(() => _rankingType = type);
    _loadRanking();
  }

  void _changeMetric(String metric) {
    setState(() => _metric = metric);

    // ✅ Territórios ativos não é semanal -> força global
    if (metric == 'territories' && _rankingType == 'weekly') {
      setState(() => _rankingType = 'global');
    }

    _loadRanking();
  }

  @override
  Widget build(BuildContext context) {
    final bool isTerritories = _metric == 'territories';

    return Container(
      color: kBg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          const Text(
            '🏆 Rankings',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 10),

          // 🔘 Seletores (dark)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ToggleChip(
                label: '🌍 Global',
                active: _rankingType == 'global',
                onTap: () => _changeRanking('global'),
                activeColor: kOrange,
                inactiveBg: kCard,
                inactiveBorder: Colors.white12,
                inactiveText: Colors.white70,
              ),
              // ✅ Semanal fica desabilitado se métrica for territórios
              Opacity(
                opacity: isTerritories ? 0.45 : 1,
                child: IgnorePointer(
                  ignoring: isTerritories,
                  child: _ToggleChip(
                    label: '🗓️ Semanal',
                    active: _rankingType == 'weekly',
                    onTap: () => _changeRanking('weekly'),
                    activeColor: kOrange,
                    inactiveBg: kCard,
                    inactiveBorder: Colors.white12,
                    inactiveText: Colors.white70,
                  ),
                ),
              ),
              _ToggleChip(
                label: '👥 Amigos',
                active: _rankingType == 'friends',
                onTap: () => _changeRanking('friends'),
                activeColor: kOrange,
                inactiveBg: kCard,
                inactiveBorder: Colors.white12,
                inactiveText: Colors.white70,
              ),
            ],
          ),

          if (isTerritories) ...[
            const SizedBox(height: 8),
            Text(
              '🗺️ Territórios ativos = territórios que ainda são seus agora.',
              style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700, fontSize: 12),
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
                activeColor: kOrange,
                inactiveBg: kCard,
                inactiveBorder: Colors.white12,
                inactiveText: Colors.white70,
              ),
              const SizedBox(width: 8),
              _ToggleChip(
                label: '🏃 KM',
                active: _metric == 'km',
                onTap: () => _changeMetric('km'),
                activeColor: kOrange,
                inactiveBg: kCard,
                inactiveBorder: Colors.white12,
                inactiveText: Colors.white70,
              ),
              const SizedBox(width: 8),
              _ToggleChip(
                label: '🗺️ Territórios',
                active: _metric == 'territories',
                onTap: () => _changeMetric('territories'),
                activeColor: kOrange,
                inactiveBg: kCard,
                inactiveBorder: Colors.white12,
                inactiveText: Colors.white70,
              ),
            ],
          ),

          const SizedBox(height: 20),

          _loading
              ? const Center(child: CircularProgressIndicator(color: kOrange))
              : _docs.isEmpty
              ? const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: Text(
                'Nenhum dado encontrado neste ranking.',
                style: TextStyle(
                  color: Colors.white60,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
              : Column(
            children: [
              // 👑 pódio
              _PodiumTop3(
                docs: _docs,
                metric: _metric,
              ),
              const SizedBox(height: 12),

              // 🧱 lista (dark card)
              Container(
                decoration: BoxDecoration(
                  color: kCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
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
                          final data = _docs[i].data() as Map<String, dynamic>;

                          // ✅ nome: leaderboard usa displayName; users usa username/displayName
                          final displayName = (data['displayName'] ??
                              data['username'] ??
                              'Runner')
                              .toString();

                          // ✅ valor por métrica
                          final value = _metric == 'xp'
                              ? '${data['xp'] ?? 0} XP'
                              : _metric == 'territories'
                              ? '🗺️ ${(data['territories']?['activeCount'] ?? 0)}'
                              : '${((data['km'] ?? 0) as num).toDouble().toStringAsFixed(2)} km';

                          return _LeaderTile(
                            position: i + 1,
                            name: displayName,
                            value: value,
                            textColor: Colors.white,
                            subTextColor: Colors.white70,
                          );
                        }),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // 🟠 sua posição (dark)
              if (_userPosition != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kOrange.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kOrange.withOpacity(0.35)),
                  ),
                  child: Center(
                    child: Text(
                      '🏁 Você está em $_userPositionº lugar '
                          '${_rankingType == 'weekly'
                          ? 'nesta semana!'
                          : _rankingType == 'friends'
                          ? 'entre seus amigos!'
                          : 'no global!'}',
                      style: const TextStyle(
                        color: Colors.white,
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

  final Color activeColor;
  final Color inactiveBg;
  final Color inactiveBorder;
  final Color inactiveText;

  const _ToggleChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.activeColor = const Color(0xFFFF7A00),
    this.inactiveBg = const Color(0xFF12121A),
    this.inactiveBorder = Colors.white12,
    this.inactiveText = Colors.white70,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active ? activeColor : inactiveBg;
    final border = active ? activeColor.withOpacity(0.9) : inactiveBorder;
    final txt = active ? Colors.black : inactiveText;

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

  final Color textColor;
  final Color subTextColor;

  const _LeaderTile({
    required this.position,
    required this.name,
    required this.value,
    this.textColor = Colors.white,
    this.subTextColor = Colors.white70,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.white10,
        child: Text(
          '$position',
          style: TextStyle(color: textColor, fontWeight: FontWeight.w900),
        ),
      ),
      title: Text(
        name,
        style: TextStyle(color: textColor, fontWeight: FontWeight.w800),
      ),
      trailing: Text(
        value,
        style: TextStyle(color: subTextColor, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _PodiumTop3 extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final String metric; // 'xp' | 'km' | 'territories'
  const _PodiumTop3({required this.docs, required this.metric});

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) return const SizedBox.shrink();

    String fmt(int i) {
      final m = docs[i].data() as Map<String, dynamic>;

      if (metric == 'xp') return '${m['xp'] ?? 0} XP';

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
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
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
                  color: const Color(0xFFFF6D00).withOpacity(0.12),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFF6D00).withOpacity(0.25)),
                ),
                child: Text(
                  '$pos',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFFF6D00),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isAvailable ? name(index) : '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                isAvailable ? fmt(index) : '',
                style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    }

    // Ordem visual: 2º | 1º | 3º
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
  static const Color kOrange = Color(0xFFFF7A00);

  @override
  Widget build(BuildContext context) {
    final t = type.toLowerCase();
    final label = t == 'oficial'
        ? 'OFICIAL'
        : t == 'grupo'
        ? 'GRUPO'
        : 'GERAL';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: kOrange.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFFF6D00).withOpacity(0.25),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: kOrange,
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}





