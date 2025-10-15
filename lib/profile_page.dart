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
  String? photoURL; // 👈 nova variável para armazenar a foto de perfil

  @override
  void initState() {
    super.initState();
    _loadUserStats();
  }

  Future<void> _loadUserStats() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // 👇 Carrega os dados das corridas
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

      // 👇 Busca o photoURL do usuário na coleção "user"
      final userDoc = await FirebaseFirestore.instance
          .collection('user')
          .doc(user.uid)
          .get();

      final userData = userDoc.data();
      final url = userData?['photoURL'] as String?;

      setState(() {
        totalDistance = distance;
        totalDuration = duration;
        totalCalories = calories;
        photoURL = url;
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
      appBar: AppBar(
        title: const Text('Meu Perfil'),
        centerTitle: true,
        backgroundColor: Colors.pinkAccent,
      ),
      backgroundColor: Colors.grey[100],
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 20),

            // 👇 Exibe a foto do perfil
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.pinkAccent,
              backgroundImage: (photoURL != null && photoURL!.isNotEmpty)
                  ? NetworkImage(photoURL!)
                  : null,
              child: (photoURL == null || photoURL!.isEmpty)
                  ? const Icon(Icons.person, color: Colors.white, size: 60)
                  : null,
            ),

            const SizedBox(height: 15),
            Text(
              user?.email ?? 'Usuário não identificado',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 30),
            _buildStatCard(
                icon: Icons.directions_run,
                label: "Distância Total",
                value: "${totalDistance.toStringAsFixed(2)} km"),
            _buildStatCard(
                icon: Icons.access_time,
                label: "Tempo Total",
                value: _formatDuration(totalDuration)),
            _buildStatCard(
                icon: Icons.local_fire_department,
                label: "Calorias Queimadas",
                value: "${totalCalories.toStringAsFixed(0)} kcal"),
            const Spacer(),
            ElevatedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Sair da Conta'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil('/', (r) => false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: Colors.pinkAccent, size: 30),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(value, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}
