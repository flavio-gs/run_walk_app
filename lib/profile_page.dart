import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  double totalDistance = 0;
  int totalDuration = 0;
  double totalCalories = 0;
  bool loading = true;
  String? photoURL;
  Map<String, dynamic>? userData;

  final Color primaryGreen = const Color(0xFF00C853);
  final Color accentOrange = const Color(0xFFFF6D00);
  final Color lightGreen = const Color(0xFF00E676);
  final Color softOrange = const Color(0xFFFF9100);
  final Color logoutRed = const Color(0xFFE53935);

  @override
  void initState() {
    super.initState();
    _loadUserStats();
  }

  Future<void> _loadUserStats() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Corridas
      final query = await FirebaseFirestore.instance
          .collection('corridas')
          .where('userId', isEqualTo: user.uid)
          .get();

      double distance = 0;
      int duration = 0;
      double calories = 0;

      for (var doc in query.docs) {
        final data = doc.data();
        distance += (data['distance'] as num?)?.toDouble() ?? 0.0;
        duration += (data['duration'] as num?)?.toInt() ?? 0;
        calories += (data['calories'] as num?)?.toDouble() ?? 0.0;
      }

      // Usuário
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      setState(() {
        totalDistance = distance;
        totalDuration = duration;
        totalCalories = calories;
        userData = userDoc.data() ?? {};
        photoURL = userData?['photoURL'] ?? user.photoURL;
        loading = false;
      });
    } catch (e) {
      debugPrint("Erro ao carregar estatísticas: $e");
      setState(() => loading = false);
    }
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}min';
    } else if (minutes > 0) {
      return '${minutes}min ${secs}s';
    } else {
      return '${secs}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

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
              title: Text(
                userData?['displayName'] ??
                    user?.email?.split('@')[0] ??
                    'Meu Perfil',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryGreen, accentOrange],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: CircleAvatar(
                        radius: 45,
                        backgroundColor: Colors.white.withOpacity(0.25),
                        backgroundImage: (photoURL != null && photoURL!.isNotEmpty)
                            ? NetworkImage(photoURL!)
                            : null,
                        child: (photoURL == null || photoURL!.isEmpty)
                            ? const Icon(Icons.person,
                            color: Colors.white, size: 50)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Corpo principal
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildInfoCard(),
                  const SizedBox(height: 20),
                  _buildStatsGrid(),
                  const SizedBox(height: 25),
                  _buildUserDetails(),
                  const SizedBox(height: 40),
                  _buildLogoutButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'Usuário não identificado';
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          children: [
            Text(
              email,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
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
        'label': 'Distância Total',
        'value': "${totalDistance.toStringAsFixed(2)} km",
        'color': primaryGreen,
      },
      {
        'icon': Icons.access_time,
        'label': 'Tempo Total',
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
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final stat = stats[index];
        final Color color = stat['color'] as Color;
        return Container(
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(stat['icon'] as IconData, color: color, size: 30),
              const SizedBox(height: 8),
              Text(stat['value'] as String,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, color: primaryGreen),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
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
          Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
        }
      },
    );
  }
}
