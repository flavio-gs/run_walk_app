// community_page.dart — versão COMPLETA com Firestore + Geolocator + UI glass
// Requisitos no pubspec:
//  cloud_firestore, firebase_auth, geolocator, google_maps_flutter

import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:run_walk_app/profile_page.dart';

// Raio em graus aproximados (1 deg ~ 111km). Para ~3km: 3 / 111 ≈ 0.027
const double _nearbyDelta = 0.2; // ~22 km

class _LatLngBox {
  final double minLat, maxLat, minLng, maxLng;
  const _LatLngBox({required this.minLat, required this.maxLat, required this.minLng, required this.maxLng});
}

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage>
    with SingleTickerProviderStateMixin {
  bool _isFollowing = false;
  bool _isLoadingFollow = false;
  late final TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Busca global compartilhada entre abas
  final ValueNotifier<String> _searchQuery = ValueNotifier('');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }


  @override
  void dispose() {
    _tabController.dispose();
    _searchQuery.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF0B1020)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Builder(
        // 👇 rootContext estável do Scaffold principal
        builder: (rootContext) => Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.transparent,
            title: const _NeonTitle(text: 'Comunidade'),
            centerTitle: true,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(112),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _SearchBar(onChanged: (v) => _searchQuery.value = v),
                  const SizedBox(height: 8),
                  _GlassContainer(
                    child: TabBar(
                      controller: _tabController,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: const BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        gradient: LinearGradient(
                          colors: [Color(0xFF4A90E2), Color(0xFF007AFF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white70,
                      tabs: const [
                        Tab(text: 'Descobrir'),
                        Tab(text: 'Mapa'),
                        Tab(text: 'Desafios'),
                        Tab(text: 'Chats'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
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
                messengerContext: rootContext, // 👈 garante SnackBars estáveis
              ),
              _MapTab(
                firestore: _firestore,
                auth: _auth,
                searchQuery: _searchQuery,
                rootContext: rootContext, // 👈 usado para SnackBars
              ),
              _ChallengesTab(firestore: _firestore),
              _ChatsTab(firestore: _firestore, auth: _auth),
            ],
          ),
          floatingActionButton: const _InviteFab(),
        ),
      ),
    );
  }
}

// =============================================================
// AÇÕES GERAIS DE COMUNIDADE (seguir / convidar)
// =============================================================
class CommunityActions {
  static Future<void> followRunner(
      FirebaseFirestore firestore,
      FirebaseAuth auth,
      BuildContext messengerContext, // 👈 usar SEMPRE o rootContext
      String targetUserId,
      ) async {
    try {
      final me = auth.currentUser?.uid;
      if (me == null || targetUserId.isEmpty) return;

      final id = '${me}_$targetUserId';
      await firestore.collection('follows').doc(id).set({
        'followerId': me,
        'followingId': targetUserId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.maybeOf(messengerContext)?.showSnackBar(
        const SnackBar(content: Text('Agora você segue este corredor 🎉')),
      );
    } catch (e) {
      ScaffoldMessenger.maybeOf(messengerContext)?.showSnackBar(
        SnackBar(content: Text('Erro ao seguir: $e')),
      );
    }
  }

  static Future<void> inviteToRun(
      FirebaseFirestore firestore,
      FirebaseAuth auth,
      BuildContext messengerContext, // 👈 usar SEMPRE o rootContext
      String targetUserId,
      ) async {
    try {
      final me = auth.currentUser?.uid;
      if (me == null || targetUserId.isEmpty) return;

      await firestore.collection('invites').add({
        'from': me,
        'to': targetUserId,
        'type': 'run_invite',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.maybeOf(messengerContext)?.showSnackBar(
        const SnackBar(content: Text('Convite enviado ✅')),
      );
    } catch (e) {
      ScaffoldMessenger.maybeOf(messengerContext)?.showSnackBar(
        SnackBar(content: Text('Erro ao convidar: $e')),
      );
    }
  }
}

// =============================================================
// 1) DESCOBRIR — Busca, sugestões próximas, grupos, salas temáticas
// =============================================================
class _DiscoverTab extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final ValueNotifier<String> searchQuery;
  final BuildContext messengerContext; // 👈 novo

  const _DiscoverTab({
    required this.firestore,
    required this.auth,
    required this.searchQuery,
    required this.messengerContext,
  });

  @override
  State<_DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<_DiscoverTab> {
  final _categories = const [
    'Trilhas', 'Noturno', 'Iniciantes', '5K', '10K', '21K', 'Maratona', 'HIIT'
  ];
  String _selectedCat = 'Trilhas';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: widget.searchQuery,
      builder: (_, query, __) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            // Chips de categorias
            _HorizontalChips(
              items: _categories,
              selected: _selectedCat,
              onSelected: (v) => setState(() => _selectedCat = v),
            ),
            const SizedBox(height: 12),

            // Sugestões perto de você (runners)
            _SectionTitle('Sugestões perto de você'),
            const SizedBox(height: 8),
            _GlassContainer(
              child: SizedBox(
                height: 134,
                child: StreamBuilder<QuerySnapshot>(
                  stream: widget.firestore
                      .collection('users')
                      .orderBy('lastActive', descending: true)
                      .limit(12)
                      .snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12.0),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final docs = snap.data!.docs;
                    final filtered = docs.where((d) {
                      final m = d.data() as Map<String, dynamic>;
                      final name = (m['displayName'] ?? '').toString().toLowerCase();
                      return query.isEmpty || name.contains(query.toLowerCase());
                    }).toList();
                    return ListView.separated(
                      padding: const EdgeInsets.all(12),
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (_, i) {
                        final data = filtered[i].data() as Map<String, dynamic>;
                        final targetUserId = (data['uid'] ?? data['userId'] ?? filtered[i].id) as String? ?? '';

                        return _RunnerCard(
                          name: data['displayName'] ?? 'Runner',
                          pace: data['pace'] ?? '--',
                          city: data['city'] ?? '',
                          onFollow: () async {
                            await CommunityActions.followRunner(
                              widget.firestore,
                              widget.auth,
                              widget.messengerContext,
                              targetUserId,
                            );
                          },
                          onInvite: () async {
                            await CommunityActions.inviteToRun(
                              widget.firestore,
                              widget.auth,
                              widget.messengerContext,
                              targetUserId,
                            );
                          },
                        );

                      },
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemCount: filtered.length,
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),
            _SectionTitle('Grupos em destaque'),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: widget.firestore
                  .collection('groups')
                  .orderBy('members', descending: true)
                  .limit(20)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                }
                final docs = snap.data!.docs.where((d) {
                  final m = d.data() as Map<String, dynamic>;
                  final name = (m['name'] ?? '').toString().toLowerCase();
                  final tag = (m['tag'] ?? '').toString();
                  final query = widget.searchQuery.value.toLowerCase();
                  final matchesQuery = query.isEmpty || name.contains(query);
                  final matchesCat = _selectedCat.isEmpty || tag == _selectedCat;
                  return matchesQuery && matchesCat;
                }).toList();

                if (docs.isEmpty) {
                  return const _EmptyState(text: 'Nenhum grupo encontrado.');
                }

                return Column(
                  children: docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: _GroupCard(
                        name: data['name'] ?? 'Grupo',
                        members: data['members'] ?? 0,
                        tag: data['tag'] ?? '',
                        onJoin: () async {
                          final user = widget.auth.currentUser;
                          if (user == null) return;
                          await widget.firestore.collection('groups').doc(doc.id).update({
                            'requests': FieldValue.arrayUnion([user.uid])
                          });
                          ScaffoldMessenger.maybeOf(widget.messengerContext)?.showSnackBar(
                            SnackBar(content: Text('Pedido enviado para "${data['name']}"')),
                          );
                        },
                      ),
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 16),
            _SectionTitle('Salas temáticas'),
            const SizedBox(height: 8),
            _GlassContainer(
              child: Column(children: const [
                _TopicTile(title: 'Desafios Semanais', members: 540),
                _TopicTile(title: 'Maratonistas RJ', members: 128),
                _TopicTile(title: 'Iniciantes — Dúvidas', members: 312),
              ]),
            ),
          ],
        );
      },
    );
  }
}

// =============================================================
// 2) MAPA — Rotas populares e corredores ativos
// =============================================================
class _MapTab extends StatefulWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final ValueNotifier<String> searchQuery;
  final BuildContext rootContext; // 👈 contexto estável do Scaffold
  const _MapTab({
    required this.firestore,
    required this.auth,
    required this.searchQuery,
    required this.rootContext,
  });

  @override
  State<_MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<_MapTab> {



  GoogleMapController? _mapController;
  LatLng _center = const LatLng(-22.978, -43.365); // Barra da Tijuca (aprox)
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  bool _loadingLocation = false;

  @override
  void initState() {
    super.initState();
    _ensureLocationPermission();
    _loadRoutesAndRunners();
  }

  Future<bool> _isFollowingUser(String targetUserId) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null || targetUserId.isEmpty) return false;
    final doc = await FirebaseFirestore.instance
        .collection('follows')
        .doc('${me}_$targetUserId')
        .get();
    return doc.exists;
  }

  Future<void> _ensureLocationPermission() async {
    LocationPermission p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
      await Geolocator.requestPermission();
    }
  }

  // 🔹 Carrega rotas + corredores
  Future<void> _loadRoutesAndRunners() async {
    final routesSnap = await widget.firestore.collection('routes').limit(10).get();
    final polylines = <Polyline>{};

    for (final r in routesSnap.docs) {
      final data = r.data();
      final points = (data['points'] as List?)?.whereType<GeoPoint>().map(
            (gp) => LatLng(gp.latitude, gp.longitude),
      ).toList();

      if (points == null || points.isEmpty) continue;
      polylines.add(Polyline(
        polylineId: PolylineId(r.id),
        points: points,
        width: 4,
        color: const Color(0xFF4A90E2),
      ));
    }

    final runnersSnap = await widget.firestore.collection('users').limit(50).get();
    final markers = runnersSnap.docs.map((d) {
      final m = d.data();
      return Marker(
        markerId: MarkerId(d.id),
        position: LatLng((m['lat'] ?? 0).toDouble(), (m['lng'] ?? 0).toDouble()),
        infoWindow: InfoWindow(title: m['displayName'] ?? 'Runner', snippet: m['pace'] ?? ''),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        onTap: () => _openRunnerSheet(m),
      );
    }).toSet();

    if (!mounted) return;
    setState(() {
      _polylines.addAll(polylines);
      _markers.addAll(markers);
    });
  }

  // 🔹 Centraliza mapa na posição atual
  Future<void> _centerOnUser() async {
    try {
      if (mounted) setState(() => _loadingLocation = true);
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: here, zoom: 14)),
      );
    } catch (e) {
      // 👇 usa SEMPRE o rootContext
      ScaffoldMessenger.maybeOf(widget.rootContext)?.showSnackBar(
        SnackBar(content: Text('Não foi possível obter sua localização: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  // 🔹 Cria bounding box para consulta
  _LatLngBox _makeBox(LatLng center, {double delta = _nearbyDelta}) {
    return _LatLngBox(
      minLat: center.latitude - delta,
      maxLat: center.latitude + delta,
      minLng: center.longitude - delta,
      maxLng: center.longitude + delta,
    );
  }

  // 🔹 Busca corredores próximos
  Future<void> _findNearbyRunners() async {
    if (!mounted) return;
    try {
      if (mounted) setState(() => _loadingLocation = true);

      // Solicita permissão
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        ScaffoldMessenger.maybeOf(widget.rootContext)?.showSnackBar(
          const SnackBar(content: Text('Permissão de localização negada')),
        );
        return;
      }

      // Pega localização atual
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      if (!mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);
      final box = _makeBox(here);

      // Busca runners dentro da bounding box
      final q = await widget.firestore
          .collection('users')
          .where('lat', isGreaterThanOrEqualTo: box.minLat)
          .where('lat', isLessThanOrEqualTo: box.maxLat)
          .get();

      final nearby = q.docs.where((d) {
        final m = d.data() as Map<String, dynamic>;
        final lng = (m['lng'] ?? 0).toDouble();
        return lng >= box.minLng && lng <= box.maxLng;
      }).toList();

      final newMarkers = nearby.map((d) {
        final m = d.data() as Map<String, dynamic>;
        final p = LatLng((m['lat'] ?? 0).toDouble(), (m['lng'] ?? 0).toDouble());
        return Marker(
          markerId: MarkerId('nearby_${d.id}'),
          position: p,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(title: m['displayName'] ?? 'Runner', snippet: m['pace'] ?? ''),
          onTap: () => _openRunnerSheet(m),
        );
      }).toSet();

      if (!mounted) return;
      setState(() {
        _markers.removeWhere((m) => m.markerId.value.startsWith('nearby_'));
        _markers.addAll(newMarkers);
      });

      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(here, 14));

      ScaffoldMessenger.maybeOf(widget.rootContext)?.showSnackBar(
        SnackBar(content: Text('${nearby.length} corredor(es) próximo(s) encontrados')),
      );
    } catch (e) {
      ScaffoldMessenger.maybeOf(widget.rootContext)?.showSnackBar(
        SnackBar(content: Text('Erro ao buscar próximos: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  // 🔹 Seguir corredor (sempre usando rootContext)
  Future<void> _followRunner(String targetUserId) async {
    try {
      final me = FirebaseAuth.instance.currentUser?.uid;
      if (me == null || targetUserId.isEmpty) return;

      final followsRef = FirebaseFirestore.instance.collection('follows');
      final id = '${me}_$targetUserId';

      // Verifica se já segue
      final doc = await followsRef.doc(id).get();
      if (doc.exists) {
        // Já segue → pode cancelar se quiser
        await followsRef.doc(id).delete();
        ScaffoldMessenger.maybeOf(widget.rootContext)?.showSnackBar(
          const SnackBar(content: Text('Você deixou de seguir este corredor.')),
        );
        return;
      }

      // Cria registro de follow
      await followsRef.doc(id).set({
        'followerId': me,
        'followingId': targetUserId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Adiciona também em subcoleções (opcional, para consultas mais rápidas)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(me)
          .collection('following')
          .doc(targetUserId)
          .set({'timestamp': FieldValue.serverTimestamp()});

      await FirebaseFirestore.instance
          .collection('users')
          .doc(targetUserId)
          .collection('followers')
          .doc(me)
          .set({'timestamp': FieldValue.serverTimestamp()});

      // Fecha sheet antes de mostrar snackbar
      if (mounted) Navigator.of(widget.rootContext).maybePop();

      ScaffoldMessenger.maybeOf(widget.rootContext)?.showSnackBar(
        const SnackBar(content: Text('Agora você segue este corredor 🎉')),
      );
    } catch (e) {
      ScaffoldMessenger.maybeOf(widget.rootContext)?.showSnackBar(
        SnackBar(content: Text('Erro ao seguir: $e')),
      );
    }
  }


  // 🔹 Enviar convite (sempre usando rootContext)
  Future<void> _inviteToRun(String targetUserId) async {
    try {
      final me = FirebaseAuth.instance.currentUser?.uid;
      if (me == null || targetUserId.isEmpty) return;

      await widget.firestore.collection('invites').add({
        'from': me,
        'to': targetUserId,
        'type': 'run_invite',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) Navigator.of(widget.rootContext).maybePop();

      ScaffoldMessenger.maybeOf(widget.rootContext)?.showSnackBar(
        const SnackBar(content: Text('Convite enviado ✅')),
      );
    } catch (e) {
      ScaffoldMessenger.maybeOf(widget.rootContext)?.showSnackBar(
        SnackBar(content: Text('Erro ao convidar: $e')),
      );
    }
  }

  // 🔹 Bottom sheet com perfil do corredor
  void _openRunnerSheet(Map<String, dynamic> runner) {
    final String targetId = (runner['uid'] ?? runner['userId'] ?? '') as String? ?? '';
    final Future<bool> followFuture = _isFollowingUser(targetId);

    showModalBottomSheet(
      context: widget.rootContext,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        bool isLoading = false;
        bool isFollowingCached = false; // cache local do estado para o botão

        return _GlassContainer(
          borderRadius: 22,
          padding: const EdgeInsets.all(16),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return FutureBuilder<bool>(
                future: followFuture,
                builder: (context, snap) {
                  final isFollowing = snap.data ?? false;
                  // guarda um cache para evitar flicker após o primeiro load
                  if (snap.connectionState == ConnectionState.done) {
                    isFollowingCached = isFollowing;
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const CircleAvatar(child: Icon(Icons.person)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            runner['displayName'] ?? runner['name'] ?? 'Usuário',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: targetId.isEmpty || isLoading || snap.connectionState != ConnectionState.done
                              ? null
                              : () async {
                            setModalState(() => isLoading = true);
                            await _followRunner(targetId); // já alterna seguir/desseguir
                            setModalState(() {
                              isFollowingCached = !isFollowingCached;
                              isLoading = false;
                            });
                          },
                          style: _primaryBtn,
                          icon: isLoading
                              ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                              : Icon(
                            isFollowingCached ? Icons.check : Icons.person_add_alt_1,
                            color: Colors.white,
                          ),
                          label: Text(
                            isFollowingCached ? 'Seguindo' : 'Seguir',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        const Icon(Icons.speed, color: Colors.white70, size: 18),
                        const SizedBox(width: 6),
                        Text('Ritmo: ${runner['pace'] ?? '--'}', style: const TextStyle(color: Colors.white70)),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.place, color: Colors.white70, size: 18),
                        const SizedBox(width: 6),
                        Text(runner['city'] ?? 'Local não informado', style: const TextStyle(color: Colors.white70)),
                      ]),
                      const SizedBox(height: 14),
                      Row(children: [
                        OutlinedButton.icon(
                          onPressed: targetId.isEmpty
                              ? null
                              : () => _inviteToRun(targetId),
                          style: _outlineBtn,
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Convidar p/ correr'),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            if (targetId.isEmpty) return;
                            Navigator.of(context).push(
                              PageRouteBuilder(
                                pageBuilder: (context, animation, secondaryAnimation) =>
                                    ProfilePage(userId: targetId),
                                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                  final curved = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
                                  return FadeTransition(opacity: curved, child: child);
                                },
                              ),
                            );
                          },
                          style: _outlineBtn,
                          icon: const Icon(Icons.info_outline),
                          label: const Text('Ver perfil'),
                        ),
                      ]),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }


  // 🔹 UI principal
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      GoogleMap(
        initialCameraPosition: CameraPosition(target: _center, zoom: 13.2),
        onMapCreated: (c) => _mapController = c,
        markers: _markers,
        polylines: _polylines,
        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        compassEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
      ),
      Positioned(
        left: 16,
        bottom: 16,
        child: Column(children: [
          FloatingActionButton(
            heroTag: 'center_on_me',
            backgroundColor: const Color(0xFF007AFF),
            onPressed: _loadingLocation ? null : _centerOnUser,
            child: _loadingLocation
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.my_location, color: Colors.white),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'find_nearby',
            backgroundColor: const Color(0xFF4A90E2),
            onPressed: _findNearbyRunners,
            icon: const Icon(Icons.radar),
            label: const Text('Encontrar próximos'),
          ),
        ]),
      ),
      Positioned(
        left: 16,
        right: 16,
        top: 12,
        child: _GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: const [
            Icon(Icons.route, color: Colors.white70),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Rotas sugeridas: Orla da Barra, Bosque da Barra',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// =============================================================
// 3) DESAFIOS — Equipes, leaderboard, recompensas e conquistas
// =============================================================
class _ChallengesTab extends StatelessWidget {
  final FirebaseFirestore firestore;
  const _ChallengesTab({required this.firestore});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        _SectionTitle('Desafio da Semana'),
        const SizedBox(height: 8),
        StreamBuilder<DocumentSnapshot>(
          stream: firestore.collection('challenges').doc('weekly').snapshots(),
          builder: (context, snap) {
            final data = (snap.data?.data() as Map<String, dynamic>?) ?? {};
            final blue = (data['blueProgress'] ?? 0.0).toDouble();
            final red = (data['redProgress'] ?? 0.0).toDouble();
            return _TeamBattleCard(
              title: data['title'] ?? 'Equipe Azul vs Equipe Vermelha',
              goal: data['goal'] ?? 'Quem soma mais km até domingo',
              blueProgress: blue.clamp(0, 1),
              redProgress: red.clamp(0, 1),
              onJoinBlue: () {},
              onCreateChallenge: () {},
            );
          },
        ),
        const SizedBox(height: 16),
        _SectionTitle('Leaderboard (Individual)'),
        const SizedBox(height: 8),
        _GlassContainer(
          child: StreamBuilder<QuerySnapshot>(
            stream: firestore
                .collection('leaderboard')
                .orderBy('km', descending: true)
                .limit(10)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: LinearProgressIndicator(minHeight: 2),
                );
              }
              final docs = snap.data!.docs;
              return Column(
                children: [
                  for (int i = 0; i < docs.length; i++)
                    _LeaderTile(
                      position: i + 1,
                      name: (docs[i].data() as Map<String, dynamic>)['displayName'] ?? 'Runner',
                      value: '${((docs[i].data() as Map<String, dynamic>)['km'] ?? 0).toString()} km',
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        _SectionTitle('Recompensas'),
        const SizedBox(height: 8),
        _GlassContainer(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                _RewardBadge(icon: Icons.emoji_events, label: 'Troféu Semana'),
                _RewardBadge(icon: Icons.monetization_on, label: '100 moedas'),
                _RewardBadge(icon: Icons.directions_run, label: 'Avatar 3D'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _SectionTitle('Conquistas recentes'),
        const SizedBox(height: 8),
        _GlassContainer(
          child: StreamBuilder<QuerySnapshot>(
            stream: firestore
                .collection('achievements')
                .orderBy('timestamp', descending: true)
                .limit(10)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const SizedBox(
                  height: 56,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final docs = snap.data!.docs;
              return Column(
                children: docs.map((d) {
                  final m = d.data() as Map<String, dynamic>;
                  return _AchievementTile(user: m['user'] ?? 'Runner', text: m['text'] ?? '—');
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}

// =============================================================
// 4) CHATS — Salas e mensagens em tempo real
// =============================================================
class _ChatsTab extends StatelessWidget {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  const _ChatsTab({required this.firestore, required this.auth});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      children: [
        _SectionTitle('Salas disponíveis'),
        const SizedBox(height: 8),
        _GlassContainer(
          child: StreamBuilder<QuerySnapshot>(
            stream: firestore.collection('chatRooms').orderBy('updatedAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
              }
              final rooms = snapshot.data!.docs;
              if (rooms.isEmpty) return const _EmptyState(text: 'Nenhuma sala ainda.');

              return Column(children: [
                for (final r in rooms)
                  _ChatRoomTile(
                    title: (r.data() as Map<String, dynamic>)['name'] ?? 'Chat',
                    members: ((r.data() as Map<String, dynamic>)['members'] as List?)?.length ?? 0,
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ChatRoomPage(
                          roomId: r.id,
                          firestore: firestore,
                          auth: auth,
                        ),
                      ));
                    },
                  ),
              ]);
            },
          ),
        ),
      ],
    );
  }
}

class ChatRoomPage extends StatefulWidget {
  final String roomId;
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  const ChatRoomPage({required this.roomId, required this.firestore, required this.auth});

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(title: const Text('Chat'), backgroundColor: Colors.transparent, elevation: 0),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: widget.firestore
                  .collection('chatRooms')
                  .doc(widget.roomId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final messages = snapshot.data!.docs;
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final m = messages[index].data() as Map<String, dynamic>;
                    final isMe = m['userId'] == widget.auth.currentUser?.uid;
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: _GlassContainer(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          color: isMe ? Colors.blue.withOpacity(0.16) : null,
                          child: Column(
                            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Text(m['author'] ?? (isMe ? 'Você' : '—'),
                                  style: const TextStyle(fontSize: 12, color: Colors.white54)),
                              const SizedBox(height: 4),
                              Text(m['text'] ?? '', style: const TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(children: [
                Expanded(
                  child: _GlassContainer(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Escreva uma mensagem…',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _sendMessage,
                  style: _primaryBtn,
                  child: const Icon(Icons.send),
                )
              ]),
            ),
          )
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final txt = _controller.text.trim();
    if (txt.isEmpty) return;
    final user = widget.auth.currentUser;
    await widget.firestore
        .collection('chatRooms')
        .doc(widget.roomId)
        .collection('messages')
        .add({
      'text': txt,
      'author': user?.displayName ?? 'Você',
      'userId': user?.uid,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await widget.firestore.collection('chatRooms').doc(widget.roomId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _controller.clear();
  }
}

// =============================================================
// FAB — Convites (link, QR, criar grupo/desafio)
// =============================================================
class _InviteFab extends StatelessWidget {
  const _InviteFab();
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      backgroundColor: const Color(0xFF007AFF),
      onPressed: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => _GlassContainer(
            borderRadius: 24,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Convidar para correr',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InviteBtn(icon: Icons.share, label: 'Compartilhar link', onTap: () {}),
                    _InviteBtn(icon: Icons.qr_code, label: 'Gerar QR Code', onTap: () {}),
                    _InviteBtn(icon: Icons.group_add, label: 'Criar grupo', onTap: () {}),
                    _InviteBtn(icon: Icons.emoji_events_outlined, label: 'Criar desafio', onTap: () {}),
                  ],
                )
              ],
            ),
          ),
        );
      },
      icon: const Icon(Icons.person_add_alt_1),
      label: const Text('Convidar'),
    );
  }
}

class _InviteBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _InviteBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: _GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white70),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

// =============================================================
// WIDGETS BÁSICOS / VISUAIS
// =============================================================
class _NeonTitle extends StatelessWidget {
  final String text;
  const _NeonTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0xFF4A90E2), Color(0xFF007AFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: Colors.white,
        ),
      ),
    );
  }
}

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
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: _GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.search, color: Colors.white70),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: widget.onChanged,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Buscar usuários, grupos ou rotas…',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton(
              onPressed: () {
                _controller.clear();
                widget.onChanged?.call('');
              },
              icon: const Icon(Icons.close, color: Colors.white54),
            )
          ],
        ),
      ),
    );
  }
}

class _HorizontalChips extends StatelessWidget {
  final List<String> items;
  final String selected;
  final ValueChanged<String> onSelected;
  const _HorizontalChips({required this.items, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemBuilder: (_, i) {
          final item = items[i];
          final active = item == selected;
          return ChoiceChip(
            selected: active,
            label: Text(item),
            labelStyle: TextStyle(
              color: active ? Colors.white : Colors.black,
              fontWeight: FontWeight.w600,
            ),
            backgroundColor: Colors.black.withOpacity(0.06),
            selectedColor: const Color(0xFF4A90E2).withOpacity(0.6),
            onSelected: (_) => onSelected(item),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: items.length,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 16,
          letterSpacing: .3,
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final String name;
  final int members;
  final String tag;
  final VoidCallback onJoin;
  const _GroupCard({required this.name, required this.members, required this.tag, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return _GlassContainer(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const CircleAvatar(radius: 24, child: Icon(Icons.group)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text('$members membros • $tag', style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: onJoin,
            style: _primaryBtn,
            icon: const Icon(Icons.how_to_reg),
            label: const Text('Entrar'),
          )
        ],
      ),
    );
  }
}

class _RunnerCard extends StatelessWidget {
  final String name;
  final String pace;
  final String city;
  final VoidCallback onFollow;
  final VoidCallback onInvite;
  const _RunnerCard({required this.name, required this.pace, required this.city, required this.onFollow, required this.onInvite});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: _GlassContainer(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              const CircleAvatar(child: Icon(Icons.person)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(city, style: const TextStyle(color: Colors.white54)),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.speed, color: Colors.white70, size: 18),
              const SizedBox(width: 6),
              Text('Ritmo: $pace', style: const TextStyle(color: Colors.white70)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              OutlinedButton.icon(onPressed: onFollow, style: _outlineBtn, icon: const Icon(Icons.person_add_alt_1), label: const Text('Seguir')),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: onInvite, style: _outlineBtn, icon: const Icon(Icons.chat_bubble_outline), label: const Text('Convidar')),
            ])
          ],
        ),
      ),
    );
  }
}

class _TopicTile extends StatelessWidget {
  final String title;
  final int members;
  const _TopicTile({required this.title, required this.members});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.forum, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text('$members membros', style: const TextStyle(color: Colors.white54)),
      trailing: ElevatedButton(onPressed: () {}, style: _primaryBtn, child: const Text('Entrar')),
    );
  }
}

class _TeamBattleCard extends StatelessWidget {
  final String title;
  final String goal;
  final double blueProgress;
  final double redProgress;
  final VoidCallback onJoinBlue;
  final VoidCallback onCreateChallenge;
  const _TeamBattleCard({
    required this.title,
    required this.goal,
    required this.blueProgress,
    required this.redProgress,
    required this.onJoinBlue,
    required this.onCreateChallenge,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassContainer(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 4),
        Text(goal, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        _progress('Equipe Azul', blueProgress, const Color(0xFF4A90E2)),
        const SizedBox(height: 10),
        _progress('Equipe Vermelha', redProgress, const Color(0xFFFF4D4F)),
        const SizedBox(height: 12),
        Row(children: [
          ElevatedButton.icon(onPressed: onJoinBlue, style: _primaryBtn, icon: const Icon(Icons.group_add), label: const Text('Entrar na Equipe Azul')),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: onCreateChallenge, style: _outlineBtn, icon: const Icon(Icons.flag_outlined), label: const Text('Criar desafio')),
        ])
      ]),
    );
  }

  Widget _progress(String label, double value, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        Text('${(value * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white70)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: LinearProgressIndicator(
          minHeight: 10,
          value: value,
          backgroundColor: Colors.white.withOpacity(0.08),
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      )
    ]);
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
      leading: CircleAvatar(backgroundColor: Colors.white10, child: Text('$position', style: const TextStyle(color: Colors.white))),
      title: Text(name, style: const TextStyle(color: Colors.white)),
      trailing: Text(value, style: const TextStyle(color: Colors.white70)),
    );
  }
}

class _RewardBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _RewardBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return _GlassContainer(
      padding: const EdgeInsets.all(10),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: Colors.white),
        const SizedBox(height: 6),
        Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    );
  }
}

class _AchievementTile extends StatelessWidget {
  final String user;
  final String text;
  const _AchievementTile({required this.user, required this.text});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person)),
      title: Text(user, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      subtitle: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }
}

class _ChatRoomTile extends StatelessWidget {
  final String title;
  final int members;
  final VoidCallback onTap;
  const _ChatRoomTile({required this.title, required this.members, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: const Icon(Icons.forum, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text('$members membros', style: const TextStyle(color: Colors.white54)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
    );
  }
}

// =============================================================
// STYLE HELPERS (botões e glass)
// =============================================================
final ButtonStyle _primaryBtn = ElevatedButton.styleFrom(
  backgroundColor: const Color(0xFF007AFF),
  foregroundColor: Colors.white,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
);

final ButtonStyle _outlineBtn = OutlinedButton.styleFrom(
  foregroundColor: Colors.white,
  side: BorderSide(color: Colors.white.withOpacity(0.25)),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
);

class _GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? blur;
  final double? opacity;
  final double borderRadius;
  final Color? color;
  const _GlassContainer({
    required this.child,
    this.padding,
    this.blur,
    this.opacity,
    this.borderRadius = 16,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final b = blur ?? 16.0;
    final o = opacity ?? 0.12;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: b, sigmaY: b),
        child: Container(
          padding: padding ?? const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (color ?? Colors.black.withOpacity(o)),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withOpacity(0.16)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4A90E2).withOpacity(0.08),
                blurRadius: 16,
                spreadRadius: 1,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// =============================================================
// ESTADO VAZIO (mensagem genérica)
// =============================================================
class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}


// =============================== END ===============================
