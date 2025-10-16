import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';

import 'package:run_walk_app/auth_gate.dart';

class ProfilePage extends StatefulWidget {
  // 1. ADICIONADO userId OPCIONAL
  final String? userId;
  const ProfilePage({super.key, this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // --- Suas variáveis de estado originais --
  double totalDistance = 0;
  int totalDuration = 0;
  double totalCalories = 0;
  bool loading = true;
  String? photoURL;
  Map<String, dynamic>? userData;

  // --- Suas constantes de cor originais ---
  final Color primaryGreen = const Color(0xFF00C853);
  final Color accentOrange = const Color(0xFFFF6D00);
  final Color softOrange = const Color(0xFFFF9100);
  final Color logoutRed = const Color(0xFFE53935);

  // --- Lógica para diferenciar perfis ---
  late final String _profileUserId;
  late final bool _isCurrentUserProfile;

  @override
  void initState() {
    super.initState();
    // 2. DEFINE QUAL PERFIL CARREGAR
    _profileUserId = widget.userId ?? FirebaseAuth.instance.currentUser!.uid;
    _isCurrentUserProfile = _profileUserId == FirebaseAuth.instance.currentUser!.uid;
    _loadUserStats();
  }

  // 3. AJUSTADO PARA CARREGAR DADOS DO PERFIL CORRETO
  Future<void> _loadUserStats() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (Platform.isAndroid && mounted && MediaQuery.of(context).size.shortestSide < 300) {
        await _loadMockData(); // Modo Demo para Wear OS
      } else {
        setState(() => loading = false);
      }
       return;
    }

    try {
      final corridasQuery = await FirebaseFirestore.instance
          .collection('corridas')
          .where('userId', isEqualTo: _profileUserId) // Usa o ID do perfil certo
          .get();

      double distance = 0; int duration = 0; double calories = 0;
      for (var doc in corridasQuery.docs) {
        final data = doc.data();
        distance += (data['distance'] as num?)?.toDouble() ?? 0.0;
        duration += (data['duration'] as num?)?.toInt() ?? 0;
        calories += (data['calories'] as num?)?.toDouble() ?? 0.0;
      }

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(_profileUserId).get();

      if(mounted) {
        setState(() {
          totalDistance = distance;
          totalDuration = duration;
          totalCalories = calories;
          userData = userDoc.data() ?? {};
          photoURL = userData?['photoURL'] ?? (userDoc.id == currentUser.uid ? currentUser.photoURL : null);
          loading = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar estatísticas: $e");
      if(mounted) setState(() => loading = false);
    }
  }

  // Função de mock para Wear OS (inalterada)
  Future<void> _loadMockData() async {
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      setState(() {
        totalDistance = 12.34;
        totalDuration = 4200;
        totalCalories = 870;
        userData = { 'displayName': 'Usuário Demo', 'city': 'Rio de Janeiro', 'state': 'RJ', };
        photoURL = null;
        loading = false;
      });
  }

  // Suas funções de formatação e detecção de Wear OS (inalteradas)
  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600; final m = (seconds % 3600) ~/ 60; final s = seconds % 60;
    if (h > 0) return '${h}h ${m}min';
    if (m > 0) return '${m}min ${s}s';
    return '${s}s';
  }

  bool get isWearOS {
    try { return Platform.isAndroid && MediaQuery.of(context).size.shortestSide < 300; }
    catch(e) { return false; }
  }


  @override
  Widget build(BuildContext context) {
    // A lógica de escolher a View correta
    return isWearOS ? _buildWearView() : _buildMobileView();
  }

  // ---------------------------------
  //  VIEW MOBILE (com as condições)
  // ---------------------------------
  Widget _buildMobileView() {
     return Scaffold(
      backgroundColor: Colors.grey[100],
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: primaryGreen,
                  expandedHeight: 220,
                  flexibleSpace: FlexibleSpaceBar(
                    titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                    title: Text(userData?['displayName'] ?? 'Perfil', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    background: Stack(fit: StackFit.expand, children: [
                      Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [primaryGreen, accentOrange], begin: Alignment.topLeft, end: Alignment.bottomRight))),
                      Align(alignment: Alignment.bottomLeft, child: Padding(padding: const EdgeInsets.all(16), child: CircleAvatar(radius: 45, backgroundColor: Colors.white.withOpacity(0.25), backgroundImage: (photoURL != null && photoURL!.isNotEmpty) ? NetworkImage(photoURL!) : null, child: (photoURL == null || photoURL!.isEmpty) ? const Icon(Icons.person, color: Colors.white, size: 50) : null))),
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
                        // 4. ADICIONA O BOTÃO DE SEGUIR APENAS SE NÃO FOR O SEU PERFIL
                        if (!_isCurrentUserProfile)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 20.0),
                            child: _FollowButton(profileUserId: _profileUserId),
                          ),
                        _buildStatsGrid(),
                        const SizedBox(height: 25),
                        _buildUserDetails(),
                        const SizedBox(height: 40),
                        // 5. MOSTRA O BOTÃO DE LOGOUT APENAS SE FOR O SEU PERFIL
                        if (_isCurrentUserProfile)
                          _buildLogoutButton(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ---------------------------------
  //  TODOS OS SEUS WIDGETS ORIGINAIS
  // ---------------------------------
  Widget _buildInfoCard() {
    final email = _isCurrentUserProfile ? FirebaseAuth.instance.currentUser?.email : userData?['email'];
    return Card(
      elevation: 5, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), color: Colors.white,
      child: Padding(padding: const EdgeInsets.all(18.0),
        child: Column(children: [
            Text(email ?? 'E-mail não disponível', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(userData?['city'] != null ? "${userData?['city']} - ${userData?['state'] ?? ''}" : "Localização não informada", style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    final List<Map<String, dynamic>> stats = [
      {'icon': Icons.directions_run, 'label': 'Distância Total', 'value': "${totalDistance.toStringAsFixed(2)} km", 'color': primaryGreen,},
      {'icon': Icons.access_time, 'label': 'Tempo Total', 'value': _formatDuration(totalDuration), 'color': accentOrange,},
      {'icon': Icons.local_fire_department, 'label': 'Calorias', 'value': "${totalCalories.toStringAsFixed(0)} kcal", 'color': softOrange,},
    ];
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: stats.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 12, mainAxisSpacing: 12),
      itemBuilder: (context, index) {
        final stat = stats[index]; final Color color = stat['color'] as Color;
        return Container(
          decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(15)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(stat['icon'] as IconData, color: color, size: 30), const SizedBox(height: 8),
              Text(stat['value'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), const SizedBox(height: 4),
              Text(stat['label'] as String, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],),
        );
      },
    );
  }

  Widget _buildUserDetails() {
    return Card(
      elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(padding: const EdgeInsets.all(16.0),
        child: Column(children: [
            _infoRow(Icons.person, 'Nome', userData?['displayName'] ?? 'Não informado'),
            _infoRow(Icons.calendar_today, 'Nascimento', userData?['birthDate'] ?? '—'),
            _infoRow(Icons.female, 'Gênero', userData?['gender'] ?? '—'),
            _infoRow(Icons.monitor_weight, 'Peso', '${userData?['weight'] ?? 0} kg'),
            _infoRow(Icons.height, 'Altura', '${userData?['height'] ?? 0} cm'),
            _infoRow(Icons.flag, 'Meta Semanal', '${userData?['weeklyGoal'] ?? 0} km'),
            _infoRow(Icons.home, 'CEP', userData?['cep'] ?? '—'),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(children: [
          Icon(icon, color: primaryGreen), const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
          Text(value, style: const TextStyle(fontSize: 14, color: Colors.black87), overflow: TextOverflow.ellipsis),
        ],),
    );
  }

  Widget _buildLogoutButton() {
    return ElevatedButton.icon(
      icon: const Icon(Icons.logout), label: const Text('Sair da Conta'),
      style: ElevatedButton.styleFrom(backgroundColor: logoutRed, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      onPressed: () async {
        await FirebaseAuth.instance.signOut();
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (c) => const AuthGate()), (r) => false);
        }
      },
    );
  }
  
  // ---------------------------------
  //  VIEW WEAR OS (SEU CÓDIGO ORIGINAL)
  // ---------------------------------
  Widget _buildWearView() {
    // ... Seu código para o relógio ...
    return Scaffold(body: Center(child: Text("Wear OS Profile")));
  }
}

// ---------------------------------
//  WIDGET ISOLADO PARA O BOTÃO
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
    final doc = await FirebaseFirestore.instance.collection('users').doc(_currentUser.uid).collection('following').doc(widget.profileUserId).get();
    if (mounted) {
      setState(() {
        _isFollowing = doc.exists;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    setState(() => _isLoading = true);
    final currentUserRef = FirebaseFirestore.instance.collection('users').doc(_currentUser.uid);
    final targetUserRef = FirebaseFirestore.instance.collection('users').doc(widget.profileUserId);
    final newFollowingState = !_isFollowing;

    try {
      if (newFollowingState) {
        await currentUserRef.collection('following').doc(widget.profileUserId).set({'timestamp': FieldValue.serverTimestamp()});
        await targetUserRef.collection('followers').doc(_currentUser.uid).set({'timestamp': FieldValue.serverTimestamp()});
        await targetUserRef.collection('notifications').add({
          'type': 'follow',
          'followerId': _currentUser.uid,
          'message': '${_currentUser.displayName ?? 'Alguém'} começou a seguir você.',
          'timestamp': FieldValue.serverTimestamp(),
        });
      } else {
        await currentUserRef.collection('following').doc(widget.profileUserId).delete();
        await targetUserRef.collection('followers').doc(_currentUser.uid).delete();
      }
      if(mounted) setState(() => _isFollowing = newFollowingState);
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(height: 48, child: Center(child: CircularProgressIndicator()));
    }
    return ElevatedButton(
      onPressed: _toggleFollow,
      style: ElevatedButton.styleFrom(
        backgroundColor: _isFollowing ? Colors.grey[700] : Theme.of(context).colorScheme.primary,
        foregroundColor: _isFollowing ? Colors.white : Colors.black,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(_isFollowing ? 'Deixar de Seguir' : 'Seguir', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }
}
