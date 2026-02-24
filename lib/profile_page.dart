import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';

import 'package:run_walk_app/activity_page.dart';
import 'package:run_walk_app/challenge_details_page.dart';
import 'package:run_walk_app/detalhe_corrida_page.dart';
import 'package:run_walk_app/edit_profile_page.dart';
import 'package:run_walk_app/followers_page.dart';
import 'package:run_walk_app/help_page.dart';
import 'package:run_walk_app/model/run_model.dart';
import 'package:run_walk_app/performance_analysis_page.dart';
import 'package:run_walk_app/points_details_page.dart';
import 'package:run_walk_app/pro_plans_page.dart';
import 'package:run_walk_app/service/achievement_service.dart';
import 'package:run_walk_app/service/level_frame_manager.dart';
import 'package:run_walk_app/service/service/firestore_service.dart';
import 'package:run_walk_app/service/service/gamification_service.dart';
import 'package:run_walk_app/territories_gallery_page.dart';
import 'package:run_walk_app/territory_details_page.dart';
import 'package:run_walk_app/training_plan_page.dart';
import 'package:run_walk_app/widgets/achievement_overlay.dart';
import 'package:run_walk_app/widgets/follow_button.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;

// ✅ SEASON THEME
import 'package:run_walk_app/theme/season_theme_scope.dart';

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

    _xpListener = FirebaseFirestore.instance
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
        photoURL = _nonnullOrBlankToNull(data['photoURL']);
        coverPhotoURL = _nonnullOrBlankToNull(data['coverPhoto']);
        memberSince = (data['createdAt'] is Timestamp)
            ? (data['createdAt'] as Timestamp).toDate()
            : null;
        bio = _nonnullOrBlankToNull(data['bio']);
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
      totalPoints =
      await GamificationService().getTotalPoints(userId: _profileUserId);
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
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'coverPhoto': url});
      setState(() => coverPhotoURL = url);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Capa atualizada!')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _isUploadingCoverPhoto = false);
    }
  }

  Future<void> _changeProfilePhoto() async {
    if (!_isCurrentUserProfile) return;

    final picker = ImagePicker();
    final s = SeasonThemeScope.of(context);

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: s.popover,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.photo_library, color: s.foreground),
              title: Text('Galeria',
                  style: TextStyle(color: s.foreground, fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: Icon(Icons.photo_camera, color: s.foreground),
              title: Text('Câmera',
                  style: TextStyle(color: s.foreground, fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
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

      final mainBytes = await FlutterImageCompress.compressWithFile(
        file.path,
        quality: 80,
        minWidth: 600,
        minHeight: 600,
      );
      final thumbBytes = await FlutterImageCompress.compressWithFile(
        file.path,
        quality: 60,
        minWidth: 200,
        minHeight: 200,
      );
      if (mainBytes == null || thumbBytes == null) throw 'Erro na compressão';

      final storage = FirebaseStorage.instance;
      final mainRef = storage.ref().child('users/$_profileUserId/photo.jpg');
      final thumbRef =
      storage.ref().child('users/$_profileUserId/photo_thumb.jpg');

      await mainRef.putData(mainBytes,
          SettableMetadata(contentType: 'image/jpeg'));
      final downloadURL = await mainRef.getDownloadURL();

      await thumbRef.putData(thumbBytes,
          SettableMetadata(contentType: 'image/jpeg'));
      final thumbUrl = await thumbRef.getDownloadURL();

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null && currentUser.uid == _profileUserId) {
        await currentUser.updatePhotoURL(downloadURL);
        await currentUser.reload();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(_profileUserId)
          .set({
        'photoURL': downloadURL,
        'photoThumbURL': thumbUrl,
        'updatedAt': FieldValue.serverTimestamp()
      }, SetOptions(merge: true));

      if (mounted) setState(() => photoURL = downloadURL);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _isUploadingProfilePhoto = false);
    }
  }

  String _formatDate(DateTime? d) => d == null ? '' : d.year.toString();

  @override
  Widget build(BuildContext context) {
    final s = SeasonThemeScope.of(context);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final canSeeContent = !isPrivate || _isCurrentUserProfile || isFollowing;

    return DefaultTabController(
      length: canSeeContent ? 4 : 0,
      child: Scaffold(
        backgroundColor: s.background,
        body: loading
            ? Center(child: CircularProgressIndicator(color: s.accent))
            : RefreshIndicator(
          color: s.accent,
          backgroundColor: s.card,
          onRefresh: _loadAll,
          child: NestedScrollView(
            headerSliverBuilder: (context, inner) => [
              _buildHeader(context, s),
              if (canSeeContent) _buildTabBar(context, s),
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
                  memberSinceText: memberSince != null
                      ? "Membro desde ${_formatDate(memberSince)}"
                      : "",
                  totalDistance30d: totalDistance,
                  totalDuration30d: totalDuration,
                  totalCalories30d: totalCalories,
                  totalPoints: totalPoints,
                  onBioUpdated: (newBio) =>
                      setState(() => bio = newBio),
                  onPrivacyToggled: (v) =>
                      setState(() => isPrivate = v),
                  onRefreshSocial: _loadUserAndSocial,
                ),
                const _AchievementsTab(),
                _HistoryTab(userId: _profileUserId, isOwner: _isCurrentUserProfile),
                _ChallengesTab(userId: _profileUserId),
              ],
            )
                : _buildPrivateAccountMessage(context, s),
          ),
        ),
      ),
    );
  }

  Widget _buildPrivateAccountMessage(BuildContext context, SeasonTheme s) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 80, color: s.mutedForeground),
            const SizedBox(height: 16),
            Text(
              "Esta conta é privada",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: s.foreground,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Siga este usuário para ver suas atividades, conquistas e histórico.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: s.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildHeader(BuildContext context, SeasonTheme s) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 280,
      backgroundColor: s.background,
      elevation: 0,
      iconTheme: IconThemeData(color: s.accent),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              coverPhotoURL ??
                  'https://play-lh.googleusercontent.com/yf1-mu5GFf-eUu7uyV1GpNwbsPmXNY_J2PFZBjl7tNx6qVL5I_fnOkfSusFmzSZrbRiZu1CwYS2y7La7WQmhpg=w240-h480-rw',
              fit: BoxFit.cover,
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    s.background.withOpacity(0.80),
                    Colors.transparent,
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                ),
              ),
            ),
            if (_isCurrentUserProfile)
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                right: 16,
                child: CircleAvatar(
                  backgroundColor: s.card.withOpacity(0.55),
                  child: IconButton(
                    icon: _isUploadingCoverPhoto
                        ? SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: s.cardForeground,
                      ),
                    )
                        : Icon(Icons.edit, color: s.cardForeground),
                    onPressed: _isUploadingCoverPhoto ? null : _changeCoverPhoto,
                  ),
                ),
              ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
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
                                onTap: _isCurrentUserProfile
                                    ? _changeProfilePhoto
                                    : null,
                                child: CircleAvatar(
                                  radius: 42,
                                  backgroundColor: s.card,
                                  backgroundImage: (photoURL != null &&
                                      photoURL!.isNotEmpty)
                                      ? NetworkImage(photoURL!)
                                      : null,
                                  child: (photoURL == null || photoURL!.isEmpty)
                                      ? Icon(Icons.person,
                                      size: 40,
                                      color: s.mutedForeground)
                                      : null,
                                ),
                              ),
                            ),
                            IgnorePointer(
                              ignoring: true,
                              child: SizedBox(
                                height: 110,
                                width: 200,
                                child: Lottie.asset(
                                  LevelFrameManager.getFrameForLevel(level),
                                  repeat: true,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.center,
                                ),
                              ),
                            ),
                            if (_isCurrentUserProfile)
                              Positioned(
                                bottom: 5,
                                right: 55,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: s.card.withOpacity(0.6),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: s.border),
                                  ),
                                  child: _isUploadingProfilePhoto
                                      ? SizedBox(
                                    height: 14,
                                    width: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: s.cardForeground,
                                    ),
                                  )
                                      : Icon(Icons.camera_alt,
                                      size: 14, color: s.cardForeground),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (userData?['displayName'] as String?) ??
                                    'Usuário',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                ),
                              ),
                              Text(
                                LevelFrameManager.getRankName(level),
                                style: TextStyle(
                                  color: s.accent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
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
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: s.card.withOpacity(0.55),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: s.border),
                                    ),
                                    child: Text(
                                      "Nível $level",
                                      style: TextStyle(
                                        color: s.accent,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: xp.clamp(0.0, 1.0),
                                        backgroundColor:
                                        s.muted.withOpacity(0.35),
                                        color: s.accent,
                                        minHeight: 6,
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

  SliverPersistentHeader _buildTabBar(BuildContext context, SeasonTheme s) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _TabBarDelegate(
        TabBar(
          labelColor: s.foreground,
          unselectedLabelColor: s.mutedForeground,
          indicatorColor: s.accent,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Início'),
            Tab(text: 'Conquistas'),
            Tab(text: 'Histórico'),
            Tab(text: 'Desafios'),
          ],
        ),
        background: s.background,
        border: s.border,
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color background;
  final Color border;

  _TabBarDelegate(this.tabBar, {required this.background, required this.border});

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: tabBar,
    );
  }

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar ||
          oldDelegate.background != background ||
          oldDelegate.border != border;
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

  Future<void> _analyzePerformance() async {
    final s = SeasonThemeScope.of(context);

    try {
      // 1️⃣ Buscar últimas corridas (ex: últimas 10)
      final snapshot = await FirebaseFirestore.instance
          .collection('corridas')
          .where('userId', isEqualTo: widget.userId)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      if (snapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Você ainda não tem corridas suficientes.")),
        );
        return;
      }

      // 2️⃣ Montar string raceData
      String raceData = "";

      for (var doc in snapshot.docs) {
        final data = doc.data();

        final distanceKm =
            ((data['distance'] as num?)?.toDouble() ?? 0) / 1000.0;

        final durationSeconds =
            (data['duration'] as num?)?.toInt() ?? 0;

        final minutes = durationSeconds ~/ 60;
        final seconds = durationSeconds % 60;

        final pace =
            (data['pace'] as num?)?.toDouble() ?? 0.0;

        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

        raceData +=
        "- Data: ${createdAt?.day}/${createdAt?.month}/${createdAt?.year}, "
            "Distância: ${distanceKm.toStringAsFixed(2)} km, "
            "Duração: ${minutes}m ${seconds}s, "
            "Pace Médio: ${pace.toStringAsFixed(2)} min/km\n";
      }

      // 3️⃣ Chamada HTTP
      final response = await http.post(
        Uri.parse(
          "https://studio--studio-4298368751-f334d.us-central1.hosted.app/api/analyze-performance",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"raceData": raceData}),
      );

      if (response.statusCode != 200) {
        throw Exception("Erro na API: ${response.body}");
      }

      final json = jsonDecode(response.body);

      _showAnalysisDialog(
        strengths: List<String>.from(json['strengths'] ?? []),
        improvements: List<String>.from(json['improvements'] ?? []),
        summary: json['summary'] ?? '',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erro ao analisar desempenho: $e")),
      );
    }
  }

  void _showAnalysisDialog({
    required List<String> strengths,
    required List<String> improvements,
    required String summary,
  }) {
    final s = SeasonThemeScope.of(context);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: s.popover,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          "Análise do seu Perfil",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: s.foreground,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("💪 Pontos Fortes",
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: s.accent)),
              const SizedBox(height: 6),
              ...strengths.map((e) => Text("• $e")),
              const SizedBox(height: 14),
              Text("📈 Pontos a Melhorar",
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: s.accent)),
              const SizedBox(height: 6),
              ...improvements.map((e) => Text("• $e")),
              const SizedBox(height: 14),
              Text("🧠 Resumo",
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: s.accent)),
              const SizedBox(height: 6),
              Text(summary),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Fechar"),
          )
        ],
      ),
    );
  }

  Future<void> _editBio() async {
    if (!widget.isOwner) return;

    final s = SeasonThemeScope.of(context);
    final controller = TextEditingController(text: _bio ?? '');

    final res = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: s.popover,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Editar biografia',
            style: TextStyle(color: s.foreground, fontWeight: FontWeight.w900)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 160,
          style: TextStyle(color: s.foreground),
          decoration: InputDecoration(
            hintText: 'Escreva algo sobre você…',
            hintStyle: TextStyle(color: s.mutedForeground),
            filled: true,
            fillColor: s.input,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: s.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: s.ring, width: 1.6),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar',
                style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w800)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: s.accent,
              foregroundColor: s.accentForeground,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: const Text('Salvar', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (res != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({'bio': res});
      setState(() => _bio = res);
      widget.onBioUpdated(res);
    }
  }

  Future<void> _togglePrivacy(bool v) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .update({'isPrivate': v});
    setState(() => _isPrivate = v);
    widget.onPrivacyToggled(v);
  }

  @override
  Widget build(BuildContext context) {
    final s = SeasonThemeScope.of(context);

    final isPro = (widget.userData?['isPro'] ?? false) as bool;
    final name = widget.userData?['displayName'] ?? 'Usuário';

    // ✅ ajuste esse valor para a altura REAL do seu bottom nav do MainScaffold
    const double kBottomNavOverlay = 96;
    final double bottomSafe =
        MediaQuery.of(context).padding.bottom + kBottomNavOverlay;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottomSafe),
      child: Column(
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.memberSinceText,
                  style: TextStyle(
                    color: s.mutedForeground,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),

                GestureDetector(
                  onTap: widget.isOwner ? _editBio : null,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: s.input,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: s.border),
                    ),
                    child: Text(
                      (_bio != null && _bio!.isNotEmpty)
                          ? _bio!
                          : (widget.isOwner
                          ? "Adicione uma biografia"
                          : "Sem biografia"),
                      style: TextStyle(
                        color: (_bio != null && _bio!.isNotEmpty)
                            ? s.foreground
                            : s.mutedForeground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                if (widget.isOwner)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.edit, size: 18, color: s.accent),
                        label: Text(
                          'Editar perfil',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: s.accent,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: s.accent),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
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
                      child: _chipStat(context, "Seguidores", widget.followersCount),
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
                      child: _chipStat(context, "Seguindo", widget.followingCount),
                    ),
                  ],
                ),

                if (widget.isOwner)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Conta privada',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: s.foreground,
                      ),
                    ),
                    subtitle: Text(
                      'Apenas seguidores aprovados veem suas atividades.',
                      style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w600),
                    ),
                    value: _isPrivate,
                    activeColor: s.accent,
                    onChanged: _togglePrivacy,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          if (widget.isOwner)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.analytics),
                label: const Text("Análise do meu perfil de jogador"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: s.accent,
                  foregroundColor: s.accentForeground,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PerformanceAnalysisPage(
                        userId: widget.userId,
                      ),
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.fitness_center),
              label: const Text("Plano de Treino"),
              style: ElevatedButton.styleFrom(
                backgroundColor: s.accent,
                foregroundColor: s.accentForeground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TrainingPlanPage(
                      userId: widget.userId,
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          const SizedBox(height: 10),

          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HelpPage()),
            ),
            child: _Card(
              child: Row(
                children: [
                  Icon(Icons.help_outline, color: s.accent, size: 34),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Ajuda: XP, Pontos e Elo",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: s.foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Entenda como subir de nível e dominar o mapa",
                          style: TextStyle(
                            color: s.mutedForeground,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: s.mutedForeground),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          _Card(
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
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          color: s.foreground,
                        ),
                      ),
                      Text(
                        isPro ? "Benefícios exclusivos" : "Desbloqueie conquistas douradas",
                        style: TextStyle(
                          color: s.mutedForeground,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProPlansPage()),
                  ),
                  child: Text(
                    "VER MAIS →",
                    style: TextStyle(
                      color: s.accent,
                      fontWeight: FontWeight.w900,
                    ),
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

          //const SizedBox(height: 12),

          _DominatedTerritoriesSection(
            userId: widget.userId,
            isOwner: widget.isOwner,
          ),



          const SizedBox(height: 10),

          InkWell(
            borderRadius: BorderRadius.circular(18),
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

            child: _Card(
              child: Row(
                children: [
                  Icon(Icons.star, color: s.accent, size: 40),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      widget.isOwner
                          ? "Você tem ${widget.totalPoints} pontos"
                          : "$name tem ${widget.totalPoints} pontos",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: s.foreground,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: s.mutedForeground),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          if (widget.isOwner)
            Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Sair'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: s.destructive,
                  side: BorderSide(color: s.destructive.withOpacity(0.85)),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
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

  Widget _chipStat(BuildContext context, String label, int value) {
    final s = SeasonThemeScope.of(context);
    return Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: s.foreground,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: s.mutedForeground,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final s = SeasonThemeScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: s.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: s.border),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            spreadRadius: 0,
            offset: const Offset(0, 8),
            color: Colors.black.withOpacity(0.25),
          )
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: child,
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
    final s = SeasonThemeScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: s.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: s.border),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: s.accent),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: s.foreground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: s.mutedForeground,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          )
        ],
      ),
    );
  }
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
  void initState() {
    super.initState();
    _loadAchievements();
  }

  Future<void> _loadAchievements() async {
    final list = await AchievementService().getUserAchievements();
    if (mounted) setState(() => {_achievements = list, _loading = false});
  }

  @override
  Widget build(BuildContext context) {
    final s = SeasonThemeScope.of(context);

    if (_loading) return Center(child: CircularProgressIndicator(color: s.accent));

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _achievements.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, i) {
        final a = _achievements[i];
        final unlocked = a['unlocked'] == true;

        return Container(
          decoration: BoxDecoration(
            color: s.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: unlocked ? Colors.amber.withOpacity(0.9) : s.border,
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                a['icon'] ?? '🏅',
                style: TextStyle(
                  fontSize: 30,
                  color: unlocked ? s.foreground : s.mutedForeground,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                a['title'] ?? '',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: unlocked ? s.foreground : s.mutedForeground,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final String userId;
  final bool isOwner;

  const _HistoryTab({required this.userId, required this.isOwner});

  @override
  Widget build(BuildContext context) {
    final s = SeasonThemeScope.of(context);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('corridas')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator(color: s.accent));
        }

        final allDocs = snapshot.data!.docs;

        // ✅ Regra: corrida com isArchived:true só aparece para o dono
        final docs = isOwner
            ? allDocs
            : allDocs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return (data['isArchived'] == true) ? false : true;
        }).toList();

        if (docs.isEmpty) {
          return Center(
            child: Text(
              "Nenhuma corrida ainda",
              style: TextStyle(
                color: s.mutedForeground,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(14),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;

            data['route'] ??= (data['path'] ?? const []);

            final corrida = RunModel.fromMap({
              ...data,
              'id': doc.id,
            });

            final bool isArchived = (data['isArchived'] == true);

            return _RunCard(
              corrida: corrida,
              isArchived: isArchived,
              showArchivedBadge: isOwner, // ✅ só o dono vê o badge
            );
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
    final s = SeasonThemeScope.of(context);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('challenges')
          .where('participants', arrayContains: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator(color: s.accent));
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text(
              "Nenhum desafio participando",
              style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w700),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: s.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: s.border),
              ),
              child: ListTile(
                title: Text(
                  data['title'] ?? 'Desafio',
                  style: TextStyle(color: s.foreground, fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  data['description'] ?? '',
                  style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w600),
                ),
                trailing: Icon(Icons.chevron_right, color: s.mutedForeground),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChallengeDetailsPage(challengeId: docs[i].id),
                  ),
                ),
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
  final bool isArchived;
  final bool showArchivedBadge;

  const _RunCard({
    required this.corrida,
    this.isArchived = false,
    this.showArchivedBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = SeasonThemeScope.of(context);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DetalheCorridaPage(corrida: corrida)),
      ),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: s.card,
              border: Border.all(color: s.border),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Expanded(
                  child: CustomPaint(
                    painter: _RoutePainter(corrida.route, color: s.accent),
                    child: const SizedBox.expand(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "${(corrida.distance / 1000).toStringAsFixed(2)} km",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: s.foreground,
                  ),
                ),
                Text(
                  "${(corrida.duration / 60).toStringAsFixed(1)} min",
                  style: TextStyle(
                    fontSize: 12,
                    color: s.mutedForeground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          // ✅ Badge de arquivado (somente dono vê)
          if (showArchivedBadge && isArchived)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: s.card.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: s.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.archive_rounded, size: 16, color: s.mutedForeground),
                    const SizedBox(width: 6),
                    Text(
                      "Arquivada",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: s.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}


class _RoutePainter extends CustomPainter {
  final List<Map<String, double>> route;
  final Color color;

  _RoutePainter(this.route, {required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (route.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    double minLat = route.first['lat']!,
        maxLat = route.first['lat']!,
        minLng = route.first['lng']!,
        maxLng = route.first['lng']!;

    for (var p in route) {
      minLat = min(minLat, p['lat']!);
      maxLat = max(maxLat, p['lat']!);
      minLng = min(minLng, p['lng']!);
      maxLng = max(maxLng, p['lng']!);
    }

    final latR = maxLat - minLat == 0 ? 0.0001 : maxLat - minLat;
    final lngR = maxLng - minLng == 0 ? 0.0001 : maxLng - minLng;

    final path = Path();
    for (int i = 0; i < route.length; i++) {
      final dx = (route[i]['lng']! - minLng) / lngR * size.width;
      final dy =
          size.height - (route[i]['lat']! - minLat) / latR * size.height;
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _DominatedTerritoriesSection extends StatelessWidget {
  final String userId;
  final bool isOwner;

  const _DominatedTerritoriesSection({
    required this.userId,
    required this.isOwner,
  });

  @override
  Widget build(BuildContext context) {
    final s = SeasonThemeScope.of(context);

    final query = FirebaseFirestore.instance
        .collection('territorios')
        .where('userId', isEqualTo: userId);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return _Card(
            child: Row(
              children: [
                Icon(Icons.public, color: s.accent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Carregando territórios...",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: s.foreground,
                    ),
                  ),
                ),
                SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: s.accent,
                  ),
                ),
              ],
            ),
          );
        }

        final docs = snap.data!.docs;

        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.public, color: s.accent, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Territórios dominados",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: s.foreground,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TerritoriesGalleryPage(
                            userId: userId,
                            isOwner: isOwner,
                          ),
                        ),
                      );
                    },
                    child: Text(
                      "VER TODOS →",
                      style: TextStyle(
                        color: s.accent,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (docs.isEmpty)
                Text(
                  isOwner
                      ? "Você ainda não domina nenhum território. Faça uma corrida e conquiste áreas no mapa 👑"
                      : "Este usuário ainda não domina nenhum território.",
                  style: TextStyle(color: s.mutedForeground, fontWeight: FontWeight.w600),
                )
              else
                SizedBox(
                  height: 86,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      final territoryId = docs[i].id;

                      final title = (data['customName'] ??
                          data['name'] ??
                          data['title'] ??
                          data['territoryName'] ??
                          "Território")
                          .toString();

                      final difficulty = (data['difficulty'] is num)
                          ? (data['difficulty'] as num).toInt()
                          : null;

                      final safety = (data['safety'] ?? '').toString();

                      final badge = safety.isNotEmpty
                          ? (safety == 'safe'
                          ? 'Tranquilo'
                          : (safety == 'danger' ? 'Perigoso' : safety))
                          : (difficulty != null
                          ? 'Dificuldade $difficulty/5'
                          : 'Domínio ativo');

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TerritoryDetailsPage(
                                  territoryId: territoryId,
                                  isOwner: isOwner,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            width: 190,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: s.input,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: s.border),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  height: 44,
                                  width: 44,
                                  decoration: BoxDecoration(
                                    color: s.accent.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: s.border),
                                  ),
                                  child: Icon(Icons.flag, color: s.accent),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: s.foreground,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        badge,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: s.mutedForeground,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
