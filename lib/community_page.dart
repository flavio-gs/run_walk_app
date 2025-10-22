import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:run_walk_app/profile_page.dart';

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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        // 🔧 Garante respiro vertical suficiente
        toolbarHeight: 64,
        title: Text(
          'Comunidade',
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _SearchBar(
                  onChanged: (v) => _searchQuery.value = v,
                ),
              ),
              TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFFFF6D00),
                labelColor: Colors.black,
                unselectedLabelColor: Colors.black54,
                tabs: const [
                  Tab(text: 'Descobrir'),
                  Tab(text: 'Mapa'),
                  Tab(text: 'Ranking'),
                ],
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
          _MapTab(
            firestore: _firestore,
            auth: _auth,
            searchQuery: _searchQuery,
          ),
          _ChallengesTab(firestore: _firestore, auth: _auth),
        ],
      ),
    );
  }
}

/// 🔍 Barra de busca simples e limpa
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: Colors.black54),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: widget.onChanged, // 🔥 mantém o vínculo com _searchQuery
                style: const TextStyle(color: Colors.black87),
                decoration: const InputDecoration(
                  hintText: 'Digite @ para usuário ou # para grupo...',
                  hintStyle: TextStyle(color: Colors.black45),
                  border: InputBorder.none,
                ),
              ),
            ),
            if (_controller.text.isNotEmpty)
              IconButton(
                onPressed: () {
                  _controller.clear();
                  widget.onChanged?.call('');
                },
                icon: const Icon(Icons.close, color: Colors.black45),
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
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                isUserSearch ? 'Resultados da busca' : 'Corredores próximos',
                style: const TextStyle(
                  color: Colors.black,
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
    return SizedBox(
      height: 180,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemCount: docs.length,
        itemBuilder: (_, i) {
          final data = docs[i].data() as Map<String, dynamic>;
          final targetUserId = (data['uid'] ?? data['userId'] ?? docs[i].id) as String? ?? '';

          return Container(
            width: 220,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const CircleAvatar(
                    backgroundColor: Colors.black12,
                    child: Icon(Icons.person, color: Colors.black87),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      data['displayName'] ?? 'Corredor',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  '@${data['username'] ?? 'sem_username'}',
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  'Cidade: ${data['city'] ?? '---'}',
                  style: const TextStyle(color: Colors.black54),
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await FirebaseFirestore.instance
                              .collection('follows')
                              .doc('${widget.auth.currentUser?.uid}_$targetUserId')
                              .set({
                            'followerId': widget.auth.currentUser?.uid,
                            'followingId': targetUserId,
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Agora você segue este corredor 🎉')),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Seguir'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfilePage(userId: targetUserId),
                          ),
                        );
                      },
                      icon: const Icon(Icons.info_outline, color: Color(0xFFFF6D00)),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// =============================================================
// 2️⃣ ABA "MAPA" — corredores e rotas populares
// =============================================================
class _MapTab extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final ValueNotifier<String> searchQuery;

  const _MapTab({
    required this.firestore,
    required this.auth,
    required this.searchQuery,
    Key? key,
  }) : super(key: key);

  @override
  State<_MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<_MapTab> {
  GoogleMapController? _mapController;
  LatLng _center = const LatLng(-22.978, -43.365);
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  bool _loadingLocation = false;

  @override
  void initState() {
    super.initState();
    _ensureLocationPermission();
    _loadRunnersAndRoutes();
  }

  Future<void> _ensureLocationPermission() async {
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      await Geolocator.requestPermission();
    }
  }

  Future<void> _loadRunnersAndRoutes() async {
    try {
      final routesSnap = await widget.firestore.collection('routes').limit(10).get();
      final polylines = <Polyline>{};

      for (final r in routesSnap.docs) {
        final data = r.data();
        final points = (data['points'] as List?)
            ?.whereType<GeoPoint>()
            .map((gp) => LatLng(gp.latitude, gp.longitude))
            .toList();

        if (points == null || points.isEmpty) continue;
        polylines.add(
          Polyline(
            polylineId: PolylineId(r.id),
            points: points,
            width: 3,
            color: const Color(0xFFFF6D00),
          ),
        );
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final current = LatLng(pos.latitude, pos.longitude);

      final runnersSnap = await widget.firestore
          .collection('users')
          .where('isOnline', isEqualTo: true)
          .get();

      final currentUserId = widget.auth.currentUser?.uid;

      final markers = <Marker>{};
      for (final d in runnersSnap.docs) {
        final m = d.data();
        final uid = (m['uid'] ?? m['userId'])?.toString();
        if (uid == currentUserId) continue;

        final lat = (m['lat'] ?? 0).toDouble();
        final lng = (m['lng'] ?? 0).toDouble();

        markers.add(
          Marker(
            markerId: MarkerId('runner_${d.id}'),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(
              title: m['displayName'] ?? 'Corredor',
              snippet: m['pace'] ?? '',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
            onTap: () => _openRunnerSheet(m),
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _center = current;
        _markers.clear();
        _markers.addAll(markers);
        _polylines.clear();
        _polylines.addAll(polylines);
      });
    } catch (e) {
      debugPrint("Erro ao carregar mapa: $e");
    }
  }

  void _openRunnerSheet(Map<String, dynamic> runner) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.black12,
                    child: Icon(Icons.person, color: Colors.black87),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      runner['displayName'] ?? 'Corredor',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black54),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Ritmo: ${runner['pace'] ?? '--'}',
                style: const TextStyle(color: Colors.black87),
              ),
              const SizedBox(height: 6),
              Text(
                'Cidade: ${runner['city'] ?? '---'}',
                style: const TextStyle(color: Colors.black87),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final targetUserId =
                        (runner['uid'] ?? runner['userId'] ?? '') as String? ?? '';
                    if (targetUserId.isEmpty) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfilePage(userId: targetUserId),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Ver perfil'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _centerOnUser() async {
    try {
      setState(() => _loadingLocation = true);
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final here = LatLng(pos.latitude, pos.longitude);
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(here, 14));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível obter sua localização')),
      );
    } finally {
      setState(() => _loadingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: _center, zoom: 13.2),
          onMapCreated: (c) => _mapController = c,
          markers: _markers,
          polylines: _polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            children: [
              FloatingActionButton(
                heroTag: 'center_on_me',
                backgroundColor: Colors.black,
                onPressed: _loadingLocation ? null : _centerOnUser,
                child: _loadingLocation
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.my_location, color: Colors.white),
              ),
              const SizedBox(height: 10),
              FloatingActionButton.extended(
                heroTag: 'reload',
                backgroundColor: const Color(0xFFFF6D00),
                onPressed: _loadRunnersAndRoutes,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text(
                  'Atualizar',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================
// 3️⃣ ABA "RANKING / DESAFIOS" — Rankings globais e de amigos
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
  String _metric = 'km'; // km | xp
  bool _loading = false;
  List<QueryDocumentSnapshot> _docs = [];
  int? _userPosition;

  @override
  void initState() {
    super.initState();
    _loadRanking();
  }

  Future<void> _loadRanking() async {
    setState(() => _loading = true);

    try {
      Query query;

      if (_rankingType == 'weekly') {
        final now = DateTime.now();
        final weekStart = DateTime(now.year, now.month, now.day - (now.weekday - 1));
        query = widget.firestore
            .collection('leaderboard_weekly')
            .where('weekStart', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart));
      } else if (_rankingType == 'friends') {
        final me = widget.auth.currentUser?.uid;
        final followsSnap = await widget.firestore
            .collection('users')
            .doc(me)
            .collection('following')
            .get();

        final friendIds = followsSnap.docs.map((d) => d.id).toList();
        friendIds.add(me ?? '');
        query = widget.firestore
            .collection('leaderboard_global')
            .where('userId', whereIn: friendIds.isEmpty ? ['dummy'] : friendIds);
      } else {
        query = widget.firestore.collection('leaderboard_global');
      }

      query = query.orderBy(_metric, descending: true).limit(50);
      final snap = await query.get();
      final docs = snap.docs;
      final me = widget.auth.currentUser?.uid;
      final index = docs.indexWhere((d) => (d.data() as Map)['userId'] == me);
      final pos = index != -1 ? index + 1 : null;

      setState(() {
        _docs = docs;
        _userPosition = pos;
      });
    } catch (e) {
      debugPrint('Erro ao carregar ranking: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _changeRanking(String type) {
    setState(() => _rankingType = type);
    _loadRanking();
  }

  void _changeMetric(String metric) {
    setState(() => _metric = metric);
    _loadRanking();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          const Text(
            '🏆 Rankings',
            style: TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),

          // 🔘 Seletores
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ToggleChip(label: '🌍 Global', active: _rankingType == 'global', onTap: () => _changeRanking('global')),
              _ToggleChip(label: '🗓️ Semanal', active: _rankingType == 'weekly', onTap: () => _changeRanking('weekly')),
              _ToggleChip(label: '👥 Amigos', active: _rankingType == 'friends', onTap: () => _changeRanking('friends')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ToggleChip(label: '⚡ XP', active: _metric == 'xp', onTap: () => _changeMetric('xp')),
              const SizedBox(width: 8),
              _ToggleChip(label: '🏃 KM', active: _metric == 'km', onTap: () => _changeMetric('km')),
            ],
          ),

          const SizedBox(height: 20),

          _loading
              ? const Center(child: CircularProgressIndicator(color: Colors.black))
              : _docs.isEmpty
              ? const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: Text(
                'Nenhum dado encontrado neste ranking.',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          )
              : Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < _docs.length; i++)
                      _LeaderTile(
                        position: i + 1,
                        name: (_docs[i].data() as Map<String, dynamic>)['displayName'] ?? 'Runner',
                        value: _metric == 'xp'
                            ? '${(_docs[i].data() as Map<String, dynamic>)['xp'] ?? 0} XP'
                            : '${((_docs[i].data() as Map<String, dynamic>)['km'] ?? 0).toStringAsFixed(2)} km',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_userPosition != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6D00).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      '🏁 Você está em $_userPositionº lugar ${_rankingType == 'weekly' ? 'nesta semana!' : _rankingType == 'friends' ? 'entre seus amigos!' : 'no global!'}',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
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
  const _ToggleChip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFFF6D00) : Colors.grey[200],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
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
  const _LeaderTile({required this.position, required this.name, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.grey[300],
        child: Text(
          '$position',
          style: const TextStyle(color: Colors.black),
        ),
      ),
      title: Text(
        name,
        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
      ),
      trailing: Text(
        value,
        style: const TextStyle(color: Colors.black54),
      ),
    );
  }
}


