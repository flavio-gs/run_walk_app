import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:run_walk_app/service/achievement_service.dart';

// Corrigido o caminho do service
import 'package:run_walk_app/service/service/gamification_service.dart';

import 'package:run_walk_app/auth_gate.dart';

class ProfilePage extends StatefulWidget {
  final String? userId;
  const ProfilePage({super.key, this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  double totalDistance = 0;
  int totalDuration = 0;
  double totalCalories = 0;
  int totalPoints = 0;

  bool loading = true;
  String? photoURL;
  Map<String, dynamic>? userData;

  final Color primaryGreen = const Color(0xFF00C853);
  final Color accentOrange = const Color(0xFFFF6D00);
  final Color softOrange = const Color(0xFFFF9100);
  final Color logoutRed = const Color(0xFFE53935);

  late final String _profileUserId;
  late final bool _isCurrentUserProfile;

  @override
  void initState() {
    super.initState();
    _profileUserId = widget.userId ?? FirebaseAuth.instance.currentUser!.uid;
    _isCurrentUserProfile = _profileUserId == FirebaseAuth.instance.currentUser!.uid;
    _loadUserStats();
  }

  Future<void> _loadUserStats() async {
    try {
      totalPoints = await GamificationService().getTotalPoints();

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (Platform.isAndroid && mounted && MediaQuery.of(context).size.shortestSide < 300) {
          await _loadMockData();
        } else {
          setState(() => loading = false);
        }
        return;
      }

      final corridasQuery = await FirebaseFirestore.instance
          .collection('corridas')
          .where('userId', isEqualTo: _profileUserId)
          .get();

      double distance = 0;
      int duration = 0;
      double calories = 0;
      for (var doc in corridasQuery.docs) {
        final data = doc.data();
        distance += (data['distance'] as num?)?.toDouble() ?? 0.0;
        duration += (data['duration'] as num?)?.toInt() ?? 0;
        calories += (data['calories'] as num?)?.toDouble() ?? 0.0;
      }

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(_profileUserId).get();

      final data = userDoc.data() ?? {};
      final int xp = (data['xp'] ?? 0) as int;
      final int level = (data['level'] ?? 1) as int;
      final double levelProgress = (data['levelProgress'] ?? 0.0).toDouble();

      if (mounted) {
        setState(() {
          totalDistance = distance;
          totalDuration = duration;
          totalCalories = calories;
          userData = userDoc.data() ?? {};
          photoURL = userData?['photoURL'] ??
              (userDoc.id == currentUser.uid ? currentUser.photoURL : null);
          loading = false;
          userData = {
            ...data,
            'xp': xp,
            'level': level,
            'levelProgress': levelProgress,
          };
        });
      }

    } catch (e) {
      debugPrint("Erro ao carregar estatísticas: $e");
      if (mounted) setState(() => loading = false);
    }
  }


  Future<void> _loadMockData() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {
      totalDistance = 12.34;
      totalDuration = 4200;
      totalCalories = 870;
      totalPoints = 320;
      userData = {'displayName': 'Usuário Demo', 'city': 'Rio de Janeiro', 'state': 'RJ'};
      photoURL = null;
      loading = false;
    });
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}min';
    if (m > 0) return '${m}min ${s}s';
    return '${s}s';
  }

  bool get isWearOS {
    try {
      return Platform.isAndroid && MediaQuery.of(context).size.shortestSide < 300;
    } catch (e) {
      return false;
    }
  }


  @override
  Widget build(BuildContext context) {
    return isWearOS ? _buildWearView() : _buildMobileView();
  }

  Widget _buildLevelCard({required int level, required double progress, required int xp}) {
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.amber.withOpacity(0.2),
              child: Text("$level",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Nível", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation(Colors.amber),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text("XP: $xp", style: const TextStyle(color: Colors.black54, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ---------------------------------
  //  VIEW MOBILE
  // ---------------------------------
  Widget _buildMobileView() {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadUserStats,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: primaryGreen,
              expandedHeight: 220,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                title: Text(
                  userData?['displayName'] ?? 'Perfil',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white),
                ),
                background: Stack(fit: StackFit.expand, children: [
                  Container(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: [primaryGreen, accentOrange],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight))),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: CircleAvatar(
                        radius: 45,
                        backgroundColor: Colors.white.withOpacity(0.25),
                        backgroundImage: (photoURL != null &&
                            photoURL!.isNotEmpty)
                            ? NetworkImage(photoURL!)
                            : null,
                        child: (photoURL == null || photoURL!.isEmpty)
                            ? const Icon(Icons.person,
                            color: Colors.white, size: 50)
                            : null,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildInfoCard(),
                    const SizedBox(height: 20),
                    if (!_isCurrentUserProfile)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20.0),
                        child: _FollowButton(profileUserId: _profileUserId),
                      ),
                    _buildStatsGrid(),
                    const SizedBox(height: 25),
                    _buildUserDetails(),
                    const SizedBox(height: 20),
                    _buildPointsCard(),
                    const SizedBox(height: 25),
                    _AchievementsSection(),
                    const SizedBox(height: 40),
                    if (_isCurrentUserProfile) _buildLogoutButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------
  //  NOVO: CARD DE PONTOS
  // ---------------------------------
  Widget _buildPointsCard() {
    return Card(
      color: Colors.white,
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Icon(Icons.stars, color: accentOrange, size: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                "Pontuação total: $totalPoints pts",
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.black54),
              onPressed: () async {
                setState(() => loading = true);
                await _loadUserStats();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------
  //  RESTANTE DO SEU CÓDIGO ORIGINAL
  // ---------------------------------
  Widget _buildInfoCard() {
    final email = _isCurrentUserProfile
        ? FirebaseAuth.instance.currentUser?.email
        : userData?['email'];
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          children: [
            Text(email ?? 'E-mail não disponível',
                style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              userData?['city'] != null
                  ? "${userData?['city']} - ${userData?['state'] ?? ''}"
                  : "Localização não informada",
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    final List<Map<String, dynamic>> stats = [
      {
        'icon': Icons.directions_run,
        'label': 'Distância',
        'value': "${totalDistance.toStringAsFixed(2)} km",
        'color': primaryGreen,
      },
      {
        'icon': Icons.access_time,
        'label': 'Tempo',
        'value': _formatDuration(totalDuration),
        'color': accentOrange,
      },
      {
        'icon': Icons.local_fire_department,
        'label': 'Calorias',
        'value': "${totalCalories.toStringAsFixed(0)} kcal",
        'color': softOrange,
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stats.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemBuilder: (context, index) {
        final stat = stats[index];
        final Color color = stat['color'] as Color;
        return Container(
          decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(15)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(stat['icon'] as IconData, color: color, size: 30),
              const SizedBox(height: 8),
              Text(stat['value'] as String,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 4),
              Text(stat['label'] as String,
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUserDetails() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _infoRow(Icons.person, 'Nome', userData?['displayName'] ?? '—'),
            _infoRow(Icons.calendar_today, 'Nascimento',
                userData?['birthDate'] ?? '—'),
            _infoRow(Icons.female, 'Gênero', userData?['gender'] ?? '—'),
            _infoRow(Icons.monitor_weight, 'Peso',
                '${userData?['weight'] ?? 0} kg'),
            _infoRow(Icons.height, 'Altura',
                '${userData?['height'] ?? 0} cm'),
            _infoRow(Icons.flag, 'Meta Semanal',
                '${userData?['weeklyGoal'] ?? 0} km'),
            _infoRow(Icons.home, 'CEP', userData?['cep'] ?? '—'),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, color: primaryGreen),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14))),
          Text(value,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    return ElevatedButton.icon(
      icon: const Icon(Icons.logout),
      label: const Text('Sair da Conta'),
      style: ElevatedButton.styleFrom(
        backgroundColor: logoutRed,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () async {
        await FirebaseAuth.instance.signOut();
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (c) => const AuthGate()),
                  (r) => false);
        }
      },
    );
  }

  Widget _buildWearView() {
    return Scaffold(body: Center(child: Text("Wear OS Profile")));
  }
}

class _AchievementsSection extends StatefulWidget {
  @override
  State<_AchievementsSection> createState() => _AchievementsSectionState();
}

class _AchievementsSectionState extends State<_AchievementsSection> {
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "🏆 Minhas Conquistas",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _achievements.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.9,
          ),
          itemBuilder: (context, index) {
            final a = _achievements[index];
            final bool unlocked = a['unlocked'];

            return AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              decoration: BoxDecoration(
                color: unlocked ? Colors.white : Colors.grey[300],
                borderRadius: BorderRadius.circular(16),
                boxShadow: unlocked
                    ? [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
                    : [],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    a['icon'],
                    style: TextStyle(
                      fontSize: 36,
                      color: unlocked ? Colors.black : Colors.black45,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    a['title'],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: unlocked ? Colors.black87 : Colors.black38,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------
//  BOTÃO SEGUIR (inalterado)
// ---------------------------------
class _FollowButton extends StatefulWidget {
  final String profileUserId;
  const _FollowButton({required this.profileUserId});

  @override
  State<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<_FollowButton> {
  final _currentUser = FirebaseAuth.instance.currentUser!;
  bool _isFollowing = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkIfFollowing();
  }

  Future<void> _checkIfFollowing() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUser.uid)
        .collection('following')
        .doc(widget.profileUserId)
        .get();
    if (mounted) {
      setState(() {
        _isFollowing = doc.exists;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    setState(() => _isLoading = true);
    final currentUserRef =
    FirebaseFirestore.instance.collection('users').doc(_currentUser.uid);
    final targetUserRef =
    FirebaseFirestore.instance.collection('users').doc(widget.profileUserId);
    final newFollowingState = !_isFollowing;

    try {
      if (newFollowingState) {
        await currentUserRef
            .collection('following')
            .doc(widget.profileUserId)
            .set({'timestamp': FieldValue.serverTimestamp()});
        await targetUserRef
            .collection('followers')
            .doc(_currentUser.uid)
            .set({'timestamp': FieldValue.serverTimestamp()});
        await targetUserRef.collection('notifications').add({
          'type': 'follow',
          'followerId': _currentUser.uid,
          'message':
          '${_currentUser.displayName ?? 'Alguém'} começou a seguir você.',
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        await currentUserRef
            .collection('following')
            .doc(widget.profileUserId)
            .delete();
        await targetUserRef
            .collection('followers')
            .doc(_currentUser.uid)
            .delete();
      }
      if (mounted) setState(() => _isFollowing = newFollowingState);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
          height: 48, child: Center(child: CircularProgressIndicator()));
    }
    return ElevatedButton(
      onPressed: _toggleFollow,
      style: ElevatedButton.styleFrom(
        backgroundColor:
        _isFollowing ? Colors.grey[700] : Theme.of(context).colorScheme.primary,
        foregroundColor: _isFollowing ? Colors.white : Colors.black,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(_isFollowing ? 'Deixar de Seguir' : 'Seguir',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }
}
