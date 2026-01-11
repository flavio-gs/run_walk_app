import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:run_walk_app/followers_page.dart';
import 'package:run_walk_app/points_details_page.dart';
import 'package:run_walk_app/service/achievement_service.dart';
import 'package:run_walk_app/service/service/gamification_service.dart';
import 'package:run_walk_app/pro_plans_page.dart';
import 'package:run_walk_app/widgets/achievement_overlay.dart';
import 'detalhe_corrida_page.dart';
import 'help_page.dart';
import 'model/run_model.dart';
import 'package:run_walk_app/activity_page.dart';
import 'package:lottie/lottie.dart';
import 'package:run_walk_app/service/level_frame_manager.dart';
import 'package:run_walk_app/challenge_details_page.dart';
import 'package:run_walk_app/edit_profile_page.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:run_walk_app/widgets/follow_button.dart';
import 'package:run_walk_app/service/service/firestore_service.dart';

class ProfilePage extends StatefulWidget {
  final String? userId;
  const ProfilePage({super.key, this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  StreamSubscription<DocumentSnapshot>? _xpListener;

  bool loading = true;
  int? _lastLevelShown;
  bool _isUploadingProfilePhoto = false;
  bool _isUploadingCoverPhoto = false;

  // Dados de level e XP
  int level = 0;
  double xp = 0.0;

  // User
  Map<String, dynamic>? userData;
  String? photoURL;
  String? coverPhotoURL;
  DateTime? memberSince;
  String? bio;
  bool isPrivate = false;

  // Social
  int followersCount = 0;
  int followingCount = 0;
  bool isFollowing = false;

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
    if (mounted) setState(() => loading = true);
    await Future.wait([
      _loadUserAndSocial(),
      _loadStatsLast30d(),
      _loadPoints(),
      _checkFollowingStatus(),
    ]);

    _loadLevelAndXP();

    if (mounted) setState(() => loading = false);
  }

  Future<void> _checkFollowingStatus() async {
    if (!_isCurrentUserProfile) {
      isFollowing = await FirestoreService().isFollowing(_profileUserId);
    } else {
      isFollowing = true;
    }
  }

  void _loadLevelAndXP() {
    _xpListener?.cancel();

    FirebaseFirestore.instance
        .collection('users')
        .doc(_profileUserId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists) return;

      final data = snapshot.data() ?? {};
      final double totalXp = (data['xp'] ?? 0.0).toDouble();
      final int currentLevel = (data['level'] ?? 0).toInt();

      final double progress = (totalXp % 500) / 500;
      final double currentXp = totalXp % 500;
      final double xpToNext = 500 - currentXp;

      if (_isCurrentUserProfile) {
        if (_lastLevelShown == null) {
          _lastLevelShown = currentLevel;
        } else if (currentLevel > _lastLevelShown!) {
          _lastLevelShown = currentLevel;
          if (context.mounted) {
            showLevelUpAnimation(context, currentLevel);
          }
        }
      }

      if (mounted) {
        setState(() {
          level = currentLevel;
          xp = progress;
          userData ??= {};
          userData!['currentXp'] = currentXp;
          userData!['xpToNext'] = xpToNext;
        });
      }
    });
  }

  @override
  void dispose() {
    _xpListener?.cancel();
    super.dispose();
  }

  Future<void> _loadUserAndSocial() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_profileUserId)
          .get();

      final data = userDoc.data() ?? {};

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

      String? _nonnullOrBlankToNull(dynamic v) {
        if (v == null) return null;
        final s = v.toString().trim();
        return s.isEmpty ? null : s;
      }

      setState(() {
        userData = data;
        photoURL     = _nonnullOrBlankToNull(data['photoURL']);
        coverPhotoURL= _nonnullOrBlankToNull(data['coverPhoto']);
        memberSince = (data['createdAt'] is Timestamp)
            ? (data['createdAt'] as Timestamp).toDate()
            : null;
        bio       = _nonnullOrBlankToNull(data['bio']);
        isPrivate = (data['isPrivate'] ?? false) as bool;
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
      totalPoints = await GamificationService().getTotalPoints(userId: _profileUserId);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Erro ao carregar pontos: $e");
    }
  }

  Future<void> _changeCoverPhoto() async {
    if (!_isCurrentUserProfile) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final file = File(picked.path);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _isUploadingCoverPhoto = true);
    try {
      final ref = FirebaseStorage.instance.ref('users/$uid/cover.jpg');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('users').doc(uid).update({'coverPhoto': url});
      setState(() => coverPhotoURL = url);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Capa atualizada!')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _isUploadingCoverPhoto = false);
    }
  }

  Future<void> _changeProfilePhoto() async {
    if (!_isCurrentUserProfile) return;
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galeria'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
            ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Câmera'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await picker.pickImage(source: source, imageQuality: 90);
    if (picked == null) return;
    final file = File(picked.path);
    try {
      setState(() => _isUploadingProfilePhoto = true);
      final mainBytes = await FlutterImageCompress.compressWithFile(file.path, quality: 80, minWidth: 600, minHeight: 600);
      final thumbBytes = await FlutterImageCompress.compressWithFile(file.path, quality: 60, minWidth: 200, minHeight: 200);
      if (mainBytes == null || thumbBytes == null) throw 'Erro na compressão';
      final storage = FirebaseStorage.instance;
      final mainRef = storage.ref().child('users/$_profileUserId/photo.jpg');
      final thumbRef = storage.ref().child('users/$_profileUserId/photo_thumb.jpg');
      await mainRef.putData(mainBytes, SettableMetadata(contentType: 'image/jpeg'));
      final downloadURL = await mainRef.getDownloadURL();
      await thumbRef.putData(thumbBytes, SettableMetadata(contentType: 'image/jpeg'));
      final thumbUrl = await thumbRef.getDownloadURL();
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && currentUser.uid == _profileUserId) {
        await currentUser.updatePhotoURL(downloadURL);
        await currentUser.reload();
      }
      await FirebaseFirestore.instance.collection('users').doc(_profileUserId).set({'photoURL': downloadURL, 'photoThumbURL': thumbUrl, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      if (mounted) setState(() => photoURL = downloadURL);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _isUploadingProfilePhoto = false);
    }
  }

  String _formatDate(DateTime? d) => d == null ? '' : d.year.toString();

  @override
  Widget build(BuildContext context) {
    bool canSeeContent = !isPrivate || _isCurrentUserProfile || isFollowing;

    return DefaultTabController(
      length: canSeeContent ? 4 : 0,
      child: Scaffold(
        backgroundColor: lightGray,
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
          onRefresh: _loadAll,
          child: NestedScrollView(
            headerSliverBuilder: (context, inner) => [
              _buildHeader(),
              if (canSeeContent) _buildTabBar(),
            ],
            body: canSeeContent
                ? TabBarView(
              physics: const BouncingScrollPhysics(),
              children: [
                _StatsTab(
                  userId: _profileUserId,
                  isOwner: _isCurrentUserProfile,
                  userData: userData,
                  bio: bio,
                  isPrivate: isPrivate,
                  followersCount: followersCount,
                  followingCount: followingCount,
                  memberSinceText: memberSince != null ? "Membro desde ${_formatDate(memberSince)}" : "",
                  totalDistance30d: totalDistance,
                  totalDuration30d: totalDuration,
                  totalCalories30d: totalCalories,
                  totalPoints: totalPoints,
                  onBioUpdated: (newBio) => setState(() => bio = newBio),
                  onPrivacyToggled: (v) => setState(() => isPrivate = v),
                  onRefreshSocial: _loadUserAndSocial,
                ),
                const _AchievementsTab(),
                _HistoryTab(userId: _profileUserId),
                _ChallengesTab(userId: _profileUserId),
              ],
            )
                : _buildPrivateAccountMessage(),
          ),
        ),
      ),
    );
  }

  Widget _buildPrivateAccountMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text(
              "Esta conta é privada",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Siga este usuário para ver suas atividades, conquistas e histórico.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildHeader() {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 280,
      backgroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              coverPhotoURL ?? 'https://images.unsplash.com/photo-1605287449435-3a8d1be9a401?auto=format&fit=crop&w=1200&q=60',
              fit: BoxFit.cover,
            ),
            Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.black.withOpacity(0.55), Colors.transparent], begin: Alignment.bottomCenter, end: Alignment.center))),
            if (_isCurrentUserProfile)
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                right: 16,
                child: CircleAvatar(
                  backgroundColor: Colors.black45,
                  child: IconButton(
                    icon: _isUploadingCoverPhoto ? const SizedBox(height: 10, width: 10, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.edit, color: Colors.white),
                    onPressed: _isUploadingCoverPhoto ? null : _changeCoverPhoto,
                  ),
                ),
              ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              top: 10,
                              child: GestureDetector(
                                onTap: _isCurrentUserProfile ? _changeProfilePhoto : null,
                                child: CircleAvatar(
                                  radius: 42,
                                  backgroundColor: Colors.white,
                                  backgroundImage: (photoURL != null && photoURL!.isNotEmpty) ? NetworkImage(photoURL!) : null,
                                  child: (photoURL == null || photoURL!.isEmpty) ? const Icon(Icons.person, size: 40) : null,
                                ),
                              ),
                            ),
                            IgnorePointer(ignoring: true, child: SizedBox(height: 110, width: 200, child: Lottie.asset(LevelFrameManager.getFrameForLevel(level), repeat: true, fit: BoxFit.contain, alignment: Alignment.center))),
                            if (_isCurrentUserProfile)
                              Positioned(
                                bottom: 5,
                                right: 55,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                  child: _isUploadingProfilePhoto ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text((userData?['displayName'] as String?) ?? 'Usuário', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                              Text(LevelFrameManager.getRankName(level), style: const TextStyle(color: Colors.orangeAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                              Text((userData?['username'] != null && (userData?['username'] as String).trim().isNotEmpty) ? "@${userData?['username']}" : "Adicionar @", style: const TextStyle(color: Colors.white70, fontSize: 14)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)), child: Text("Nível $level", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 13))),
                                  const SizedBox(width: 10),
                                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: xp.clamp(0.0, 1.0), backgroundColor: Colors.white24, color: Colors.orangeAccent, minHeight: 6))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (!_isCurrentUserProfile)
                      Padding(
                        padding: const EdgeInsets.only(top: 12, left: 20),
                        child: FollowButton(
                          userId: _profileUserId,
                          onStatusChanged: _loadAll,
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

  SliverPersistentHeader _buildTabBar() {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _TabBarDelegate(
        const TabBar(
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Color(0xFFFF6D00),
          indicatorWeight: 3,
          tabs: [
            Tab(text: 'Início'),
            Tab(text: 'Conquistas'),
            Tab(text: 'Histórico'),
            Tab(text: 'Desafios'),
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
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(color: Colors.white, child: tabBar);
  @override
  double get maxExtent => tabBar.preferredSize.height;
  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => oldDelegate.tabBar != tabBar;
}

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

  @override
  void initState() {
    super.initState();
    _bio = widget.bio;
    _isPrivate = widget.isPrivate;
  }

  @override
  void didUpdateWidget(_StatsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bio != widget.bio) _bio = widget.bio;
    if (oldWidget.isPrivate != widget.isPrivate) _isPrivate = widget.isPrivate;
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}min' : '${m}min';
  }

  Future<void> _editBio() async {
    if (!widget.isOwner) return;
    final controller = TextEditingController(text: _bio ?? '');
    final res = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar biografia'),
        content: TextField(controller: controller, autofocus: true, maxLength: 160, decoration: const InputDecoration(hintText: 'Escreva algo sobre você…', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Salvar')),
        ],
      ),
    );
    if (res != null) {
      await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({'bio': res});
      setState(() => _bio = res);
      widget.onBioUpdated(res);
    }
  }

  Future<void> _togglePrivacy(bool v) async {
    await FirebaseFirestore.instance.collection('users').doc(widget.userId).update({'isPrivate': v});
    setState(() => _isPrivate = v);
    widget.onPrivacyToggled(v);
  }

  @override
  Widget build(BuildContext context) {
    final isPro = (widget.userData?['isPro'] ?? false) as bool;
    final name = widget.userData?['displayName'] ?? 'Usuário';

    // ✅ ajuste esse valor para a altura REAL do seu bottom nav do MainScaffold
    // (se seu CurvedNavbar for grande, use algo tipo 90~110)
    const double kBottomNavOverlay = 96;

    final double bottomSafe =
        MediaQuery.of(context).padding.bottom + kBottomNavOverlay;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomSafe),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.memberSinceText,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                const SizedBox(height: 8),
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
                          : (widget.isOwner ? "Adicione uma biografia" : "Sem biografia"),
                      style: TextStyle(
                        color: (_bio != null && _bio!.isNotEmpty)
                            ? Colors.black87
                            : Colors.black45,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                if (widget.isOwner)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text(
                          'Editar perfil',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFFF6D00)),
                          foregroundColor: const Color(0xFFFF6D00),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditProfilePage(userId: widget.userId),
                          ),
                        ).then((_) => widget.onRefreshSocial()),
                      ),
                    ),
                  ),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FollowersPage(
                              userId: widget.userId,
                              displayName: name,
                            ),
                          ),
                        );
                      },
                      child: _chipStat("Seguidores", widget.followersCount),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FollowersPage(
                              userId: widget.userId,
                              displayName: name,
                            ),
                          ),
                        );
                      },
                      child: _chipStat("Seguindo", widget.followingCount),
                    ),
                  ],
                ),

                if (widget.isOwner)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Conta privada',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Apenas seguidores aprovados veem suas atividades.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    value: _isPrivate,
                    onChanged: _togglePrivacy,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelpPage()),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.help_outline, color: Color(0xFFFF6D00), size: 34),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Ajuda: XP, Pontos e Elo",
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 2),
                        Text(
                          "Entenda como subir de nível e dominar o mapa",
                          style: TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.black45),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
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
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                      Text(
                        isPro ? "Benefícios exclusivos" : "Desbloqueie conquistas douradas",
                        style: const TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProPlansPage()),
                  ),
                  child: const Text(
                    "VER MAIS →",
                    style: TextStyle(color: Color(0xFFFF6D00), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            children: [
              _StatBox(
                icon: Icons.directions_run,
                label: 'Distância',
                value: "${widget.totalDistance30d.toStringAsFixed(1)} km",
              ),
              _StatBox(
                icon: Icons.access_time,
                label: 'Tempo',
                value: _formatDuration(widget.totalDuration30d),
              ),
              _StatBox(
                icon: Icons.local_fire_department,
                label: 'Calorias',
                value: "${widget.totalCalories30d.toStringAsFixed(0)} kcal",
              ),
            ],
          ),

          const SizedBox(height: 10),

          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PointsDetailsPage(
                  userId: widget.userId,
                  displayName: name,
                  isOwner: widget.isOwner,
                ),
              ),
            ),
            child: Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  const Icon(Icons.star, color: Color(0xFFFF6D00), size: 40),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      widget.isOwner
                          ? "Você tem ${widget.totalPoints} pontos"
                          : "$name tem ${widget.totalPoints} pontos",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.black45),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          if (widget.isOwner)
            Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Sair'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red,
                  minimumSize: const Size(double.infinity, 50),
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => FirebaseAuth.instance
                    .signOut()
                    .then((_) => Navigator.pushReplacementNamed(context, '/login')),
              ),
            ),
        ],
      ),
    );
  }


  Widget _chipStat(String label, int value) => Column(children: [Text('$value', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13))]);
}

class _StatBox extends StatelessWidget {
  final IconData icon; final String label; final String value;
  const _StatBox({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 16), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: const Color(0xFFFF6D00)), const SizedBox(height: 8), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), const SizedBox(height: 4), Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12))]));
}

class _AchievementsTab extends StatefulWidget {
  const _AchievementsTab();
  @override
  State<_AchievementsTab> createState() => _AchievementsTabState();
}

class _AchievementsTabState extends State<_AchievementsTab> {
  List<Map<String, dynamic>> _achievements = [];
  bool _loading = true;
  @override
  void initState() { super.initState(); _loadAchievements(); }
  Future<void> _loadAchievements() async {
    final list = await AchievementService().getUserAchievements();
    if (mounted) setState(() { _achievements = list; _loading = false; });
  }
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _achievements.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemBuilder: (context, i) {
        final a = _achievements[i];
        final unlocked = a['unlocked'] == true;
        return Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: unlocked ? Colors.amber : Colors.black12)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(a['icon'] ?? '🏅', style: TextStyle(fontSize: 30, color: unlocked ? Colors.black : Colors.black38)), const SizedBox(height: 6), Text(a['title'] ?? '', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: unlocked ? Colors.black87 : Colors.black45))]),
        );
      },
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final String userId;
  const _HistoryTab({required this.userId});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('corridas').where('userId', isEqualTo: userId).orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text("Nenhuma corrida ainda"));
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 14),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            data['route'] ??= (data['path'] ?? const []);
            return _RunCard(corrida: RunModel.fromMap(data));
          },
        );
      },
    );
  }
}

class _ChallengesTab extends StatelessWidget {
  final String userId;
  const _ChallengesTab({required this.userId});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('challenges').where('participants', arrayContains: userId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text("Nenhum desafio participando"));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(data['title'] ?? 'Desafio'),
                subtitle: Text(data['description'] ?? ''),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChallengeDetailsPage(challengeId: docs[i].id))),
              ),
            );
          },
        );
      },
    );
  }
}

class _RunCard extends StatelessWidget {
  final RunModel corrida;
  const _RunCard({required this.corrida});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetalheCorridaPage(corrida: corrida))),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Expanded(child: CustomPaint(painter: _RoutePainter(corrida.route), child: const SizedBox.expand())),
            const SizedBox(height: 8),
            Text("${(corrida.distance / 1000).toStringAsFixed(2)} km", style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("${(corrida.duration / 60).toStringAsFixed(1)} min", style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final List<Map<String, double>> route;
  _RoutePainter(this.route);
  @override
  void paint(Canvas canvas, Size size) {
    if (route.isEmpty) return;
    final paint = Paint()..color = const Color(0xFFFF6D00)..strokeWidth = 2..style = PaintingStyle.stroke;
    double minLat = route.first['lat']!, maxLat = route.first['lat']!, minLng = route.first['lng']!, maxLng = route.first['lng']!;
    for (var p in route) {
      minLat = min(minLat, p['lat']!); maxLat = max(maxLat, p['lat']!);
      minLng = min(minLng, p['lng']!); maxLng = max(maxLng, p['lng']!);
    }
    final latR = maxLat - minLat == 0 ? 0.0001 : maxLat - minLat;
    final lngR = maxLng - minLng == 0 ? 0.0001 : maxLng - minLng;
    final path = Path();
    for (int i = 0; i < route.length; i++) {
      final dx = (route[i]['lng']! - minLng) / lngR * size.width;
      final dy = size.height - (route[i]['lat']! - minLat) / latR * size.height;
      if (i == 0) path.moveTo(dx, dy); else path.lineTo(dx, dy);
    }
    canvas.drawPath(path, paint);
  }
  @override bool shouldRepaint(covariant CustomPainter old) => false;
}
