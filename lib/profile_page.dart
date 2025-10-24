import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:run_walk_app/followers_page.dart';
import 'package:run_walk_app/service/achievement_service.dart';
import 'package:run_walk_app/service/service/gamification_service.dart';
import 'package:run_walk_app/pro_plans_page.dart';
import 'detalhe_corrida_page.dart';
import 'model/run_model.dart';

class ProfilePage extends StatefulWidget {
  final String? userId;
  const ProfilePage({super.key, this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool loading = true;

  // Privacidade / relacionamento
  bool isPrivate = false;     // já existia, ok manter aqui
  bool isFollower = false;    // NOVO: visitante é seguidor?

  // User
  Map<String, dynamic>? userData;
  String? photoURL;
  String? coverPhotoURL;
  DateTime? memberSince;
  String? bio;

  // Social
  int followersCount = 0;
  int followingCount = 0;

  // Stats (últimos 30 dias)
  double totalDistance = 0; // km
  int totalDuration = 0; // s
  double totalCalories = 0; // kcal
  int totalPoints = 0; // total geral

  late final String _profileUserId;
  late final bool _isCurrentUserProfile;

  final Color orange = const Color(0xFFFF6D00);
  final Color lightGray = const Color(0xFFF7F7F7);

  @override
  void initState() {
    super.initState();
    _profileUserId = widget.userId ?? FirebaseAuth.instance.currentUser!.uid;
    _isCurrentUserProfile =
        _profileUserId == FirebaseAuth.instance.currentUser!.uid;
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadUserAndSocial(),
      _loadStatsLast30d(),
      _loadPoints(),
    ]);
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadUserAndSocial() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_profileUserId)
          .get();

      final data = userDoc.data() ?? {};

      // 🔒 lê isPrivate do usuário visitado
      final bool private = (data['isPrivate'] ?? false) as bool;

      // 👥 contagens
      final followersSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_profileUserId)
          .collection('followers')
          .get();

      final followingSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_profileUserId)
          .collection('following')
          .get();

      // ✅ checa se o visitante é seguidor (somente se não for o dono)
      bool visitorIsFollower = false;
      if (!_isCurrentUserProfile && currentUser != null) {
        final meAsFollowerDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_profileUserId)
            .collection('followers')
            .doc(currentUser.uid)
            .get();
        visitorIsFollower = meAsFollowerDoc.exists;
      }

      setState(() {
        userData = data;
        photoURL = data['photoURL'] ?? currentUser?.photoURL;
        coverPhotoURL = data['coverPhoto'];
        memberSince = (data['createdAt'] is Timestamp)
            ? (data['createdAt'] as Timestamp).toDate()
            : null;
        bio = (data['bio'] as String?)?.trim();
        isPrivate = private;              // <-- salva flag
        isFollower = visitorIsFollower;   // <-- salva relação

        followersCount = followersSnap.docs.length;
        followingCount = followingSnap.docs.length;
      });
    } catch (e) {
      debugPrint("Erro ao carregar usuário/social: $e");
    }
  }


  Future<void> _loadStatsLast30d() async {
    try {
      final agora = DateTime.now();
      final inicio = agora.subtract(const Duration(days: 30));

      final corridas = await FirebaseFirestore.instance
          .collection('corridas')
          .where('userId', isEqualTo: _profileUserId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(inicio))
          .get();

      double distKm = 0;
      int durS = 0;
      double cal = 0;

      for (var c in corridas.docs) {
        final data = c.data();
        distKm += ((data['distance'] as num?)?.toDouble() ?? 0.0) / 1000.0;
        durS += (data['duration'] as num?)?.toInt() ?? 0;
        cal += (data['calories'] as num?)?.toDouble() ?? 0.0;
      }

      setState(() {
        totalDistance = distKm;
        totalDuration = durS;
        totalCalories = cal;
      });
    } catch (e) {
      debugPrint("Erro ao carregar estatísticas 30d: $e");
    }
  }

  Future<void> _loadPoints() async {
    try {
      totalPoints = await GamificationService().getTotalPoints();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Erro ao carregar pontos: $e");
    }
  }

  // -------- capa: upload e salvar url
  Future<void> _changeCoverPhoto() async {
    if (!_isCurrentUserProfile) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final file = File(picked.path);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enviando nova imagem de capa...')),
    );

    try {
      final ref = FirebaseStorage.instance.ref('users/$uid/cover.jpg');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'coverPhoto': url});

      setState(() => coverPhotoURL = url);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capa atualizada com sucesso!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar imagem: $e')),
      );
    }
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return d.year.toString(); // mostra apenas o ano
  }


  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: lightGray,
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
          onRefresh: _loadAll,
          child: NestedScrollView(
            headerSliverBuilder: (context, inner) => [
              _buildHeader(),
              _buildTabBar(),
            ],
            body: TabBarView(
              physics: const BouncingScrollPhysics(),
              children: (isPrivate && !_isCurrentUserProfile && !isFollower)
              // 🔒 VISITANTE NÃO SEGUIDOR: mostra lock em todas as abas
                  ? const [
                _PrivateAccountLock(),
                _PrivateAccountLock(),
                _PrivateAccountLock(),
              ]
              // ✅ DONO OU SEGUIDOR: conteúdo normal
                  : [
                _StatsTab(
                  userId: _profileUserId,
                  isOwner: _isCurrentUserProfile,
                  userData: userData,
                  bio: bio,
                  isPrivate: isPrivate,
                  followersCount: followersCount,
                  followingCount: followingCount,
                  memberSinceText: memberSince != null
                      ? 'Membro desde ${_formatDate(memberSince)}'
                      : 'Membro desde —',
                  totalDistance30d: totalDistance,
                  totalDuration30d: totalDuration,
                  totalCalories30d: totalCalories,
                  totalPoints: totalPoints,
                  onBioUpdated: (newBio) {
                    setState(() => bio = newBio);
                  },
                  onPrivacyToggled: (v) {
                    setState(() => isPrivate = v);
                  },
                  onRefreshSocial: _loadUserAndSocial,
                ),
                const _AchievementsTab(),
                _HistoryTab(userId: _profileUserId),
              ],
            ),

          ),
        ),
      ),
    );
  }

  // -------- Header
  SliverAppBar _buildHeader() {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 260,
      backgroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              coverPhotoURL ??
                  'https://images.unsplash.com/photo-1605287449435-3a8d1be9a401?auto=format&fit=crop&w=1200&q=60',
              fit: BoxFit.cover,
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black.withOpacity(0.55), Colors.transparent],
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                ),
              ),
            ),
            if (_isCurrentUserProfile)
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                right: 16,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.edit, color: Colors.white),
                    onPressed: _changeCoverPhoto,
                    tooltip: 'Alterar imagem de capa',
                  ),
                ),
              ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    CircleAvatar(
                      radius: 45,
                      backgroundColor: Colors.white,
                      backgroundImage: (photoURL != null && photoURL!.isNotEmpty)
                          ? NetworkImage(photoURL!)
                          : null,
                      child: (photoURL == null || photoURL!.isEmpty)
                          ? const Icon(Icons.person, size: 45)
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (userData?['displayName'] as String?) ?? 'Usuário',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            (userData?['username'] != null &&
                                (userData?['username'] as String)
                                    .trim()
                                    .isNotEmpty)
                                ? "@${userData?['username']}"
                                : "Adicionar @",
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            memberSince != null
                                ? "Membro desde ${_formatDate(memberSince)}"
                                : "",
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------- TabBar
  SliverPersistentHeader _buildTabBar() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _TabBarDelegate(
        TabBar(
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          indicatorColor: orange,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Estatísticas'),
            Tab(text: 'Conquistas'),
            Tab(text: 'Histórico'),
          ],
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: Colors.white, child: tabBar);
  }

  @override
  double get maxExtent => tabBar.preferredSize.height;
  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar;
}

class _PrivateAccountLock extends StatelessWidget {
  const _PrivateAccountLock();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.lock, size: 56, color: Colors.black45),
            SizedBox(height: 16),
            Text(
              "Esta conta é privada",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              "Siga para ver corridas, estatísticas e conquistas.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}


// ---------------------- ABA ESTATÍSTICAS ----------------------
class _StatsTab extends StatefulWidget {
  final String userId;
  final bool isOwner;
  final Map<String, dynamic>? userData;
  final String? bio;
  final bool isPrivate;
  final int followersCount;
  final int followingCount;
  final String memberSinceText;

  final double totalDistance30d;
  final int totalDuration30d;
  final double totalCalories30d;
  final int totalPoints;

  final ValueChanged<String?> onBioUpdated;
  final ValueChanged<bool> onPrivacyToggled;
  final Future<void> Function() onRefreshSocial;

  const _StatsTab({
    required this.userId,
    required this.isOwner,
    required this.userData,
    required this.bio,
    required this.isPrivate,
    required this.followersCount,
    required this.followingCount,
    required this.memberSinceText,
    required this.totalDistance30d,
    required this.totalDuration30d,
    required this.totalCalories30d,
    required this.totalPoints,
    required this.onBioUpdated,
    required this.onPrivacyToggled,
    required this.onRefreshSocial,
  });

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  late String? _bio;
  late bool _isPrivate;
  late int _followers;
  late int _following;

  @override
  void initState() {
    super.initState();
    _bio = widget.bio;
    _isPrivate = widget.isPrivate;
    _followers = widget.followersCount;
    _following = widget.followingCount;
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}min';
    if (m > 0) return '${m}min';
    return '${seconds % 60}s';
  }

  Future<void> _editBio() async {
    if (!widget.isOwner) return;
    final controller = TextEditingController(text: _bio ?? '');
    final res = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar biografia'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 160,
          decoration: const InputDecoration(
            hintText: 'Escreva algo sobre você…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (res == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({'bio': res});
      setState(() => _bio = res);
      widget.onBioUpdated(res);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Biografia atualizada!')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao salvar bio: $e')));
    }
  }

  Future<void> _togglePrivacy(bool v) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({'isPrivate': v});
      setState(() => _isPrivate = v);
      widget.onPrivacyToggled(v);
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro ao atualizar privacidade: $e')));
    }
  }

  Future<void> _refreshCounts() async {
    await widget.onRefreshSocial();
    // Os novos valores virão do pai numa próxima build; para feedback imediato,
    // podemos reconsultar localmente também, se quiser.
  }

  @override
  Widget build(BuildContext context) {
    final isPro = (widget.userData?['isPro'] ?? false) as bool;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          // --------- Perfil social: Bio / Seguidores / Privacidade
          Container(
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Membro desde
                Text(
                  widget.memberSinceText,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                const SizedBox(height: 8),
                // Bio
                GestureDetector(
                  onTap: widget.isOwner ? _editBio : null,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      (_bio != null && _bio!.isNotEmpty)
                          ? _bio!
                          : (widget.isOwner
                          ? "Adicione uma biografia ao perfil"
                          : "Sem biografia"),
                      style: TextStyle(
                        color: (_bio != null && _bio!.isNotEmpty)
                            ? Colors.black87
                            : Colors.black45,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Seguidores | Seguindo
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      // 👉 ao clicar em "Seguidores"
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FollowersPage(
                              userId: widget.userId,
                              displayName: widget.userData?['displayName'] ?? 'Usuário',
                              initialTabIndex: 0, // 👈 abre na aba Seguidores
                            ),
                          ),
                        );
                      },

                      child: _chipStat("Seguidores", _followers),
                    ),
                    GestureDetector(
                      // 👉 ao clicar em "Seguindo"
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FollowersPage(
                              userId: widget.userId,
                              displayName: widget.userData?['displayName'] ?? 'Usuário',
                              initialTabIndex: 1, // 👈 abre na aba Seguindo
                            ),
                          ),
                        );
                      },

                      child: _chipStat("Seguindo", _following),
                    ),
                    IconButton(
                      onPressed: _refreshCounts,
                      icon: const Icon(Icons.refresh, size: 20),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                // Privacidade
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Conta privada',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Apenas seguidores aprovados podem ver suas atividades.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  value: _isPrivate,
                  onChanged: widget.isOwner ? _togglePrivacy : null,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // --------- Plano
          Container(
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium, color: Colors.amber, size: 38),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPro ? "Pro Runner" : "Runner Free",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17, color: Colors.black),
                      ),
                      Text(
                        isPro
                            ? "Aproveite seus benefícios exclusivos"
                            : "Desbloqueie conquistas douradas e rankings premium",
                        style: const TextStyle(color: Colors.black54, fontSize: 13, height: 1.3),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ProPlansPage()));
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6D00),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  child: const Text("VER MAIS →"),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // --------- Estatísticas (últimos 30 dias)
          GridView(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 12),
            children: [
              _StatBox(
                icon: Icons.directions_run,
                label: 'Distância (30d)',
                value: "${widget.totalDistance30d.toStringAsFixed(2)} km",
              ),
              _StatBox(
                icon: Icons.access_time,
                label: 'Tempo (30d)',
                value: _formatDuration(widget.totalDuration30d),
              ),
              _StatBox(
                icon: Icons.local_fire_department,
                label: 'Calorias (30d)',
                value: "${widget.totalCalories30d.toStringAsFixed(0)} kcal",
              ),
            ],
          ),

          const SizedBox(height: 20),

          // --------- Pontos (total geral)
          Container(
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.star, color: Color(0xFFFF6D00), size: 40),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    "Você acumulou ${widget.totalPoints} pontos",
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // --------- Logout
          if (widget.isOwner)
            ElevatedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Sair da Conta'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.red.shade700,
                minimumSize: const Size(double.infinity, 50),
                side: BorderSide(color: Colors.red.shade700, width: 1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil(
                      '/login', (Route<dynamic> route) => false);
                }
              },
            ),
          if (widget.isOwner) const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _chipStat(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7), borderRadius: BorderRadius.circular(10)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$value', style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration:
      BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xFFFF6D00)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
        ],
      ),
    );
  }
}

// ---------------------- ABA CONQUISTAS ----------------------
class _AchievementsTab extends StatefulWidget {
  const _AchievementsTab();

  @override
  State<_AchievementsTab> createState() => _AchievementsTabState();
}

class _AchievementsTabState extends State<_AchievementsTab> {
  List<Map<String, dynamic>> _achievements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAchievements();
  }

  Future<void> _loadAchievements() async {
    final list = await AchievementService().getUserAchievements();
    if (mounted) {
      setState(() {
        _achievements = list;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_achievements.isEmpty) {
      return const Center(
        child: Text('Nenhuma conquista ainda', style: TextStyle(color: Colors.black54)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _achievements.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12,
        ),
        itemBuilder: (context, i) {
          final a = _achievements[i];
          final unlocked = a['unlocked'] == true;

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: unlocked
                  ? Border.all(color: Colors.amber, width: 1.2)
                  : Border.all(color: Colors.black12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(a['icon'] ?? '🏅',
                    style: TextStyle(
                      fontSize: 30,
                      color: unlocked ? Colors.black : Colors.black38,
                    )),
                const SizedBox(height: 6),
                Text(
                  a['title'] ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: unlocked ? Colors.black87 : Colors.black45,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------- ABA HISTÓRICO ----------------------
class _HistoryTab extends StatefulWidget {
  final String userId;
  const _HistoryTab({required this.userId});

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  String? _filtroSelecionado;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filtro
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: DropdownButtonFormField<String>(
            value: _filtroSelecionado,
            decoration: InputDecoration(
              labelText: 'Filtrar por',
              labelStyle: const TextStyle(color: Colors.black54),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderSide: const BorderSide(color: Colors.black26),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            dropdownColor: Colors.white,
            items: const [
              DropdownMenuItem(value: 'hoje', child: Text('Hoje')),
              DropdownMenuItem(value: 'semana', child: Text('Últimos 7 dias')),
              DropdownMenuItem(value: 'mes', child: Text('Últimos 30 dias')),
            ],
            onChanged: (value) => setState(() => _filtroSelecionado = value),
          ),
        ),
        Expanded(child: _buildRunStream(widget.userId, _filtroSelecionado)),
      ],
    );
  }

  Widget _buildRunStream(String userId, String? filtro) {
    Query query = FirebaseFirestore.instance
        .collection('corridas')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt'); // asc

    final agora = DateTime.now();

    if (filtro == 'hoje') {
      final inicioHoje = DateTime(agora.year, agora.month, agora.day);
      query = query
          .where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(inicioHoje))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(agora));
    } else if (filtro == 'semana') {
      final inicioSemana = agora.subtract(const Duration(days: 7));
      query = query
          .where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(inicioSemana))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(agora));
    } else if (filtro == 'mes') {
      final inicioMes = agora.subtract(const Duration(days: 30));
      query = query
          .where('createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(inicioMes))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(agora));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Erro ao carregar histórico',
                style: TextStyle(color: Colors.redAccent)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6D00)));
        }

        final docs = snapshot.data!.docs;
        final corridas = <RunModel>[];
        for (final d in docs) {
          final raw = d.data() as Map<String, dynamic>;
          try {
            raw['route'] ??= (raw['path'] ?? const []);
            corridas.add(RunModel.fromMap(raw));
          } catch (_) {}
        }

        if (corridas.isEmpty) {
          return const Center(
            child:
            Text('Nenhuma corrida encontrada', style: TextStyle(color: Colors.black54)),
          );
        }

        final corridasDesc = corridas.reversed.toList();

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 1),
          itemCount: corridasDesc.length,
          itemBuilder: (context, index) {
            final corrida = corridasDesc[index];
            return _RunCard(corrida: corrida);
          },
        );
      },
    );
  }
}

class _RunCard extends StatelessWidget {
  final RunModel corrida;
  const _RunCard({required this.corrida});

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(duration.inHours)}:${two(duration.inMinutes.remainder(60))}:${two(duration.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(context,
            MaterialPageRoute(builder: (context) => DetalheCorridaPage(corrida: corrida)));
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomPaint(
                painter: _RoutePainter(corrida.route),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "${(corrida.distance / 1000).toStringAsFixed(2)} km",
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black),
            ),
            Text(
              _formatDuration(corrida.duration),
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _iconInfo(Icons.local_fire_department,
                    "${corrida.calories?.toStringAsFixed(0)} kcal"),
                _iconInfo(Icons.speed,
                    "${corrida.pace?.toStringAsFixed(2)} min/km"),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconInfo(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFF6D00), size: 16),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(
            fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<Map<String, double>> route;
  _RoutePainter(this.route);

  @override
  void paint(Canvas canvas, Size size) {
    if (route.isEmpty) return;

    final paint = Paint()
      ..color = const Color(0xFFFF6D00)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    double minLat = route.first['lat']!;
    double maxLat = route.first['lat']!;
    double minLng = route.first['lng']!;
    double maxLng = route.first['lng']!;

    for (final p in route) {
      minLat = minLat < p['lat']! ? minLat : p['lat']!;
      maxLat = maxLat > p['lat']! ? maxLat : p['lat']!;
      minLng = minLng < p['lng']! ? minLng : p['lng']!;
      maxLng = maxLng > p['lng']! ? maxLng : p['lng']!;
    }

    final latRange = maxLat - minLat == 0 ? 0.0001 : maxLat - minLat;
    final lngRange = maxLng - minLng == 0 ? 0.0001 : maxLng - minLng;

    final path = Path();
    for (int i = 0; i < route.length; i++) {
      final latNorm = (route[i]['lat']! - minLat) / latRange;
      final lngNorm = (route[i]['lng']! - minLng) / lngRange;

      final dx = lngNorm * size.width;
      final dy = size.height - (latNorm * size.height);

      if (i == 0) path.moveTo(dx, dy);
      else path.lineTo(dx, dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.route != route;
}
